BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')

    function Start-TestSleeper {
        # A child PowerShell that sleeps for a minute.
        $info = New-Object System.Diagnostics.ProcessStartInfo -ArgumentList (Get-Process -Id $PID).Path
        $info.Arguments = '-NoProfile -Command Start-Sleep 60'
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        [System.Diagnostics.Process]::Start($info)
    }

    function Wait-TestExit {
        param([System.Diagnostics.Process]$Process)
        $Process.WaitForExit(10000)
    }
}

Describe 'kill' {
    It 'lists signal names with -l / --list' {
        $r = Invoke-TestGnu kill '-l'
        $r.Output[0..2] | Should -Be @('HUP', 'INT', 'QUIT')
        $r.Output | Should -Contain 'TERM'
        (Invoke-TestGnu kill '--list').Output.Count | Should -Be 31
    }

    It 'converts between names and numbers with -l' {
        (Invoke-TestGnu kill '-l', '9', 'KILL', 'SIGTERM', '137', 'io').Output | Should -Be @('KILL', '9', '15', 'KILL', '29')
        $r = Invoke-TestGnu kill '-l', 'FOO', '0', '1', '99'
        $r.Output | Should -Be @('HUP')
        $r.Errors | Should -Be @("kill: 'FOO': invalid signal", "kill: '0': invalid signal", "kill: '99': invalid signal")
        $r.ExitCode | Should -Be 1
    }

    It 'prints a table with -t / --table / -L' {
        (Invoke-TestGnu kill '-t').Output[0] | Should -Be ' 1 HUP    Hangup'
        (Invoke-TestGnu kill '--table', '9', 'TERM').Output | Should -Be @(' 9 KILL   Killed', '15 TERM   Terminated')
        (Invoke-TestGnu kill '-L', 'cld').Output | Should -Be @('17 CHLD   Child exited')
    }

    It 'terminates processes (default TERM, -s / --signal, -SIGNAL)' {
        foreach ($form in @(@(), @('-s', 'TERM'), @('--signal=KILL'), @('-sKILL'), @('-9'), @('-KILL'), @('--signal', 'INT'))) {
            $process = Start-TestSleeper
            try {
                $r = Invoke-TestGnu kill (@($form) + [string]$process.Id)
                $r.ErrorText | Should -BeNullOrEmpty
                $r.ExitCode | Should -Be 0
                Wait-TestExit $process | Should -BeTrue
            }
            finally { if (-not $process.HasExited) { $process.Kill() } }
        }
    }

    It 'only checks that a process exists with signal 0' {
        $process = Start-TestSleeper
        try {
            $r = Invoke-TestGnu kill '-0', ([string]$process.Id)
            $r.ErrorText | Should -BeNullOrEmpty
            $r.ExitCode | Should -Be 0
            $process.HasExited | Should -BeFalse
        }
        finally { $process.Kill() }
    }

    It 'reports bad process ids and signals' {
        $r = Invoke-TestGnu kill '999999', 'abc', '0', '-5'
        $r.Errors | Should -Be @("kill: '999999': No such process", "kill: 'abc': invalid process id", "kill: '0': process groups are not supported", "kill: '-5': process groups are not supported")
        $r.ExitCode | Should -Be 1
        (Invoke-TestGnu kill '--', '-5').ErrorText | Should -Match "'-5': process groups are not supported"
        (Invoke-TestGnu kill '-s', 'FOO', '1').ErrorText | Should -Match "'FOO': invalid signal"
        (Invoke-TestGnu kill '-s').ErrorText | Should -Match "option requires an argument -- 's'"
        $r = Invoke-TestGnu kill '-9'
        $r.ErrorText | Should -Match 'no process ID specified'
        $r.ExitCode | Should -Be 1
    }

    It 'uses kill(1) for other signals on Unix' {
        $process = Start-TestSleeper
        try {
            InModuleScope PSGnuUtils -Parameters @{ Id = $process.Id } {
                param($Id)
                Mock Test-GnuWindows { $false }
                Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
                Send-GnuSignal -Id $Id -Signal @{ Name = 'HUP'; Number = 1 } | Should -BeNullOrEmpty
                Should -Invoke Start-Process -Times 1 -ParameterFilter { $FilePath -eq 'kill' -and ($ArgumentList -join ' ') -eq "-s HUP $Id" }
            }
            InModuleScope PSGnuUtils -Parameters @{ Id = $process.Id } {
                param($Id)
                Mock Test-GnuWindows { $false }
                Mock Start-Process { [pscustomobject]@{ ExitCode = 1 } }
                Send-GnuSignal -Id $Id -Signal @{ Name = 'USR1'; Number = 10 } | Should -Be 'Operation not permitted'
            }
        }
        finally { $process.Kill() }
    }
}
