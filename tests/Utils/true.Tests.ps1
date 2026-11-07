BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'true' {
    It 'exits with 0 and prints nothing' {
        $r = Invoke-TestGnu true
        $r.ExitCode | Should -Be 0
        $r.Output.Count | Should -Be 0
    }

    It 'ignores all arguments, including unknown options' {
        $r = Invoke-TestGnu true '-x', '--bogus', 'operand'
        $r.ExitCode | Should -Be 0
        $r.Errors.Count | Should -Be 0
    }

    It 'only recognizes a sole --help or --version' {
        (Invoke-TestGnu true '--help').Output[0] | Should -Match '^Usage: true'
        (Invoke-TestGnu true '--version').Output[0] | Should -Match '^true \(PSGnuUtils\)'
        (Invoke-TestGnu true '--help', 'x').Output.Count | Should -Be 0
    }
}
