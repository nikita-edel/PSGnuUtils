BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'basename' {
    It 'strips the directory' {
        (Invoke-TestGnu basename '/usr/bin/sort').Output | Should -Be @('sort')
        (Invoke-TestGnu basename 'include/').Output | Should -Be @('include')
        (Invoke-TestGnu basename '/').Output | Should -Be @('/')
    }

    It 'removes a suffix given as second operand' {
        (Invoke-TestGnu basename 'include/stdio.h', '.h').Output | Should -Be @('stdio')
        (Invoke-TestGnu basename '.h', '.h').Output | Should -Be @('.h')
    }

    It 'handles several names with -a / --multiple' {
        (Invoke-TestGnu basename '-a', 'a/x', 'b/y').Output | Should -Be @('x', 'y')
        (Invoke-TestGnu basename '--multiple', 'a/x').Output | Should -Be @('x')
    }

    It 'removes a suffix from every name with -s / --suffix (implies -a)' {
        (Invoke-TestGnu basename '-s', '.h', 'a/b.h', 'c.h').Output | Should -Be @('b', 'c')
        (Invoke-TestGnu basename '--suffix=.txt', 'x.txt').Output | Should -Be @('x')
    }

    It 'ends records with NUL for -z / --zero' {
        (Invoke-TestGnu basename '-z', '-a', 'a/x', 'b/y').Output | Should -Be @("x`0y`0")
        (Invoke-TestGnu basename '--zero', 'a/x').Output | Should -Be @("x`0")
    }

    It 'treats backslash as a separator on Windows only' {
        $expected = 'C:\dir\file.txt'
        if (Test-IsWindowsPlatform) { $expected = 'file.txt' }
        (Invoke-TestGnu basename 'C:\dir\file.txt').Output | Should -Be @($expected)
    }

    It 'reports missing and extra operands' {
        $r = Invoke-TestGnu basename
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match 'missing operand'
        (Invoke-TestGnu basename 'a', 'b', 'c').ErrorText | Should -Match "extra operand 'c'"
    }
}
