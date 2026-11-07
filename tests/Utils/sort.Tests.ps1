BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'sort' {
    It 'sorts ordinally (like LC_ALL=C)' {
        (Invoke-TestGnu sort -InputObject 'banana', 'Apple', 'cherry', 'apple', '10', '9').Output | Should -Be @('10', '9', 'Apple', 'apple', 'banana', 'cherry')
    }

    It 'reverses with -r / --reverse' {
        (Invoke-TestGnu sort '-r' -InputObject 'a', 'c', 'b').Output | Should -Be @('c', 'b', 'a')
        (Invoke-TestGnu sort '--reverse' -InputObject 'a', 'b').Output | Should -Be @('b', 'a')
    }

    It 'sorts numbers with -n / --numeric-sort' {
        (Invoke-TestGnu sort '-n' -InputObject '10', '9', '-1.5', 'x', '2.25', ' 3').Output | Should -Be @('-1.5', 'x', '2.25', ' 3', '9', '10')
        (Invoke-TestGnu sort '--numeric-sort' -InputObject '2', '1').Output | Should -Be @('1', '2')
    }

    It 'sorts general numbers with -g / --general-numeric-sort' {
        (Invoke-TestGnu sort '-g' -InputObject '1e3', '5', 'abc', '-inf', '2.5e-1').Output | Should -Be @('abc', '-inf', '2.5e-1', '5', '1e3')
        (Invoke-TestGnu sort '--general-numeric-sort' -InputObject 'inf', '1').Output | Should -Be @('1', 'inf')
    }

    It 'sorts human sizes with -h / --human-numeric-sort' {
        (Invoke-TestGnu sort '-h' -InputObject '2G', '1K', '500', '3M', '1.5K').Output | Should -Be @('500', '1K', '1.5K', '3M', '2G')
        (Invoke-TestGnu sort '--human-numeric-sort' -InputObject 'x', '1k').Output | Should -Be @('x', '1k')
    }

    It 'sorts versions with -V / --version-sort' {
        (Invoke-TestGnu sort '-V' -InputObject 'v1.10', 'v1.2', 'v1.9', 'v1.2a').Output | Should -Be @('v1.2', 'v1.2a', 'v1.9', 'v1.10')
        (Invoke-TestGnu sort '--version-sort' -InputObject 'file10', 'file2').Output | Should -Be @('file2', 'file10')
    }

    It 'sorts months with -M / --month-sort' {
        (Invoke-TestGnu sort '-M' -InputObject 'Mar', 'jan', 'December', 'foo').Output | Should -Be @('foo', 'jan', 'Mar', 'December')
        (Invoke-TestGnu sort '--month-sort' -InputObject 'FEB', 'JAN').Output | Should -Be @('JAN', 'FEB')
    }

    It 'chooses the order with --sort=WORD' {
        (Invoke-TestGnu sort '--sort=numeric' -InputObject '10', '9').Output | Should -Be @('9', '10')
        (Invoke-TestGnu sort '--sort=bogus' -InputObject 'a').ErrorText | Should -Match "invalid argument 'bogus' for '--sort'"
    }

    It 'folds case with -f / --ignore-case, ignores characters with -d and -i' {
        # equal keys fall back to the whole line: 'A' < 'a' and 'B' < 'b'
        (Invoke-TestGnu sort '-f' -InputObject 'b', 'A', 'a', 'B').Output | Should -Be @('A', 'a', 'B', 'b')
        (Invoke-TestGnu sort '--ignore-case', '-s' -InputObject 'b', 'A').Output | Should -Be @('A', 'b')
        (Invoke-TestGnu sort '-d' -InputObject '#b', 'a').Output | Should -Be @('a', '#b')
        (Invoke-TestGnu sort '--dictionary-order' -InputObject '_z', 'y').Output | Should -Be @('y', '_z')
        $control = [string][char]1 + 'z'
        (Invoke-TestGnu sort '-i' -InputObject $control, 'a').Output | Should -Be @('a', $control)
        (Invoke-TestGnu sort '--ignore-nonprinting' -InputObject $control, 'y').Output | Should -Be @('y', $control)
    }

    It 'ignores leading blanks with -b / --ignore-leading-blanks' {
        (Invoke-TestGnu sort -InputObject 'b', '  a').Output | Should -Be @('  a', 'b')
        (Invoke-TestGnu sort '-b' -InputObject '  c', 'b').Output | Should -Be @('b', '  c')
        (Invoke-TestGnu sort '--ignore-leading-blanks' -InputObject ' z', 'y').Output | Should -Be @('y', ' z')
    }

    It 'sorts by keys with -k / --key and -t / --field-separator' {
        $rows = 'b,2,x', 'a,10,y', 'c,1,z'
        (Invoke-TestGnu sort '-t', ',', '-k', '2n' -InputObject $rows).Output | Should -Be @('c,1,z', 'b,2,x', 'a,10,y')
        (Invoke-TestGnu sort '--field-separator=,', '--key=2,2' -InputObject $rows).Output | Should -Be @('c,1,z', 'a,10,y', 'b,2,x')
        (Invoke-TestGnu sort '-t', ',', '-k', '3r' -InputObject $rows).Output | Should -Be @('c,1,z', 'a,10,y', 'b,2,x')
        (Invoke-TestGnu sort '-k', '2' -InputObject 'x b', 'y a').Output | Should -Be @('y a', 'x b')
        (Invoke-TestGnu sort '-k', '1.2,1.2' -InputObject 'ab', 'ba').Output | Should -Be @('ba', 'ab')
        (Invoke-TestGnu sort '-t', ',', '-k', '1,1', '-k', '2,2n' -InputObject 'a,2', 'b,1', 'a,1').Output | Should -Be @('a,1', 'a,2', 'b,1')
        (Invoke-TestGnu sort '-k', '2b,2' -InputObject 'x    b', 'y a').Output | Should -Be @('y a', 'x    b')
        (Invoke-TestGnu sort '-k', '1,1.1b' -InputObject 'b', 'a').Output | Should -Be @('a', 'b')
        (Invoke-TestGnu sort '-t', ',', '-k', '5' -InputObject 'b', 'a').Output | Should -Be @('a', 'b')
        (Invoke-TestGnu sort '-k', '2,1' -InputObject 'b a', 'a b').Output | Should -Be @('a b', 'b a')
        (Invoke-TestGnu sort '-k', '1fdi' -InputObject 'B', 'a').Output | Should -Be @('a', 'B')
        (Invoke-TestGnu sort '-k', '1g' -InputObject '1e2', '3').Output | Should -Be @('3', '1e2')
        (Invoke-TestGnu sort '-k', '1h' -InputObject '1M', '2K').Output | Should -Be @('2K', '1M')
        (Invoke-TestGnu sort '-k', '1V' -InputObject 'a10', 'a9').Output | Should -Be @('a9', 'a10')
        (Invoke-TestGnu sort '-k', '1M' -InputObject 'feb', 'jan').Output | Should -Be @('jan', 'feb')
    }

    It 'rejects invalid keys and separators' -ForEach @(
        @{ Arguments = @('-k', 'x'); Message = "invalid field specification 'x'" }
        @{ Arguments = @('-k', '0'); Message = 'field number is zero' }
        @{ Arguments = @('-k', '1.0'); Message = 'character offset is zero' }
        @{ Arguments = @('-k', '1,0'); Message = 'field number is zero' }
        @{ Arguments = @('-k', '1R'); Message = 'random sort (-R) is not supported' }
        @{ Arguments = @('-t', 'ab'); Message = "multi-character tab 'ab'" }
    ) {
        $r = Invoke-TestGnu sort $Arguments -InputObject 'a'
        $r.ExitCode | Should -Be 2
        $r.ErrorText | Should -Match ([regex]::Escape($Message))
    }

    It 'accepts \0 as separator' {
        (Invoke-TestGnu sort '-t', '\0', '-k', '2' -InputObject ("a`0z"), ("b`0y")).Output | Should -Be @("b`0y", "a`0z")
    }

    It 'keeps the first of equal lines with -u / --unique and input order with -s / --stable' {
        (Invoke-TestGnu sort '-u' -InputObject 'b', 'a', 'b').Output | Should -Be @('a', 'b')
        (Invoke-TestGnu sort '--unique', '-f' -InputObject 'a', 'A', 'b').Output | Should -Be @('a', 'b')
        (Invoke-TestGnu sort '-s', '-k', '1,1' -InputObject 'a 2', 'a 1').Output | Should -Be @('a 2', 'a 1')
        (Invoke-TestGnu sort '--stable', '-r', '-k', '1,1' -InputObject 'a 2', 'b', 'a 1').Output | Should -Be @('b', 'a 2', 'a 1')
        (Invoke-TestGnu sort '-k', '1,1' -InputObject 'a 2', 'a 1').Output | Should -Be @('a 1', 'a 2')
        (Invoke-TestGnu sort '-r', '-k', '1,1' -InputObject 'a 1', 'a 2').Output | Should -Be @('a 2', 'a 1')
    }

    It 'checks order with -c, -C and --check=WHEN' {
        (Invoke-TestGnu sort '-c' -InputObject 'a', 'b').ExitCode | Should -Be 0
        $r = Invoke-TestGnu sort '-c' -InputObject 'b', 'a'
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -BeExactly 'sort: -:2: disorder: a'
        $q = Invoke-TestGnu sort '-C' -InputObject 'b', 'a'
        $q.ExitCode | Should -Be 1
        $q.Errors.Count | Should -Be 0
        (Invoke-TestGnu sort '--check' -InputObject 'b', 'a').ErrorText | Should -Match 'disorder'
        (Invoke-TestGnu sort '--check=quiet' -InputObject 'b', 'a').Errors.Count | Should -Be 0
        (Invoke-TestGnu sort '--check=silent' -InputObject 'b', 'a').ExitCode | Should -Be 1
        (Invoke-TestGnu sort '-cu' -InputObject 'a', 'a').ExitCode | Should -Be 1
        (Invoke-TestGnu sort '--check=loud' -InputObject 'a').ErrorText | Should -Match "invalid argument 'loud' for '--check'"
        (Invoke-TestGnu sort '-c', 'a', 'b').ErrorText | Should -Match "extra operand 'b' not allowed with -c"
    }

    It 'merges files with -m / --merge, writes to a file with -o / --output' {
        $a = New-TestFile -Path (Join-Path $TestDrive 's1.txt') -Content "a`nc`n"
        $b = New-TestFile -Path (Join-Path $TestDrive 's2.txt') -Content "b`nd`n"
        (Invoke-TestGnu sort '-m', $a, $b).Output | Should -Be @('a', 'b', 'c', 'd')
        (Invoke-TestGnu sort '--merge', $b, $a).Output | Should -Be @('a', 'b', 'c', 'd')
        $null = Invoke-TestGnu sort '-o', $a, '-r', $a
        [System.IO.File]::ReadAllText($a) | Should -BeExactly "c`na`n"
        $empty = Join-Path $TestDrive 'empty-out.txt'
        $null = Invoke-TestGnu sort '--output', $empty -InputObject @()
        [System.IO.File]::ReadAllText($empty) | Should -BeExactly ''
        (Invoke-TestGnu sort '-o', (Join-Path $TestDrive 'no/dir/out'), $b).ErrorText | Should -Match 'open failed'
    }

    It 'splits on NUL with -z / --zero-terminated' {
        $file = New-TestFile -Path (Join-Path $TestDrive 'z.txt') -Content "b`0a`0"
        (Invoke-TestGnu sort '-z', $file).Output | Should -Be @("a`0b`0")
        $out = Join-Path $TestDrive 'z-out.txt'
        $null = Invoke-TestGnu sort '--zero-terminated', '-o', $out, $file
        [System.IO.File]::ReadAllText($out) | Should -BeExactly "a`0b`0"
    }

    It 'reads file names from --files0-from' {
        $a = New-TestFile -Path (Join-Path $TestDrive 'f1.txt') -Content "y`n"
        $b = New-TestFile -Path (Join-Path $TestDrive 'f2.txt') -Content "x`n"
        $list = New-TestFile -Path (Join-Path $TestDrive 'list0') -Content "$a`0$b`0"
        (Invoke-TestGnu sort "--files0-from=$list").Output | Should -Be @('x', 'y')
        (Invoke-TestGnu sort "--files0-from=$list", $a).ErrorText | Should -Match 'file operands cannot be combined with --files0-from'
        (Invoke-TestGnu sort '--files0-from=missing-list').ExitCode | Should -Be 2
    }

    It 'stops when an input cannot be read' {
        $r = Invoke-TestGnu sort (Join-Path $TestDrive 'missing') -InputObject 'a'
        $r.Output.Count | Should -Be 0
        $r.ErrorText | Should -Match 'No such file or directory'
        $r.ExitCode | Should -Be 2
    }

    It 'compares versions and values directly' {
        InModuleScope PSGnuUtils {
            Compare-GnuVersion -Left '1.2' -Right '1.2.1' | Should -Be -1
            Compare-GnuVersion -Left 'a' -Right 'a' | Should -Be 0
            Compare-GnuSortValue -Left @(1, 2.0) -Right @(1, 1.0) -Mode 'human' | Should -Be 1
            ConvertTo-GnuSortValue -Text '-inf' -Key @{ Mode = 'general'; Blanks = $false } | Should -Be ([double]::NegativeInfinity)
        }
    }
}
