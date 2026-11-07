BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'dirname' {
    It 'strips the last component' {
        (Invoke-TestGnu dirname '/usr/bin/').Output | Should -Be @('/usr')
        (Invoke-TestGnu dirname 'dir1/str', 'dir2/str', 'stdio.h').Output | Should -Be @('dir1', 'dir2', '.')
        (Invoke-TestGnu dirname '/').Output | Should -Be @('/')
    }

    It 'ends records with NUL for -z / --zero' {
        (Invoke-TestGnu dirname '-z', 'a/b', 'c/d').Output | Should -Be @("a`0c`0")
        (Invoke-TestGnu dirname '--zero', 'a/b').Output | Should -Be @("a`0")
    }

    It 'keeps the drive root on Windows' {
        if (-not (Test-IsWindowsPlatform)) { Set-ItResult -Skipped -Because 'Windows only' }
        (Invoke-TestGnu dirname 'C:\foo').Output | Should -Be @('C:\')
        (Invoke-TestGnu dirname 'C:\foo\bar').Output | Should -Be @('C:\foo')
    }

    It 'reports a missing operand' {
        $r = Invoke-TestGnu dirname
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match 'missing operand'
    }
}
