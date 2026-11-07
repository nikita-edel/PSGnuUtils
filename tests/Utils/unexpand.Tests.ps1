BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# Expected outputs come from GNU coreutils unexpand.
Describe 'unexpand' {
    It 'converts leading blanks by default' {
        (Invoke-TestGnu unexpand -InputObject '        x', "    `ty  z       w", 'none', "       `tx").Output |
            Should -Be @("`tx", "`ty  z       w", 'none', "`tx")
    }

    It 'converts all blanks with -a / --all' {
        (Invoke-TestGnu unexpand '-a' -InputObject "ab      cd`t  e").Output | Should -Be @("ab`tcd`t  e")
        (Invoke-TestGnu unexpand '--all' -InputObject 'a  b        c').Output | Should -Be @("a  b`t    c")
    }

    It 'keeps a single blank before a tab stop' {
        (Invoke-TestGnu unexpand '-a' -InputObject 'abcdefg h').Output | Should -Be @('abcdefg h')
    }

    It 'turns a blank before a tab stop into a tab when more blanks follow' {
        (Invoke-TestGnu unexpand '-a' -InputObject 'abcdefg  x').Output | Should -Be @("abcdefg`t x")
        (Invoke-TestGnu unexpand '-a' -InputObject 'abcdefg         x').Output | Should -Be @("abcdefg`t`tx")
        (Invoke-TestGnu unexpand '-t', '1' -InputObject ' x').Output | Should -Be @("`tx")
    }

    It 'uses tab sizes and lists with -t / --tabs and -NUM (implies -a)' {
        (Invoke-TestGnu unexpand '-t', '4' -InputObject '                q').Output | Should -Be @("`t`t`t`tq")
        (Invoke-TestGnu unexpand '--tabs=2,5' -InputObject '   x   y').Output | Should -Be @("`t x   y")
        (Invoke-TestGnu unexpand '-t', '2,5' -InputObject '          a').Output | Should -Be @("`t`t     a")
        (Invoke-TestGnu unexpand '-3' -InputObject "  `t  `tx").Output | Should -Be @("`t`tx")
    }

    It 'repeats after the last stop with +N and /N' {
        (Invoke-TestGnu unexpand '-t', '2,+4' -InputObject '      a     b').Output | Should -Be @("`t`ta`t  b")
        (Invoke-TestGnu unexpand '-t', '3,/5' -InputObject '      a     b').Output | Should -Be @("`t`t a`t  b")
    }

    It 'only converts leading blanks with --first-only (overrides -a)' {
        (Invoke-TestGnu unexpand '--first-only', '-a' -InputObject 'ab      cd       e', '        x  y       z').Output |
            Should -Be @('ab      cd       e', "`tx  y       z")
    }

    It 'handles backspace' {
        (Invoke-TestGnu unexpand '-a' -InputObject "ab`b      c").Output | Should -Be @("ab`b      c")
    }

    It 'reads files' {
        $file = New-TestFile -Path (Join-Path $TestDrive 'spaces.txt') -Content "        x`n"
        (Invoke-TestGnu unexpand $file).Output | Should -Be @("`tx")
    }

    It 'rejects invalid tab lists' {
        $r = Invoke-TestGnu unexpand '-t', '0' -InputObject 'a'
        $r.ErrorText | Should -Match 'tab size cannot be 0'
        $r.ExitCode | Should -Be 1
    }

    It 'reads the console without pipeline input' {
        (Use-TestConsoleInput -Text "    x`n" -Script { Invoke-TestGnu unexpand '-t', '2' }).Output | Should -Be @("`t`tx")
    }
}
