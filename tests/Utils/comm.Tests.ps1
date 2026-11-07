BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'comm' {
    BeforeAll {
        $script:dir = Join-Path $TestDrive 'comm'
        $null = New-TestFile -Path (Join-Path $dir 'one.txt') -Content "a`nb`nd`n"
        $null = New-TestFile -Path (Join-Path $dir 'two.txt') -Content "b`nc`nd`n"
        $null = New-TestFile -Path (Join-Path $dir 'unsorted.txt') -Content "b`na`n"
    }

    It 'prints three columns' {
        (Invoke-TestGnu comm 'one.txt', 'two.txt' -WorkingDirectory $dir).Output | Should -Be @('a', "`t`tb", "`tc", "`t`td")
    }

    It 'suppresses columns with -1, -2 and -3' {
        (Invoke-TestGnu comm '-1', 'one.txt', 'two.txt' -WorkingDirectory $dir).Output | Should -Be @("`tb", 'c', "`td")
        (Invoke-TestGnu comm '-2', 'one.txt', 'two.txt' -WorkingDirectory $dir).Output | Should -Be @('a', "`tb", "`td")
        (Invoke-TestGnu comm '-3', 'one.txt', 'two.txt' -WorkingDirectory $dir).Output | Should -Be @('a', "`tc")
        (Invoke-TestGnu comm '-12', 'one.txt', 'two.txt' -WorkingDirectory $dir).Output | Should -Be @('b', 'd')
    }

    It 'uses --output-delimiter' {
        (Invoke-TestGnu comm '--output-delimiter=|', 'one.txt', 'two.txt' -WorkingDirectory $dir).Output | Should -Be @('a', '||b', '|c', '||d')
    }

    It 'adds a summary with --total' {
        (Invoke-TestGnu comm '--total', 'one.txt', 'two.txt' -WorkingDirectory $dir).Output[-1] | Should -Be "1`t1`t2`ttotal"
        (Invoke-TestGnu comm '--total', '-12', 'one.txt', 'two.txt' -WorkingDirectory $dir).Output[-1] | Should -Be "1`t1`t2`ttotal"
    }

    It 'reads standard input for -' {
        (Invoke-TestGnu comm '-23', '-', 'two.txt' -InputObject 'a', 'b' -WorkingDirectory $dir).Output | Should -Be @('a')
    }

    It 'reports unsorted input, but not with --nocheck-order' {
        $r = Invoke-TestGnu comm 'unsorted.txt', 'two.txt' -WorkingDirectory $dir
        $r.ErrorText | Should -Match 'file 1 is not in sorted order'
        $r.ErrorText | Should -Match 'input is not in sorted order'
        $r.ExitCode | Should -Be 1
        $r = Invoke-TestGnu comm '--nocheck-order', 'unsorted.txt', 'two.txt' -WorkingDirectory $dir
        $r.Errors.Count | Should -Be 0
        $r.ExitCode | Should -Be 0
    }

    It 'stops at the first unsorted line with --check-order' {
        $r = Invoke-TestGnu comm '--check-order', 'two.txt', 'unsorted.txt' -WorkingDirectory $dir
        $r.ErrorText | Should -Match 'file 2 is not in sorted order'
        $r.ExitCode | Should -Be 1
    }

    It 'splits on NUL with -z / --zero-terminated' {
        $null = New-TestFile -Path (Join-Path $dir 'z1') -Content "a`0b`0"
        $null = New-TestFile -Path (Join-Path $dir 'z2') -Content "b`0"
        (Invoke-TestGnu comm '-z', 'z1', 'z2' -WorkingDirectory $dir).Output | Should -Be @("a`0`t`tb`0")
        (Invoke-TestGnu comm '--zero-terminated', '-3', 'z1', 'z2' -WorkingDirectory $dir).Output | Should -Be @("a`0")
    }

    It 'checks its operands' {
        (Invoke-TestGnu comm).ErrorText | Should -Match 'missing operand'
        (Invoke-TestGnu comm 'one.txt' -WorkingDirectory $dir).ErrorText | Should -Match "missing operand after 'one.txt'"
        (Invoke-TestGnu comm 'a', 'b', 'c').ErrorText | Should -Match "extra operand 'c'"
        $r = Invoke-TestGnu comm 'missing.txt', 'two.txt' -WorkingDirectory $dir
        $r.ErrorText | Should -Match 'missing.txt: No such file or directory'
        $r.Output.Count | Should -Be 0
    }

    It 'uses NUL for an empty --output-delimiter' {
        (Invoke-TestGnu comm '--output-delimiter=', 'one.txt', 'two.txt' -WorkingDirectory $dir).Output[1] | Should -BeExactly ("`0`0" + 'b')
    }

    It 'prints the rest of a longer first file' {
        $null = New-TestFile -Path (Join-Path $dir 'long.txt') -Content "b`nx`ny`n"
        (Invoke-TestGnu comm 'long.txt', 'two.txt' -WorkingDirectory $dir).Output | Should -Be @("`t`tb", "`tc", "`td", 'x', 'y')
    }
}
