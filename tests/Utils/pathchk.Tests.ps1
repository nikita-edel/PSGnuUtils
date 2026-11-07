BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'pathchk' {
    It 'accepts ordinary names' {
        $r = Invoke-TestGnu pathchk 'dir/file.txt', 'a b'
        $r.ExitCode | Should -Be 0
        $r.Errors.Count | Should -Be 0
    }

    It 'rejects components and names over the default limits' {
        $long = 'a' * 256
        (Invoke-TestGnu pathchk "x/$long").ErrorText | Should -BeExactly "pathchk: limit 255 exceeded by length 256 of file name component '$long'"
        $deep = ('abcdefghi/' * 410)
        (Invoke-TestGnu pathchk $deep).ErrorText | Should -Match 'limit 4096 exceeded by length 4100 of file name'
    }

    It 'checks POSIX portability with -p' {
        (Invoke-TestGnu pathchk '-p', 'a b').ErrorText | Should -BeExactly "pathchk: nonportable character ' ' in file name 'a b'"
        (Invoke-TestGnu pathchk '-p', 'abcdefghijklmno').ErrorText | Should -Match 'limit 14 exceeded by length 15 of file name component'
        (Invoke-TestGnu pathchk '-p', ('abcdefghij/' * 24)).ErrorText | Should -Match 'limit 256 exceeded by length 264 of file name'
        (Invoke-TestGnu pathchk '-p', 'ok_name-1.txt').ExitCode | Should -Be 0
    }

    It 'checks empty names and leading dashes with -P' {
        (Invoke-TestGnu pathchk '-P', '').ErrorText | Should -BeExactly 'pathchk: empty file name'
        (Invoke-TestGnu pathchk '-P', '--', '-x').ErrorText | Should -BeExactly "pathchk: leading '-' in a component of file name '-x'"
        (Invoke-TestGnu pathchk '-P', 'a/-b').ErrorText | Should -Match 'leading'
    }

    It 'combines both checks with --portability' {
        (Invoke-TestGnu pathchk '--portability', 'a b').ErrorText | Should -Match 'nonportable character'
        (Invoke-TestGnu pathchk '--portability', '').ErrorText | Should -Match 'empty file name'
    }

    It 'reports an empty name without -P like a missing file' {
        (Invoke-TestGnu pathchk '').ErrorText | Should -Match "'': No such file or directory"
    }

    It 'checks every name and reports a missing operand' {
        $r = Invoke-TestGnu pathchk '-p', 'a b', 'c d'
        $r.Errors.Count | Should -Be 2
        $r.ExitCode | Should -Be 1
        (Invoke-TestGnu pathchk).ErrorText | Should -Match 'missing operand'
    }
}
