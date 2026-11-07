BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'cat' {
    BeforeAll {
        $script:dir = Join-Path $TestDrive 'cat'
        $null = New-TestFile -Path (Join-Path $dir 'a.txt') -Content "one`ntwo`n"
        $null = New-TestFile -Path (Join-Path $dir 'b.txt') -Content "three`n"
        $null = New-TestFile -Path (Join-Path $dir 'blank.txt') -Content "x`n`n`n`ny`n"
        $null = New-TestFile -Path (Join-Path $dir 'special.txt') -Content ("a`tb`r`n" + [char]1 + [char]127 + [char]0xE9 + "`nlast")
    }

    It 'concatenates files' {
        (Invoke-TestGnu cat 'a.txt', 'b.txt' -WorkingDirectory $dir).Output | Should -Be @('one', 'two', 'three')
    }

    It 'reads pipeline input and - in order' {
        (Invoke-TestGnu cat -InputObject 'p1', 'p2').Output | Should -Be @('p1', 'p2')
        (Invoke-TestGnu cat 'a.txt', '-', 'b.txt' -InputObject 'mid' -WorkingDirectory $dir).Output | Should -Be @('one', 'two', 'mid', 'three')
    }

    It 'numbers all lines with -n / --number, continuing across files' {
        (Invoke-TestGnu cat '-n', 'a.txt', 'b.txt' -WorkingDirectory $dir).Output | Should -Be @("     1`tone", "     2`ttwo", "     3`tthree")
        (Invoke-TestGnu cat '--number' -InputObject 'x').Output | Should -Be @("     1`tx")
    }

    It 'numbers non-blank lines with -b / --number-nonblank' {
        (Invoke-TestGnu cat '-b', 'blank.txt' -WorkingDirectory $dir).Output | Should -Be @("     1`tx", '', '', '', "     2`ty")
        (Invoke-TestGnu cat '--number-nonblank', '-n' -InputObject 'a', '', 'b').Output | Should -Be @("     1`ta", '', "     2`tb")
    }

    It 'squeezes repeated blank lines with -s / --squeeze-blank' {
        (Invoke-TestGnu cat '-s', 'blank.txt' -WorkingDirectory $dir).Output | Should -Be @('x', '', 'y')
        (Invoke-TestGnu cat '--squeeze-blank', '-n', 'blank.txt' -WorkingDirectory $dir).Output | Should -Be @("     1`tx", "     2`t", "     3`ty")
    }

    It 'shows line ends with -E / --show-ends (not after an unterminated last line)' {
        (Invoke-TestGnu cat '-E', 'a.txt' -WorkingDirectory $dir).Output | Should -Be @('one$', 'two$')
        (Invoke-TestGnu cat '--show-ends', 'special.txt' -WorkingDirectory $dir).Output[-1] | Should -BeExactly 'last'
    }

    It 'shows tabs with -T / --show-tabs' {
        (Invoke-TestGnu cat '-T' -InputObject "a`tb").Output | Should -Be @('a^Ib')
        (Invoke-TestGnu cat '--show-tabs' -InputObject "a`tb").Output | Should -Be @('a^Ib')
    }

    It 'shows non-printing characters with -v / --show-nonprinting' {
        $r = Invoke-TestGnu cat '-v', 'special.txt' -WorkingDirectory $dir
        $r.Output | Should -Be @("a`tb^M", '^A^?M-CM-)', 'last')
        (Invoke-TestGnu cat '--show-nonprinting' -InputObject ([string][char]0x80)).Output | Should -Be @('M-BM-^@')
    }

    It 'combines -v, -E and -T with -A / --show-all' {
        $expected = @('a^Ib^M$', '^A^?M-CM-)$', 'last')
        (Invoke-TestGnu cat '-A', 'special.txt' -WorkingDirectory $dir).Output | Should -Be $expected
        (Invoke-TestGnu cat '--show-all', 'special.txt' -WorkingDirectory $dir).Output | Should -Be $expected
    }

    It 'combines -v and -E with -e' {
        (Invoke-TestGnu cat '-e', 'special.txt' -WorkingDirectory $dir).Output | Should -Be @("a`tb^M$", '^A^?M-CM-)$', 'last')
    }

    It 'combines -v and -T with -t' {
        (Invoke-TestGnu cat '-t', 'special.txt' -WorkingDirectory $dir).Output | Should -Be @('a^Ib^M', '^A^?M-CM-)', 'last')
    }

    It 'renders characters outside the BMP as their UTF-8 bytes' {
        $emoji = [char]::ConvertFromUtf32(0x1F600)
        (Invoke-TestGnu cat '-v' -InputObject $emoji).Output | Should -Be @('M-pM-^_M-^XM-^@')
    }

    It 'ignores -u' {
        (Invoke-TestGnu cat '-u', 'b.txt' -WorkingDirectory $dir).Output | Should -Be @('three')
    }

    It 'reports missing files and continues' {
        $r = Invoke-TestGnu cat 'missing.txt', 'b.txt' -WorkingDirectory $dir
        $r.Output | Should -Be @('three')
        $r.ErrorText | Should -BeExactly 'cat: missing.txt: No such file or directory'
        $r.ExitCode | Should -Be 1
    }

    It 'prints nothing for an empty file in -A mode' {
        $null = New-TestFile -Path (Join-Path $dir 'empty.txt') -Content ''
        $r = Invoke-TestGnu cat '-A', 'empty.txt', 'b.txt' -WorkingDirectory $dir
        $r.Output | Should -Be @('three$')
    }
}
