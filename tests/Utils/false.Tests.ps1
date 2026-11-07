BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'false' {
    It 'exits with 1 and prints nothing' {
        $r = Invoke-TestGnu false 'ignored'
        $r.ExitCode | Should -Be 1
        $r.Output.Count | Should -Be 0
        $r.Errors.Count | Should -Be 0
    }

    It 'exits with 1 even for --help and --version' {
        $r = Invoke-TestGnu false '--help'
        $r.Output[0] | Should -Match '^Usage: false'
        $r.ExitCode | Should -Be 1
        (Invoke-TestGnu false '--version').ExitCode | Should -Be 1
    }
}
