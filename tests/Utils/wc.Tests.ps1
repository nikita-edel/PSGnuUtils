BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'wc' {
    BeforeAll {
        $script:dir = Join-Path $TestDrive 'wc'
        $null = New-TestFile -Path (Join-Path $dir 'f.txt') -Content "one two`nthree`n"
        $null = New-TestFile -Path (Join-Path $dir 'g.txt') -Content "four`n"
        $null = New-TestFile -Path (Join-Path $dir 'nonl.txt') -Content 'no newline'
        $null = New-TestFile -Path (Join-Path $dir 'list0') -Content "f.txt`0g.txt`0"
    }

    It 'prints lines, words and bytes padded to the width of the total size' {
        (Invoke-TestGnu wc 'f.txt' -WorkingDirectory $dir).Output | Should -Be @(' 2  3 14 f.txt')
    }

    It 'prints a total line for several files' {
        (Invoke-TestGnu wc 'f.txt', 'g.txt' -WorkingDirectory $dir).Output | Should -Be @(' 2  3 14 f.txt', ' 1  1  5 g.txt', ' 3  4 19 total')
    }

    It 'prints a single count without padding' {
        (Invoke-TestGnu wc '-l', 'f.txt' -WorkingDirectory $dir).Output | Should -Be @('2 f.txt')
        (Invoke-TestGnu wc '--lines' -InputObject 'a', 'b').Output | Should -Be @('2')
    }

    It 'counts newline characters, not lines' {
        (Invoke-TestGnu wc '-l', 'nonl.txt' -WorkingDirectory $dir).Output | Should -Be @('0 nonl.txt')
    }

    It 'uses width 7 and no name for pipeline input' {
        (Invoke-TestGnu wc -InputObject 'x', 'yy').Output | Should -Be @('      2       2       5')
    }

    It 'selects counts with -c, -m, -w and -L (and long forms)' {
        $text = [string][char]0xE9 + "`tb"
        (Invoke-TestGnu wc '-c' -InputObject $text).Output | Should -Be @('5')
        (Invoke-TestGnu wc '--bytes' -InputObject $text).Output | Should -Be @('5')
        (Invoke-TestGnu wc '-m' -InputObject $text).Output | Should -Be @('4')
        (Invoke-TestGnu wc '--chars' -InputObject $text).Output | Should -Be @('4')
        (Invoke-TestGnu wc '-w' -InputObject 'a b  c').Output | Should -Be @('3')
        (Invoke-TestGnu wc '--words' -InputObject 'a b  c').Output | Should -Be @('3')
        (Invoke-TestGnu wc '-L' -InputObject 'a', "a`tb", 'abc').Output | Should -Be @('9')
        (Invoke-TestGnu wc '--max-line-length' -InputObject 'abcd').Output | Should -Be @('4')
    }

    It 'prints counts in GNU order regardless of option order' {
        (Invoke-TestGnu wc '-cl', 'f.txt' -WorkingDirectory $dir).Output | Should -Be @(' 2 14 f.txt')
    }

    It 'controls the total line with --total' {
        (Invoke-TestGnu wc '-l', '--total=always', 'f.txt' -WorkingDirectory $dir).Output | Should -Be @('2 f.txt', '2 total')
        (Invoke-TestGnu wc '-l', '--total=only', 'f.txt', 'g.txt' -WorkingDirectory $dir).Output | Should -Be @('3')
        (Invoke-TestGnu wc '-l', '--total=never', 'f.txt', 'g.txt' -WorkingDirectory $dir).Output | Should -Be @(' 2 f.txt', ' 1 g.txt')
        (Invoke-TestGnu wc '--total=bogus' -InputObject 'x').ErrorText | Should -Match "invalid argument 'bogus' for '--total'"
    }

    It 'reads file names from --files0-from' {
        (Invoke-TestGnu wc '-l', '--files0-from=list0' -WorkingDirectory $dir).Output | Should -Be @(' 2 f.txt', ' 1 g.txt', ' 3 total')
        (Invoke-TestGnu wc '--files0-from=list0', 'f.txt' -WorkingDirectory $dir).ErrorText | Should -Match 'file operands cannot be combined with --files0-from'
    }

    It 'shows - as the name when it is given explicitly' {
        (Invoke-TestGnu wc '-l', '-' -InputObject 'a').Output | Should -Be @('1 -')
    }

    It 'reports missing files and continues' {
        $r = Invoke-TestGnu wc '-l', 'missing', 'g.txt' -WorkingDirectory $dir
        $r.ErrorText | Should -BeExactly 'wc: missing: No such file or directory'
        $r.Output | Should -Contain '1 g.txt'
        $r.ExitCode | Should -Be 1
    }
}
