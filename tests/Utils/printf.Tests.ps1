BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# Expected outputs come from GNU coreutils printf.
Describe 'printf' {
    It 'formats strings and reuses the format for remaining arguments' {
        (Invoke-TestGnu printf '%s-%s\n', 'a', 'b', 'c').Output | Should -Be @('a-b', 'c-')
        (Invoke-TestGnu printf '%5s|%-5s|%.2s\n', 'ab', 'ab', 'abc').Output | Should -Be @('   ab|ab   |ab')
        (Invoke-TestGnu printf 'plain').Output | Should -Be @('plain')
        (Invoke-TestGnu printf '--', '%s\n', 'dash').Output | Should -Be @('dash')
    }

    It 'formats integers' {
        (Invoke-TestGnu printf '%d %i %o %u %x %X\n', '42', '-7', '8', '9', '255', '255').Output | Should -Be @('42 -7 10 9 ff FF')
        (Invoke-TestGnu printf '%#x %#o %+d % d %05d %-5d| %.3d\n', '255', '8', '5', '5', '42', '42', '7').Output | Should -Be @('0xff 010 +5  5 00042 42   | 007')
        (Invoke-TestGnu printf '%.0d|%#.0o|%x|%#X|%5.3d|%-+4d|\n', '0', '0', '0', '0', '7', '3').Output | Should -Be @('|0|0|0|  007|+3  |')
        (Invoke-TestGnu printf '%u %x %o\n', '-1', '-1', '-1').Output | Should -Be @('18446744073709551615 ffffffffffffffff 1777777777777777777777')
        (Invoke-TestGnu printf '%ld %hhd\n', '5', '6').Output | Should -Be @('5 6')
        (Invoke-TestGnu printf '%.d|%#X\n', '5', '255').Output | Should -Be @('5|0XFF')
    }

    It 'parses numbers like strtoimax' {
        (Invoke-TestGnu printf '%d,', "'A", '"B', '0x1F', '010', ' 42', '+7', '-0x10').Output | Should -Be @('65,66,31,8,42,7,-16,')
    }

    It 'reports invalid numbers and prints 0 or the converted prefix' {
        $r = Invoke-TestGnu printf '%d\n', '12abc', 'abc', '99999999999999999999'
        $r.Output | Should -Be @('12', '0', '9223372036854775807')
        $r.Errors | Should -Be @("printf: '12abc': value not completely converted", "printf: 'abc': expected a numeric value", "printf: '99999999999999999999': Numerical result out of range")
        $r.ExitCode | Should -Be 1
        (Invoke-TestGnu printf '%u\n', '-99999999999999999999').Output | Should -Be @('18446744073709551615')
        (Invoke-TestGnu printf '%d\n', '-99999999999999999999').Output | Should -Be @('-9223372036854775808')
    }

    It 'formats floating point numbers' {
        (Invoke-TestGnu printf '%5.2f %e %g %G %F %E\n', '3.14159', '1234.5', '0.0001', '1e-10', '2.5', '0.5').Output | Should -Be @(' 3.14 1.234500e+03 0.0001 1E-10 2.500000 5.000000E-01')
        (Invoke-TestGnu printf '%.3e|%10.4g|%-8.2e|%''.2f\n', '12345.678', '0.000123456', '5', '1.5').Output | Should -Be @('1.235e+04| 0.0001235|5.00e+00|1.50')
        (Invoke-TestGnu printf '%f %f %f %.1f\n', 'inf', '-Infinity', 'nan', "'A").Output | Should -Be @('inf -inf nan 65.0')
        $r = Invoke-TestGnu printf '%i %f %f\n', '1.5', 'abc', '2x'
        $r.Output | Should -Be @('1 0.000000 2.000000')
        $r.Errors | Should -Contain "printf: 'abc': expected a numeric value"
        $r.Errors | Should -Contain "printf: '2x': value not completely converted"
    }

    It 'takes widths and precisions from arguments with *' {
        (Invoke-TestGnu printf '%*d|%-*d|%.*s|%*s|\n', '5', '1', '4', '2', '2', 'abcdef', '-3', 'x').Output | Should -Be @('    1|2   |ab|x  |')
        (Invoke-TestGnu printf '%*d|%.*d|\n').Output | Should -Be @('0||')
    }

    It 'prints characters with %c' {
        (Invoke-TestGnu printf '%c%c|%5c|\n', 'hello', 'x', 'y').Output | Should -Be @('hx|    y|')
        (Invoke-TestGnu printf '[%c]').Output | Should -Be @("[$([char]0)]")
    }

    It 'interprets escapes in FORMAT' {
        (Invoke-TestGnu printf 'A\101\x42\u00e9\U0001F600\"\\\q\n').Output | Should -Be @("AAB$([char]0xE9)$([char]::ConvertFromUtf32(0x1F600))`"\\q")
        (Invoke-TestGnu printf '\a\b\e\f\t\v\r|\n').Output | Should -Be @("$([char]7)$([char]8)$([char]27)$([char]12)`t$([char]11)`r|")
        (Invoke-TestGnu printf 'a\cb\n').Output | Should -Be @('a')
        (Invoke-TestGnu printf 'end\').Output | Should -Be @('end\')
        $r = Invoke-TestGnu printf 'a\xZ'
        $r.ErrorText | Should -Match 'missing hexadecimal number in escape'
        $r.ExitCode | Should -Be 1
        (Invoke-TestGnu printf '\u12').ErrorText | Should -Match 'missing hexadecimal number in escape'
    }

    It 'interprets escapes in %b arguments (\0NNN octal, \c stops)' {
        (Invoke-TestGnu printf '%b|%b\n', 'a\tb\0101\101', 'x\').Output | Should -Be @("a`tbAA|x\")
        (Invoke-TestGnu printf '%b\n', 'one\ctwo', 'three').Output | Should -Be @('one')
        (Invoke-TestGnu printf '%5b|\n', 'ab').Output | Should -Be @('   ab|')
        (Invoke-TestGnu printf '%b|\n').Output | Should -Be @('|')
    }

    It 'quotes for the shell with %q' {
        (Invoke-TestGnu printf '%q\n', 'abc', 'a b', "it's", 'x$y', 'a,b', '~x', '', '$x', "it's `$x").Output |
            Should -Be @('abc', "'a b'", "`"it's`"", "'x`$y'", 'a,b', "'~x'", "''", "'`$x'", "'it'\''s `$x'")
        (Invoke-TestGnu printf '%q\n', "a`tb", "x$([char]1)").Output | Should -Be @("'a'`$'\t''b'", "'x'`$'\001'")
    }

    It 'warns about excess arguments when FORMAT uses none' {
        $r = Invoke-TestGnu printf 'x\n', 'a', 'b'
        $r.Output | Should -Be @('x')
        $r.WarningText | Should -Match "ignoring excess arguments, starting with 'a'"
        $r.ExitCode | Should -Be 0
    }

    It 'rejects invalid conversions' {
        $r = Invoke-TestGnu printf 'a%z'
        $r.Output | Should -Be @('a')
        $r.ErrorText | Should -Match '%z: invalid conversion specification'
        $r.ExitCode | Should -Be 1
        (Invoke-TestGnu printf 'a%').ErrorText | Should -Match '%: invalid conversion specification'
        (Invoke-TestGnu printf '%%|%s\n', 'z').Output | Should -Be @('%|z')
    }

    It 'needs a FORMAT' {
        $r = Invoke-TestGnu printf
        $r.ErrorText | Should -Match 'missing operand'
        $r.ExitCode | Should -Be 1
    }
}
