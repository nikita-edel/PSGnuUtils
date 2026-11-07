BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'sleep' {
    It 'sleeps for the sum of its operands' {
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-TestGnu sleep '0.1', '0.1s'
        $watch.Stop()
        $r.ExitCode | Should -Be 0
        $watch.Elapsed.TotalMilliseconds | Should -BeGreaterOrEqual 190
    }

    It 'accepts the m, h and d suffixes and zero values' {
        $r = Invoke-TestGnu sleep '0m', '0h', '0d', '0', '.0', '0e3'
        $r.ExitCode | Should -Be 0
        $r.Errors.Count | Should -Be 0
    }

    It 'rejects invalid intervals' {
        $r = Invoke-TestGnu sleep 'abc', '1x'
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match "invalid time interval 'abc'"
        $r.ErrorText | Should -Match "invalid time interval '1x'"
        $r.ErrorText | Should -Match "Try 'sleep --help'"
    }

    It 'reports a missing operand' {
        $r = Invoke-TestGnu sleep
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match 'missing operand'
    }
}
