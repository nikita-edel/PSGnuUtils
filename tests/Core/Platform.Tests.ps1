BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# Code paths of other runtimes and platforms (Windows PowerShell 5.1, Linux, macOS), exercised everywhere
# through their injectable parameters.
Describe 'Platform-specific code paths' {
    It 'kills a process without its tree (.NET Framework has no Kill(bool))' {
        $info = New-Object System.Diagnostics.ProcessStartInfo -ArgumentList (Get-Process -Id $PID).Path
        $info.Arguments = '-NoProfile -Command Start-Sleep 60'
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $process = [System.Diagnostics.Process]::Start($info)
        try {
            InModuleScope PSGnuUtils -Parameters @{ Process = $process } { param($Process) Stop-GnuProcess -Process $Process -NoTree }
            $process.WaitForExit(10000) | Should -BeTrue
        }
        finally { if (-not $process.HasExited) { $process.Kill() } }
    }

    It 'builds a quoted command line when ArgumentList is not used' {
        InModuleScope PSGnuUtils {
            (New-GnuProcessStartInfo -Path 'prog' -Arguments @('a b', 'c') -CommandLine).Arguments | Should -Be '"a b" c'
            $backslash = [string][char]92
            ConvertTo-GnuCommandLine -Arguments @('a' + $backslash + 'b c') | Should -Be ('"a' + $backslash + 'b c"')
        }
    }

    It 'reports a failure to signal a process' {
        $info = New-Object System.Diagnostics.ProcessStartInfo -ArgumentList (Get-Process -Id $PID).Path
        $info.Arguments = '-NoProfile -Command Start-Sleep 60'
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $process = [System.Diagnostics.Process]::Start($info)
        try {
            InModuleScope PSGnuUtils -Parameters @{ Id = $process.Id } {
                param($Id)
                Mock Test-GnuWindows { $true }
                Mock Stop-GnuProcess { throw [System.UnauthorizedAccessException]::new('denied') }
                Send-GnuSignal -Id $Id -Signal @{ Name = 'TERM'; Number = 15 } | Should -Be 'Permission denied'
            }
        }
        finally { $process.Kill() }
    }

    It 'uses the Linux identity when /proc/self/status exists' {
        $status = New-TestFile -Path (Join-Path $TestDrive 'status') -Content "Uid:`t1`t1`t1`t1`n"
        InModuleScope PSGnuUtils -Parameters @{ Status = $status } {
            param($Status)
            Mock Test-GnuWindows { $false }
            Mock Get-GnuLinuxIdentity { @{ UserId = 'from-proc' } }
            (Get-GnuIdentity -StatusPath $Status).UserId | Should -Be 'from-proc'
        }
    }

    It 'asks the system id command on other Unix systems' {
        function global:Invoke-PSGnuFakeId {
            switch -CaseSensitive ($args[0]) {
                '-u' { if ($args -contains 'ghost') { return }; '501' }
                '-un' { 'alice' }
                '-g' { '20' }
                '-gn' { 'staff' }
                '-G' { '20 12' }
                '-Gn' { 'staff everyone' }
            }
        }
        try {
            InModuleScope PSGnuUtils {
                $identity = Get-GnuNativeIdentity -IdCommand 'Invoke-PSGnuFakeId'
                $identity.UserId | Should -Be '501'
                $identity.UserName | Should -Be 'alice'
                $identity.GroupName | Should -Be 'staff'
                @($identity.Groups | ForEach-Object { "$($_.Id)=$($_.Name)" }) | Should -Be @('20=staff', '12=everyone')
                (Get-GnuNativeIdentity -User 'bob' -Real -IdCommand 'Invoke-PSGnuFakeId').UserId | Should -Be '501'
                Get-GnuNativeIdentity -User 'ghost' -IdCommand 'Invoke-PSGnuFakeId' | Should -BeNullOrEmpty
            }
        }
        finally { Remove-Item -Path Function:\Invoke-PSGnuFakeId }
    }

    It 'reads Unix mode strings from the UnixMode property' {
        InModuleScope PSGnuUtils {
            Mock Test-GnuWindows { $false }
            Mock Get-Item { [pscustomobject]@{ UnixMode = 'crw-rw-rw-' } }
            Get-GnuUnixModeString -Path 'x' | Should -Be 'crw-rw-rw-'
        }
    }

    It 'counts users and reads load averages through who and sysctl' {
        function global:Invoke-PSGnuFakeSysctl { '{ 1.50 2.25 3.00 }' }
        function global:Invoke-PSGnuFakeWho { 'alice console'; 'bob ttys001' }
        $global:PSGnuFakeCommands = @{ sysctl = (Get-Command Invoke-PSGnuFakeSysctl); who = (Get-Command Invoke-PSGnuFakeWho) }
        try {
            InModuleScope PSGnuUtils {
                Mock Test-GnuWindows { $false }
                Mock Get-Command { $global:PSGnuFakeCommands[$Name] }
                $load = Get-GnuLoadAverage -Path (Join-Path $TestDrive 'none')
                $load | Should -Be @(1.5, 2.25, 3.0)
                Get-GnuUserCount | Should -Be 2
            }
            InModuleScope PSGnuUtils {
                Mock Test-GnuWindows { $false }
                Mock Get-Command { }
                Get-GnuUserCount | Should -Be 0
            }
        }
        finally {
            Remove-Item -Path Function:\Invoke-PSGnuFakeSysctl, Function:\Invoke-PSGnuFakeWho
            Remove-Variable -Name PSGnuFakeCommands -Scope Global
        }
    }

    It 'stops renaming a shredded file that cannot be renamed' {
        $file = New-TestFile -Path (Join-Path (New-Item -ItemType Directory -Path (Join-Path $TestDrive 'shred-guard')).FullName 'locked-shred') -Content 'x'
        $stream = Block-TestFileRemoval -Path $file
        try {
            $messages = InModuleScope PSGnuUtils -Parameters @{ File = $file } {
                param($File)
                $ctx = @{ Name = 'shred'; ExitCode = 0; ErrorCount = 0; Spec = @{ UsageExitCode = 1 } }
                Remove-GnuShreddedFile -Context $ctx -Operand $File -How 'wipe' 2>&1 | ForEach-Object { "$_" }
            }
            $messages | Should -Match 'failed to remove'
        }
        finally { $stream.Dispose() }
    }
}

Describe 'Test-GnuPathExists' {
    It 'follows links like stat()' {
        $file = New-TestFile -Path (Join-Path $TestDrive 'exists-target.txt') -Content 'x'
        InModuleScope PSGnuUtils -Parameters @{ F = $file } {
            param($F)
            Test-GnuPathExists -Path '' | Should -BeFalse
            Test-GnuPathExists -Path (Split-Path -Parent $F) | Should -BeTrue
            Test-GnuPathExists -Path ($F + '.missing') | Should -BeFalse
            Test-GnuPathExists -Path $F | Should -BeTrue
            Mock Get-GnuLinkTarget { 'nowhere.txt' } -ParameterFilter { $Path -eq $F }
            Test-GnuPathExists -Path $F | Should -BeFalse -Because 'a dangling link does not exist'
            Mock Get-GnuLinkTarget { 'exists-target.txt' } -ParameterFilter { $Path -eq $F }
            Test-GnuPathExists -Path $F | Should -BeFalse -Because 'a link to itself is a loop'
            Mock Get-GnuLinkTarget { (Split-Path -Parent $F) } -ParameterFilter { $Path -eq $F }
            Test-GnuPathExists -Path $F | Should -BeTrue
        }
    }
}
