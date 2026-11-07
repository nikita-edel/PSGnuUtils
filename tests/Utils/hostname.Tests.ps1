BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'hostname' {
    It 'prints the host name' {
        $r = Invoke-TestGnu hostname
        $r.Output | Should -Be @([System.Net.Dns]::GetHostName())
        $r.ExitCode | Should -Be 0
    }

    It 'does not support setting the host name' {
        $r = Invoke-TestGnu hostname 'newname'
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match "cannot set name to 'newname'"
    }

    It 'rejects extra operands' {
        (Invoke-TestGnu hostname 'a', 'b').ErrorText | Should -Match "extra operand 'b'"
    }
}
