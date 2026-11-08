BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# Expected outputs come from GNU coreutils tr.
Describe 'tr' {
    It 'translates characters and ranges' {
        (Invoke-TestGnu tr 'a-z', 'A-Z' -InputObject 'Hello, World!').Output | Should -Be @('HELLO, WORLD!')
        (Invoke-TestGnu tr 'abc', 'x' -InputObject 'aabbcc d').Output | Should -Be @('xxxxxx d')
        (Invoke-TestGnu tr 'abc', 'xy' -InputObject 'abc').Output | Should -Be @('xyy')
    }

    It 'converts case with [:lower:] and [:upper:]' {
        (Invoke-TestGnu tr '[:lower:]', '[:upper:]' -InputObject 'abc XYZ').Output | Should -Be @('ABC XYZ')
        (Invoke-TestGnu tr '[:upper:]', '[:lower:]' -InputObject 'abc XYZ').Output | Should -Be @('abc xyz')
    }

    It 'interprets escapes and octal values' {
        (Invoke-TestGnu tr '\101-\103', 'abc' -InputObject 'ABCD').Output | Should -Be @('abcD')
        (Invoke-TestGnu tr '\n', ' ' -InputObject 'a', 'b').Output | Should -Be @('a b ')
        (Invoke-TestGnu tr '\t\\', '_/' -InputObject "a`tb\c").Output | Should -Be @('a_b/c')
        (Invoke-TestGnu tr '\a\b\f\v\r', 'abfvr' -InputObject "$([char]7)$([char]8)$([char]12)$([char]11)").Output | Should -Be @('abfv')
        (Invoke-TestGnu tr '\q', 'Q' -InputObject 'q').Output | Should -Be @('Q')
        # \400 is \40 (space) followed by '0'.
        (Invoke-TestGnu tr '\400', 'xy' -InputObject 'a 0').Output | Should -Be @('axy')
    }

    It 'fills STRING2 with [c*] and repeats with [c*n]' {
        (Invoke-TestGnu tr 'a-c', '[x*]' -InputObject 'abcd').Output | Should -Be @('xxxd')
        (Invoke-TestGnu tr 'a-f', '[x*2]yz' -InputObject 'abcdef').Output | Should -Be @('xxyzzz')
        (Invoke-TestGnu tr 'a-h', '[x*010]' -InputObject 'abh').Output | Should -Be @('xxx')
        (Invoke-TestGnu tr 'ab', '[x*0]' -InputObject 'ab').Output | Should -Be @('xx')
        (Invoke-TestGnu tr '[=a=]', 'Q' -InputObject 'banana').Output | Should -Be @('bQnQnQ')
    }

    It 'deletes with -d / --delete' {
        (Invoke-TestGnu tr '-d', '[:digit:]' -InputObject 'a1b2c3').Output | Should -Be @('abc')
        (Invoke-TestGnu tr '--delete', 'a-c' -InputObject 'abcdef').Output | Should -Be @('def')
    }

    It 'uses the complement with -c / -C / --complement' {
        (Invoke-TestGnu tr '-c', '[:alnum:]\n', '_' -InputObject 'a b!c').Output | Should -Be @('a_b_c')
        (Invoke-TestGnu tr '-C', '[:alpha:]\n', '-' -InputObject 'x1y').Output | Should -Be @('x-y')
        (Invoke-TestGnu tr '-d', '--complement', '[:alpha:]\n' -InputObject 'a1 b2').Output | Should -Be @('ab')
        # Characters above U+00FF become the last character of STRING2.
        (Invoke-TestGnu tr '-c', 'a\n', '?' -InputObject "a$([char]0x263A)b").Output | Should -Be @('a??')
    }

    It 'squeezes with -s / --squeeze-repeats' {
        (Invoke-TestGnu tr '-s', ' ' -InputObject 'a   b  c').Output | Should -Be @('a b c')
        (Invoke-TestGnu tr '--squeeze-repeats', 'a-z', 'A-Z' -InputObject 'aabbcc').Output | Should -Be @('ABC')
        (Invoke-TestGnu tr '-ds', 'a-c', 'o' -InputObject 'abooocd').Output | Should -Be @('od')
        (Invoke-TestGnu tr '-s', 'aA' -InputObject 'aaAA').Output | Should -Be @('aA')
        (Invoke-TestGnu tr '-cs', 'x' -InputObject "x$([char]0x263A)$([char]0x263A)yyx").Output | Should -Be @("x$([char]0x263A)yx")
    }

    It 'truncates STRING1 with -t / --truncate-set1' {
        (Invoke-TestGnu tr '-t', 'abcdef', 'xy' -InputObject 'abcdef').Output | Should -Be @('xycdef')
        (Invoke-TestGnu tr '--truncate-set1', 'abc', '' -InputObject 'abc').Output | Should -Be @('abc')
    }

    It 'reads the console without pipeline input' {
        (Use-TestConsoleInput -Text "abc`n" -Script { Invoke-TestGnu tr 'a', 'b' }).Output | Should -Be @('bbc')
    }

    It 'checks its operands' {
        (Invoke-TestGnu tr -InputObject 'a').ErrorText | Should -Match 'missing operand'
        (Invoke-TestGnu tr 'a' -InputObject 'a').ErrorText | Should -Match 'Two strings must be given when translating'
        (Invoke-TestGnu tr '-d', 'a', 'b' -InputObject 'a').ErrorText | Should -Match 'Only one string may be given when deleting without squeezing repeats'
        (Invoke-TestGnu tr '-ds', 'a' -InputObject 'a').ErrorText | Should -Match 'Two strings must be given when both deleting and squeezing repeats'
        (Invoke-TestGnu tr '-s', 'a', 'b', 'c' -InputObject 'a').ErrorText | Should -Match "extra operand 'c'"
    }

    It 'rejects invalid sets' {
        (Invoke-TestGnu tr '[:foo:]', 'x' -InputObject 'a').ErrorText | Should -Match "invalid character class 'foo'"
        (Invoke-TestGnu tr 'a', '[:foo:]' -InputObject 'a').ErrorText | Should -Match "invalid character class 'foo'"
        (Invoke-TestGnu tr 'z-a', 'x' -InputObject 'a').ErrorText | Should -Match "range-endpoints of 'z-a' are in reverse collating sequence order"
        (Invoke-TestGnu tr '\002-\001', 'x' -InputObject 'a').ErrorText | Should -Match ([regex]::Escape("range-endpoints of '\002-\001'"))
        (Invoke-TestGnu tr '[a*]', 'x' -InputObject 'a').ErrorText | Should -Match 'the \[c\*\] repeat construct may not appear in string1'
        (Invoke-TestGnu tr 'a', '[x*09]' -InputObject 'a').ErrorText | Should -Match "invalid repeat count '09'"
        (Invoke-TestGnu tr 'a', '[:digit:]' -InputObject 'a').ErrorText | Should -Match "the only character classes that may appear in string2 are 'upper' and 'lower'"
        (Invoke-TestGnu tr 'lo', '[:upper:]' -InputObject 'a').ErrorText | Should -Match 'misaligned \[:upper:\] and/or \[:lower:\] construct'
        (Invoke-TestGnu tr '-c', 'a', '[:upper:]' -InputObject 'a').ErrorText | Should -Match 'misaligned'
        $r = Invoke-TestGnu tr 'abc', '' -InputObject 'a'
        $r.ErrorText | Should -Match 'when not truncating set1, string2 must be non-empty'
        $r.ExitCode | Should -Be 1
    }
}
