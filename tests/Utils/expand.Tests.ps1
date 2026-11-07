BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'expand' {
    It 'expands tabs to every 8 columns by default' {
        (Invoke-TestGnu expand -InputObject "a`tb", "`tc", 'none').Output | Should -Be @('a       b', '        c', 'none')
    }

    It 'uses a tab size with -t / --tabs and -NUM' {
        (Invoke-TestGnu expand '-t', '4' -InputObject "a`tb").Output | Should -Be @('a   b')
        (Invoke-TestGnu expand '--tabs=2' -InputObject "a`tb").Output | Should -Be @('a b')
        (Invoke-TestGnu expand '-3' -InputObject "`tx").Output | Should -Be @('   x')
    }

    It 'uses explicit tab positions and single spaces after the last one' {
        (Invoke-TestGnu expand '-t', '2,5' -InputObject "`ta`tb`tc").Output | Should -Be @('  a  b c')
        (Invoke-TestGnu expand '-t', '2', '-t', '5' -InputObject "`ta`tb").Output | Should -Be @('  a  b')
        (Invoke-TestGnu expand '-t', '2 5' -InputObject "`ta`tb").Output | Should -Be @('  a  b')
    }

    It 'repeats after the last stop with /N and +N' {
        (Invoke-TestGnu expand '-t', '2,/4' -InputObject "`ta`tb`tc").Output | Should -Be @('  a b   c')
        (Invoke-TestGnu expand '-t', '2,+4' -InputObject "`ta`tb`tc").Output | Should -Be @('  a   b   c')
        (Invoke-TestGnu expand '-t', '/3' -InputObject "`tx").Output | Should -Be @('   x')
    }

    It 'only converts leading tabs with -i / --initial' {
        (Invoke-TestGnu expand '-i' -InputObject "`ta`tb").Output | Should -Be @("        a`tb")
        (Invoke-TestGnu expand '--initial', '-t', '2' -InputObject " `tx`ty").Output | Should -Be @("  x`ty")
    }

    It 'handles backspace' {
        (Invoke-TestGnu expand '-t', '4' -InputObject "ab`b`tc").Output | Should -Be @("ab`b   c")
    }

    It 'reads files' {
        $file = New-TestFile -Path (Join-Path $TestDrive 'tabs.txt') -Content "x`ty`n"
        (Invoke-TestGnu expand '-t', '2', $file).Output | Should -Be @('x y')
    }

    It 'rejects invalid tab lists' {
        (Invoke-TestGnu expand '-t', '0' -InputObject 'a').ErrorText | Should -Match 'tab size cannot be 0'
        (Invoke-TestGnu expand '-t', 'x' -InputObject 'a').ErrorText | Should -Match "tab size contains invalid character\(s\): 'x'"
        (Invoke-TestGnu expand '-t', '4,2' -InputObject 'a').ErrorText | Should -Match 'tab sizes must be ascending'
        $r = Invoke-TestGnu expand '-t', '/2,4' -InputObject 'a'
        $r.ErrorText | Should -Match "'/' specifier only allowed with the last value"
        $r.ExitCode | Should -Be 1
    }
}
