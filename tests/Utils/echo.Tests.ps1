BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'echo' {
    It 'joins operands with spaces' {
        (Invoke-TestGnu echo 'hello', 'world').Output | Should -Be @('hello world')
    }

    It 'prints an empty line without operands' {
        (Invoke-TestGnu echo).Output | Should -Be @('')
    }

    It 'suppresses the trailing newline with -n' {
        (Invoke-TestGnu echo '-n', 'x').Output | Should -Be @('x')
        (Invoke-TestGnu echo '-n').Output.Count | Should -Be 0
    }

    It 'interprets escapes with -e' {
        (Invoke-TestGnu echo '-e', 'a\tb\nc').Output | Should -Be @("a`tb", 'c')
        (Invoke-TestGnu echo '-e', 'end\n').Output | Should -Be @('end', '')
        (Invoke-TestGnu echo '-n', '-e', 'end\n').Output | Should -Be @('end')
    }

    It 'stops at \c' {
        (Invoke-TestGnu echo '-e', 'ab\cde', 'more').Output | Should -Be @('ab')
    }

    It 'does not interpret escapes by default or with -E' {
        (Invoke-TestGnu echo 'a\tb').Output | Should -Be @('a\tb')
        (Invoke-TestGnu echo '-e', '-E', 'a\tb').Output | Should -Be @('a\tb')
        (Invoke-TestGnu echo '-neE', 'x').Output | Should -Be @('x')
    }

    It 'prints arguments that are not pure option clusters' {
        (Invoke-TestGnu echo '-nx', 'y').Output | Should -Be @('-nx y')
        (Invoke-TestGnu echo 'a', '-n').Output | Should -Be @('a -n')
        (Invoke-TestGnu echo '--', '-n').Output | Should -Be @('-- -n')
    }

    It 'only recognizes a sole --help' {
        (Invoke-TestGnu echo '--help').Output[0] | Should -Match '^Usage: echo'
        (Invoke-TestGnu echo '--help', 'x').Output | Should -Be @('--help x')
    }
}
