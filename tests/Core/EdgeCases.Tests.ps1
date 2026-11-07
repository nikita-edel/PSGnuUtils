BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'Console standard input (no pipeline input)' {
    It 'cat reads the console when there are no operands' {
        $r = Use-TestConsoleInput -Text "one`ntwo`n" -Script { Invoke-TestGnu cat }
        $r.Output | Should -Be @('one', 'two')
    }

    It 'tee copies the console input to files and the output' {
        $file = Join-Path $TestDrive 'console-tee.txt'
        $r = Use-TestConsoleInput -Text "x`n" -Script { Invoke-TestGnu tee $file }
        $r.Output | Should -Be @('x')
        [System.IO.File]::ReadAllText($file) | Should -BeExactly "x`n"
    }

    It 'wc counts the console input' {
        (Use-TestConsoleInput -Text "a b`n" -Script { Invoke-TestGnu wc '-w' }).Output | Should -Be @('2')
    }
}

Describe 'Pipeline objects in buffered and streaming utils' {
    It 'renders objects when stdin is read later (tac)' {
        $r = Invoke-TestGnu tac -InputObject ([pscustomobject]@{ Column = 'value1' })
        $r.Output[0] | Should -Match 'value1'
        $r.Output[-1] | Should -Match '^Column$'
    }

    It 'renders objects that arrive last in streaming mode (head)' {
        $r = Invoke-TestGnu head '-n', '1' -InputObject ([pscustomobject]@{ Column = 'value1' })
        $r.Output | Should -Be @('Column')
    }

    It 'limits standard input read through - (head -n 1 - file)' {
        $file = New-TestFile -Path (Join-Path $TestDrive 'h.txt') -Content "f1`nf2`n"
        $r = Invoke-TestGnu head '-q', '-n', '1', '-', $file -InputObject 'p1', 'p2'
        $r.Output | Should -Be @('p1', 'f1')
    }
}

Describe 'Unreadable files' {
    BeforeAll {
        $script:lockedPath = New-TestFile -Path (Join-Path $TestDrive 'locked.txt') -Content "secret`n"
        $script:lock = Lock-TestFile -Path $lockedPath
    }
    AfterAll {
        if ($null -ne $lock) { $lock.Dispose() }
    }
    BeforeEach {
        if ($null -eq $lock) { Set-ItResult -Skipped -Because 'this OS does not enforce exclusive file locks' }
    }

    It 'reports read errors for line, text, byte and stream readers' -ForEach @(
        @{ Util = 'cat'; Arguments = @() }
        @{ Util = 'tac'; Arguments = @() }
        @{ Util = 'base64'; Arguments = @() }
        @{ Util = 'md5sum'; Arguments = @() }
    ) {
        $r = Invoke-TestGnu $Util (@($Arguments) + $lockedPath)
        $r.ExitCode | Should -Be 1
        $r.Errors.Count | Should -Be 1
        $r.ErrorText | Should -Match ([regex]::Escape($lockedPath))
    }

    It 'stays silent for unreadable files with md5sum -c --status' {
        $list = New-TestFile -Path (Join-Path $TestDrive 'locked.sums') -Content "d41d8cd98f00b204e9800998ecf8427e  $lockedPath`n"
        $r = Invoke-TestGnu md5sum '-c', '--status', $list
        $r.ExitCode | Should -Be 1
        $r.Errors.Count | Should -Be 0
    }

    It 'reports when unlink cannot delete a file' {
        $r = Invoke-TestGnu unlink $lockedPath
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match "cannot unlink '.*locked.txt'"
    }
}

Describe 'File system failures' {
    It 'link reports a target in a missing directory' {
        $source = New-TestFile -Path (Join-Path $TestDrive 'link-src.txt') -Content 'x'
        $r = Invoke-TestGnu link $source, (Join-Path $TestDrive 'no-such-dir/target.txt')
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match "cannot create link"
    }

    It 'mkdir reports names the file system rejects (Windows)' {
        if (-not (Test-IsWindowsPlatform)) { Set-ItResult -Skipped -Because 'Windows only' }
        $r = Invoke-TestGnu mkdir 'bad|name' -WorkingDirectory $TestDrive
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match "cannot create directory 'bad\|name'"
    }

    It 'rmdir reports directories that cannot be removed (Windows: process working directory)' {
        if (-not (Test-IsWindowsPlatform)) { Set-ItResult -Skipped -Because 'Windows only' }
        $busy = Join-Path $TestDrive 'busy-cwd'
        $null = New-Item -ItemType Directory -Path $busy
        $saved = [System.Environment]::CurrentDirectory
        [System.Environment]::CurrentDirectory = $busy
        try { $r = Invoke-TestGnu rmdir $busy }
        finally { [System.Environment]::CurrentDirectory = $saved }
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match 'failed to remove'
    }
}

Describe 'Platform helpers with explicit input' {
    It 'maps <Architecture> on <Platform> to <Expected>' -ForEach @(
        @{ Architecture = 'X64'; Platform = 'Linux'; Expected = 'x86_64' }
        @{ Architecture = 'AMD64'; Platform = 'Windows'; Expected = 'x86_64' }
        @{ Architecture = 'X86'; Platform = 'Windows'; Expected = 'i686' }
        @{ Architecture = 'Arm64'; Platform = 'Linux'; Expected = 'aarch64' }
        @{ Architecture = 'Arm64'; Platform = 'MacOS'; Expected = 'arm64' }
        @{ Architecture = 'Arm'; Platform = 'Linux'; Expected = 'armv7l' }
        @{ Architecture = 'S390x'; Platform = 'Linux'; Expected = 's390x' }
        @{ Architecture = ''; Platform = 'Linux'; Expected = 'unknown' }
    ) {
        InModuleScope PSGnuUtils -Parameters @{ A = $Architecture; P = $Platform } {
            param($A, $P)
            Get-GnuMachineName -Architecture $A -Platform $P
        } | Should -Be $Expected
    }

    It 'parses the OS description on <Platform>' -ForEach @(
        @{ Platform = 'Linux'; Description = 'Linux 6.8.0-45-generic #45-Ubuntu SMP PREEMPT_DYNAMIC'; Kernel = 'Linux'; Release = '6.8.0-45-generic'; Version = '#45-Ubuntu SMP PREEMPT_DYNAMIC'; Os = 'GNU/Linux' }
        @{ Platform = 'MacOS'; Description = 'Darwin 23.1.0 Darwin Kernel Version 23.1.0'; Kernel = 'Darwin'; Release = '23.1.0'; Version = 'Darwin Kernel Version 23.1.0'; Os = 'Darwin' }
        @{ Platform = 'Unix'; Description = 'FreeBSD 14.0-RELEASE'; Kernel = 'FreeBSD'; Release = '14.0-RELEASE'; Version = ''; Os = 'FreeBSD' }
        @{ Platform = 'Windows'; Description = 'Microsoft Windows 10.0.26100'; Kernel = 'Windows_NT'; Release = [System.Environment]::OSVersion.Version.ToString(); Version = 'Microsoft Windows 10.0.26100'; Os = 'Windows' }
    ) {
        $info = InModuleScope PSGnuUtils -Parameters @{ P = $Platform; D = $Description } { param($P, $D) Get-GnuOsInfo -Platform $P -Description $D }
        $info.KernelName | Should -Be $Kernel
        $info.KernelRelease | Should -Be $Release
        $info.KernelVersion | Should -Be $Version
        $info.OperatingSystem | Should -Be $Os
    }

    It 'falls back when the OS description is empty' {
        $info = InModuleScope PSGnuUtils { Get-GnuOsInfo -Platform 'Linux' -Description '' }
        $info.KernelName | Should -Be 'Unix'
        $info.KernelVersion | Should -Be ''
    }

    It 'uses only / as separator outside Windows' {
        InModuleScope PSGnuUtils {
            Mock Test-GnuWindows { $false }
            @(Get-GnuPathSeparator) | Should -Be @([char]'/')
        }
    }

}

Describe 'Framework error paths' {
    It 'throws for utils that are not registered' {
        { InModuleScope PSGnuUtils { Initialize-GnuUtil -Name 'not-registered' -Arguments @() -ExpectingInput $false } } | Should -Throw '*is not registered*'
    }

    It 'uses the synopsis when a spec has no description' {
        $lines = InModuleScope PSGnuUtils {
            $spec = @{ Name = 'demo'; Synopsis = 'Demo synopsis.'; Usage = @('demo'); Description = @(); Notes = @(); Options = @(); FunctionName = 'Invoke-GnuDemo' }
            @(Get-GnuHelpText -Spec $spec)
        }
        $lines[1] | Should -Be 'Demo synopsis.'
    }

    It 'resolves an empty path to an empty string' {
        InModuleScope PSGnuUtils { Resolve-GnuPath -Path '' } | Should -BeExactly ''
    }

    It 'reports nothing shadowed for names without any command' {
        InModuleScope PSGnuUtils { Get-GnuShadowedCommand -Name 'psgnuutils-no-such-command' } | Should -BeNullOrEmpty
    }

    It 'honors NoClobber in the import configuration' {
        Set-Alias -Name seq -Value Get-Date -Scope Global -Force
        try {
            InModuleScope PSGnuUtils { Invoke-GnuImportConfiguration -Configuration @{ Name = 'seq'; NoClobber = $true } }
            (Get-Alias -Name seq -Scope Global).Definition | Should -Be 'Get-Date'
        }
        finally {
            Disable-GnuUtil -All
            Remove-Item -LiteralPath 'Alias:\seq' -Force -ErrorAction SilentlyContinue
        }
    }

    It 'reports alias failures when enabling' {
        InModuleScope PSGnuUtils {
            Mock Set-Alias { throw 'alias refused' }
            Enable-GnuUtil -Name tac -ErrorVariable failures -ErrorAction SilentlyContinue
            "$failures" | Should -Match "cannot enable 'tac': alias refused"
            $script:GnuEnabledUtils.ContainsKey('tac') | Should -BeFalse
        }
    }

    # Separate test: a Pester mock stays active for the whole It block.
    It 'reports alias failures when restoring on disable' {
        Set-Alias -Name seq -Value Get-Date -Scope Global -Force
        Enable-GnuUtil -Name seq
        try {
            InModuleScope PSGnuUtils {
                Mock Set-Alias { throw 'restore refused' }
                Disable-GnuUtil -Name seq -ErrorVariable failures -ErrorAction SilentlyContinue
                "$failures" | Should -Match "cannot restore 'seq': restore refused"
                $script:GnuEnabledUtils.ContainsKey('seq') | Should -BeFalse
            }
        }
        finally {
            Remove-Item -LiteralPath 'Alias:\seq' -Force -ErrorAction SilentlyContinue
        }
    }
}
