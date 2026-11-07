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

    It 'parses intervals into seconds' -ForEach @(
        @{ Text = '2'; Seconds = 2 }
        @{ Text = '1.5m'; Seconds = 90 }
        @{ Text = '2h'; Seconds = 7200 }
        @{ Text = '1d'; Seconds = 86400 }
        @{ Text = '.5s'; Seconds = 0.5 }
        @{ Text = '1e1'; Seconds = 10 }
    ) {
        InModuleScope PSGnuUtils -Parameters @{ T = $Text } { param($T) ConvertFrom-GnuSleepInterval -Text $T } | Should -Be $Seconds
    }

    It 'parses inf and infinity as an endless sleep' {
        InModuleScope PSGnuUtils {
            [double]::IsPositiveInfinity((ConvertFrom-GnuSleepInterval -Text 'inf')) | Should -BeTrue
            [double]::IsPositiveInfinity((ConvertFrom-GnuSleepInterval -Text 'infinity')) | Should -BeTrue
            ConvertFrom-GnuSleepInterval -Text '-1' | Should -BeNullOrEmpty
        }
    }
}
