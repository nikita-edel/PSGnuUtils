BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'yes' {
    It 'repeats y' {
        @(Invoke-GnuYes | Select-Object -First 3) | Should -Be @('y', 'y', 'y')
    }

    It 'repeats all operands joined with spaces' {
        @(Invoke-GnuYes hello world | Select-Object -First 2) | Should -Be @('hello world', 'hello world')
    }

    It 'treats arguments after the first operand as text' {
        @(Invoke-GnuYes a -n | Select-Object -First 1) | Should -Be @('a -n')
        @(Invoke-GnuYes '--' '-n' | Select-Object -First 1) | Should -Be @('-n')
    }

    It 'rejects options' {
        $r = Invoke-TestGnu yes '-n'
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match "invalid option -- 'n'"
    }

    It 'supports --help' {
        (Invoke-TestGnu yes '--help').Output[0] | Should -Match '^Usage: yes'
    }
}
