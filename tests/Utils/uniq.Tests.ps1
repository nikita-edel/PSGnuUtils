BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'uniq' {
    It 'merges adjacent duplicates only' {
        (Invoke-TestGnu uniq -InputObject 'a', 'a', 'b', 'a').Output | Should -Be @('a', 'b', 'a')
    }

    It 'counts with -c / --count' {
        (Invoke-TestGnu uniq '-c' -InputObject 'a', 'a', 'b').Output | Should -Be @('      2 a', '      1 b')
        (Invoke-TestGnu uniq '--count' -InputObject 'x').Output | Should -Be @('      1 x')
    }

    It 'prints duplicates with -d / --repeated and unique lines with -u / --unique' {
        (Invoke-TestGnu uniq '-d' -InputObject 'a', 'a', 'b', 'c', 'c').Output | Should -Be @('a', 'c')
        (Invoke-TestGnu uniq '--repeated' -InputObject 'a', 'b').Output.Count | Should -Be 0
        (Invoke-TestGnu uniq '-u' -InputObject 'a', 'a', 'b', 'c', 'c').Output | Should -Be @('b')
        (Invoke-TestGnu uniq '--unique' -InputObject 'a', 'b').Output | Should -Be @('a', 'b')
        (Invoke-TestGnu uniq '-d', '-u' -InputObject 'a', 'a', 'b').Output.Count | Should -Be 0
    }

    It 'prints every duplicate with -D and --all-repeated=METHOD' {
        $lines = 'a', 'a', 'b', 'c', 'c'
        (Invoke-TestGnu uniq '-D' -InputObject $lines).Output | Should -Be @('a', 'a', 'c', 'c')
        (Invoke-TestGnu uniq '--all-repeated' -InputObject $lines).Output | Should -Be @('a', 'a', 'c', 'c')
        (Invoke-TestGnu uniq '--all-repeated=separate' -InputObject $lines).Output | Should -Be @('a', 'a', '', 'c', 'c')
        (Invoke-TestGnu uniq '--all-repeated=prepend' -InputObject $lines).Output | Should -Be @('', 'a', 'a', '', 'c', 'c')
    }

    It 'shows all groups with --group=METHOD' {
        $lines = 'a', 'a', 'b'
        (Invoke-TestGnu uniq '--group' -InputObject $lines).Output | Should -Be @('a', 'a', '', 'b')
        (Invoke-TestGnu uniq '--group=prepend' -InputObject $lines).Output | Should -Be @('', 'a', 'a', '', 'b')
        (Invoke-TestGnu uniq '--group=append' -InputObject $lines).Output | Should -Be @('a', 'a', '', 'b', '')
        (Invoke-TestGnu uniq '--group=both' -InputObject $lines).Output | Should -Be @('', 'a', 'a', '', 'b', '')
    }

    It 'controls the comparison with -i, -f, -s and -w (and long forms)' {
        (Invoke-TestGnu uniq '-i' -InputObject 'A', 'a').Output | Should -Be @('A')
        (Invoke-TestGnu uniq '--ignore-case' -InputObject 'b', 'B', 'c').Output | Should -Be @('b', 'c')
        (Invoke-TestGnu uniq '-f', '1' -InputObject 'x a', 'y a', 'z b').Output | Should -Be @('x a', 'z b')
        # the blanks before a field belong to it: ' a' and '  a' differ
        (Invoke-TestGnu uniq '-f', '1' -InputObject 'x a', 'y  a').Output | Should -Be @('x a', 'y  a')
        (Invoke-TestGnu uniq '--skip-fields=2' -InputObject 'a b c', 'd e c').Output | Should -Be @('a b c')
        (Invoke-TestGnu uniq '-s', '1' -InputObject 'xa', 'ya').Output | Should -Be @('xa')
        (Invoke-TestGnu uniq '--skip-chars=9' -InputObject 'ab', 'cd').Output | Should -Be @('ab')
        (Invoke-TestGnu uniq '-w', '1' -InputObject 'ab', 'ac', 'b').Output | Should -Be @('ab', 'b')
        (Invoke-TestGnu uniq '--check-chars=0' -InputObject 'x', 'y').Output | Should -Be @('x')
    }

    It 'splits on NUL with -z / --zero-terminated' {
        $file = New-TestFile -Path (Join-Path $TestDrive 'z.txt') -Content "a`0a`0b`0"
        (Invoke-TestGnu uniq '-z', $file).Output | Should -Be @("a`0b`0")
        (Invoke-TestGnu uniq '--zero-terminated', '-c', $file).Output | Should -Be @("      2 a`0      1 b`0")
    }

    It 'reads INPUT and writes OUTPUT files' {
        $in = New-TestFile -Path (Join-Path $TestDrive 'in.txt') -Content "q`nq`nr`n"
        $out = Join-Path $TestDrive 'out.txt'
        $r = Invoke-TestGnu uniq $in, $out
        $r.Output.Count | Should -Be 0
        [System.IO.File]::ReadAllText($out) | Should -BeExactly "q`nr`n"
        (Invoke-TestGnu uniq '-', $out -InputObject 'only').ExitCode | Should -Be 0
        [System.IO.File]::ReadAllText($out) | Should -BeExactly "only`n"
        (Invoke-TestGnu uniq $in, (Join-Path $TestDrive 'no/dir/out.txt')).ErrorText | Should -Match 'No such file or directory'
    }

    It 'rejects invalid combinations and arguments' {
        (Invoke-TestGnu uniq '--group', '-c' -InputObject 'a').ErrorText | Should -Match '--group is mutually exclusive with -c/-d/-D/-u'
        (Invoke-TestGnu uniq '-c', '-D' -InputObject 'a').ErrorText | Should -Match 'printing all duplicated lines and repeat counts is meaningless'
        (Invoke-TestGnu uniq '-f', 'x' -InputObject 'a').ErrorText | Should -Match 'x: invalid number of fields to skip'
        (Invoke-TestGnu uniq '-s', 'x' -InputObject 'a').ErrorText | Should -Match 'x: invalid number of bytes to skip'
        (Invoke-TestGnu uniq '-w', 'x' -InputObject 'a').ErrorText | Should -Match 'x: invalid number of bytes to compare'
        (Invoke-TestGnu uniq '--group=bad' -InputObject 'a').ErrorText | Should -Match "invalid argument 'bad' for '--group'"
        (Invoke-TestGnu uniq '--all-repeated=bad' -InputObject 'a').ErrorText | Should -Match "invalid argument 'bad' for '--all-repeated'"
        $r = Invoke-TestGnu uniq 'a', 'b', 'c'
        $r.ErrorText | Should -Match "extra operand 'c'"
        $r.ExitCode | Should -Be 1
        (Invoke-TestGnu uniq (Join-Path $TestDrive 'missing')).ErrorText | Should -Match 'No such file or directory'
    }

    It 'writes NUL-terminated records to OUTPUT with -z' {
        $in = New-TestFile -Path (Join-Path $TestDrive 'zin.txt') -Content "a`0a`0b`0"
        $out = Join-Path $TestDrive 'zout.txt'
        $null = Invoke-TestGnu uniq '-z', $in, $out
        [System.IO.File]::ReadAllText($out) | Should -BeExactly "a`0b`0"
    }
}
