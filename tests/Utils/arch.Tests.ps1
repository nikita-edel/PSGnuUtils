BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'arch' {
    It 'prints the same machine name as uname -m' {
        $r = Invoke-TestGnu arch
        $r.ExitCode | Should -Be 0
        $r.Output | Should -Be (Invoke-TestGnu uname '-m').Output
        $r.Output[0] | Should -Match '^(x86_64|i686|aarch64|arm64|armv7l|[a-z0-9_]+)$'
    }

    It 'rejects operands' {
        $r = Invoke-TestGnu arch 'x'
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match "extra operand 'x'"
    }
}
