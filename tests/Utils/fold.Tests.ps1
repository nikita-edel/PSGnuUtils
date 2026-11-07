BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'fold' {
    It 'wraps at 80 columns by default' {
        $r = Invoke-TestGnu fold -InputObject ('x' * 100)
        $r.Output | Should -Be @(('x' * 80), ('x' * 20))
    }

    It 'wraps at WIDTH with -w / --width and -NUM' {
        (Invoke-TestGnu fold '-w', '3' -InputObject 'abcdefg').Output | Should -Be @('abc', 'def', 'g')
        (Invoke-TestGnu fold '--width=4' -InputObject 'abcdefg').Output | Should -Be @('abcd', 'efg')
        (Invoke-TestGnu fold '-2' -InputObject 'abc').Output | Should -Be @('ab', 'c')
    }

    It 'keeps short and empty lines' {
        (Invoke-TestGnu fold '-w', '5' -InputObject 'abc', '', 'abcde').Output | Should -Be @('abc', '', 'abcde')
    }

    It 'counts tabs to the next multiple of 8, backspace and carriage return' {
        (Invoke-TestGnu fold '-w', '8' -InputObject "a`tb").Output | Should -Be @("a`t", 'b')
        (Invoke-TestGnu fold '-w', '2' -InputObject "ab`bc").Output | Should -Be @("ab`bc")
        (Invoke-TestGnu fold '-w', '2' -InputObject "ab`rcd").Output | Should -Be @("ab`rcd")
    }

    It 'counts every character as one column with -b / --bytes' {
        (Invoke-TestGnu fold '-b', '-w', '2' -InputObject "a`tb").Output | Should -Be @("a`t", 'b')
        (Invoke-TestGnu fold '--bytes', '-w', '2' -InputObject "ab`bc").Output | Should -Be @('ab', "`bc")
    }

    It 'breaks at the last blank with -s / --spaces' {
        (Invoke-TestGnu fold '-s', '-w', '8' -InputObject 'hello world foo').Output | Should -Be @('hello ', 'world ', 'foo')
        (Invoke-TestGnu fold '--spaces', '-w', '3' -InputObject 'abcdef').Output | Should -Be @('abc', 'def')
    }

    It 'reads files' {
        $file = New-TestFile -Path (Join-Path $TestDrive 'fold.txt') -Content "123456`n"
        (Invoke-TestGnu fold '-w', '4', $file).Output | Should -Be @('1234', '56')
        (Invoke-TestGnu fold (Join-Path $TestDrive 'missing')).ErrorText | Should -Match 'No such file or directory'
    }

    It 'rejects invalid widths' {
        $r = Invoke-TestGnu fold '-w', 'x' -InputObject 'a'
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match "invalid number of columns: 'x'"
        (Invoke-TestGnu fold '-w', '0' -InputObject 'a').ErrorText | Should -Match "invalid number of columns: '0'"
    }
}
