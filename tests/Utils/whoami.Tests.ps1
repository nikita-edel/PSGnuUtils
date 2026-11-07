BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'whoami' {
    It 'prints the user name' {
        $r = Invoke-TestGnu whoami
        $r.Output | Should -Be @([System.Environment]::UserName)
        $r.ExitCode | Should -Be 0
    }

    It 'rejects operands' {
        $r = Invoke-TestGnu whoami 'x'
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match "extra operand 'x'"
    }
}
