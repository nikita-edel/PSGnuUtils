BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
    # The child program: this PowerShell executable (exists on every platform).
    $script:shell = (Get-Process -Id $PID).Path
}

Describe 'timeout' {
    It 'passes output and the exit code of a program that finishes in time' {
        $r = Invoke-TestGnu timeout '10', $shell, '-NoProfile', '-Command', 'echo one; echo two; exit 3'
        $r.Output | Should -Be @('one', 'two')
        $r.ExitCode | Should -Be 3
    }

    It 'writes pipeline input to the program' {
        (Invoke-TestGnu timeout '10', $shell, '-NoProfile', '-Command', '$input | ForEach-Object { "got:$_" }' -InputObject 'x', 'y').Output | Should -Be @('got:x', 'got:y')
    }

    It 'stops the program after DURATION with exit code 124 (-v / --verbose reports it)' {
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-TestGnu timeout '-v', '1', $shell, '-NoProfile', '-Command', 'echo start; Start-Sleep 30; echo never'
        $clock.Elapsed.TotalSeconds | Should -BeLessThan 20
        $r.Output | Should -Be @('start')
        $r.WarningText | Should -Match "sending signal TERM to command"
        $r.ExitCode | Should -Be 124
        (Invoke-TestGnu timeout '--verbose', '0.5s', $shell, '-NoProfile', '-Command', 'Start-Sleep 30').ExitCode | Should -Be 124
    }

    It 'exits with 137 for -s / --signal KILL and 128+SIGNAL with --preserve-status' {
        (Invoke-TestGnu timeout '-s', 'KILL', '1', $shell, '-NoProfile', '-Command', 'Start-Sleep 30').ExitCode | Should -Be 137
        (Invoke-TestGnu timeout '--signal=9', '1', $shell, '-NoProfile', '-Command', 'Start-Sleep 30').ExitCode | Should -Be 137
        (Invoke-TestGnu timeout '--preserve-status', '1', $shell, '-NoProfile', '-Command', 'Start-Sleep 30').ExitCode | Should -Be 143
        (Invoke-TestGnu timeout '--preserve-status', '10', $shell, '-NoProfile', '-Command', 'exit 5').ExitCode | Should -Be 5
    }

    It 'sends KILL after -k / --kill-after when the first signal is ignored' {
        Mock -ModuleName PSGnuUtils Send-GnuSignal { }
        $r = Invoke-TestGnu timeout '-v', '-k', '1', '1', $shell, '-NoProfile', '-Command', 'Start-Sleep 30'
        $r.WarningText | Should -Match 'sending signal KILL'
        $r.ExitCode | Should -Be 137
        (Invoke-TestGnu timeout '--kill-after=0.5', '0.5', $shell, '-NoProfile', '-Command', 'Start-Sleep 30').ExitCode | Should -Be 137
    }

    It 'disables the limit with DURATION 0 and accepts --foreground' {
        (Invoke-TestGnu timeout '--foreground', '0', $shell, '-NoProfile', '-Command', 'Start-Sleep -Milliseconds 1500; echo done').Output | Should -Be @('done')
    }

    It 'stops the program when the pipeline stops' {
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        @(Invoke-GnuTimeout 60 $shell -NoProfile -Command 'echo a; echo b; Start-Sleep 30' | Select-Object -First 1) | Should -Be @('a')
        $clock.Elapsed.TotalSeconds | Should -BeLessThan 20
    }

    It 'parses durations' {
        InModuleScope PSGnuUtils {
            ConvertFrom-GnuDuration -Text '5' | Should -Be 5
            ConvertFrom-GnuDuration -Text '1.5m' | Should -Be 90
            ConvertFrom-GnuDuration -Text '2h' | Should -Be 7200
            ConvertFrom-GnuDuration -Text '1d' | Should -Be 86400
            ConvertFrom-GnuDuration -Text '.5s' | Should -Be 0.5
            ConvertFrom-GnuDuration -Text '1x' | Should -BeNullOrEmpty
        }
    }

    It 'reports bad arguments (exit code 125)' {
        $r = Invoke-TestGnu timeout '5'
        $r.ErrorText | Should -Match 'missing operand'
        $r.ExitCode | Should -Be 125
        (Invoke-TestGnu timeout 'x', 'cmd').ErrorText | Should -Match "invalid time interval 'x'"
        (Invoke-TestGnu timeout '-k', 'y', '1', 'cmd').ErrorText | Should -Match "invalid time interval 'y'"
        $r = Invoke-TestGnu timeout '-s', 'FOO', '1', 'cmd'
        $r.ErrorText | Should -Match "'FOO': invalid signal"
        $r.ExitCode | Should -Be 125
    }

    It 'reports commands that cannot run (127 missing, 126 not a program)' {
        $r = Invoke-TestGnu timeout '1', 'no-such-command-xyz'
        $r.ErrorText | Should -Match "failed to run command 'no-such-command-xyz': No such file or directory"
        $r.ExitCode | Should -Be 127
        $r = Invoke-TestGnu timeout '1', 'Get-Date'
        $r.ErrorText | Should -Match 'not an external program'
        $r.ExitCode | Should -Be 126
        Mock -ModuleName PSGnuUtils New-GnuProcessStartInfo {
            $info = New-Object System.Diagnostics.ProcessStartInfo -ArgumentList (Join-Path $TestDrive 'missing.exe')
            $info.UseShellExecute = $false
            $info
        }
        $r = Invoke-TestGnu timeout '1', $shell
        $r.ErrorText | Should -Match 'failed to run command'
        $r.ExitCode | Should -Be 126
    }

    It 'quotes Windows command lines' {
        InModuleScope PSGnuUtils {
            $backslash = [string][char]92
            ConvertTo-GnuCommandLine -Arguments @('plain', 'a b', '', 'say "hi"', ('end' + $backslash), ('x' + $backslash + 'y')) |
                Should -Be ('plain "a b" "" "say ' + $backslash + '"hi' + $backslash + '"" end' + $backslash + ' x' + $backslash + 'y')
            ConvertTo-GnuCommandLine -Arguments @(('a' + $backslash + $backslash + '"b c')) | Should -Be ('"a' + ($backslash * 5) + '"b c"')
        }
    }

    It 'builds a command line when ArgumentList is not available' {
        InModuleScope PSGnuUtils {
            $info = New-GnuProcessStartInfo -Path 'prog' -Arguments @('a b', 'c')
            if ($null -ne $info.PSObject.Properties['ArgumentList']) { @($info.ArgumentList) | Should -Be @('a b', 'c') }
            else { $info.Arguments | Should -Be '"a b" c' }
        }
    }
}
