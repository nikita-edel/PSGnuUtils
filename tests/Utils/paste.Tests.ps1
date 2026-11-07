BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'paste' {
    BeforeAll {
        $script:dir = Join-Path $TestDrive 'paste'
        $null = New-TestFile -Path (Join-Path $dir 'nums.txt') -Content "1`n2`n"
        $null = New-TestFile -Path (Join-Path $dir 'letters.txt') -Content "x`ny`nz`n"
        $null = New-TestFile -Path (Join-Path $dir 'empty.txt') -Content ''
    }

    It 'merges corresponding lines with TABs' {
        (Invoke-TestGnu paste 'nums.txt', 'letters.txt' -WorkingDirectory $dir).Output | Should -Be @("1`tx", "2`ty", "`tz")
    }

    It 'uses delimiters from -d / --delimiters in turn' {
        (Invoke-TestGnu paste '-d', ',' , 'nums.txt', 'letters.txt' -WorkingDirectory $dir).Output | Should -Be @('1,x', '2,y', ',z')
        (Invoke-TestGnu paste '--delimiters=,;', 'nums.txt', 'letters.txt', 'nums.txt' -WorkingDirectory $dir).Output | Should -Be @('1,x;1', '2,y;2', ',z;')
        (Invoke-TestGnu paste '-d', '\0', 'nums.txt', 'letters.txt' -WorkingDirectory $dir).Output | Should -Be @('1x', '2y', 'z')
        (Invoke-TestGnu paste '-d', '\t\\', 'nums.txt', 'nums.txt', 'nums.txt' -WorkingDirectory $dir).Output | Should -Be @("1`t1\1", "2`t2\2")
        (Invoke-TestGnu paste '-d', '\n', 'nums.txt', 'letters.txt' -WorkingDirectory $dir).Output | Should -Be @('1', 'x', '2', 'y', '', 'z')
        (Invoke-TestGnu paste '-d', '', 'nums.txt', 'nums.txt' -WorkingDirectory $dir).Output | Should -Be @('11', '22')
    }

    It 'joins the lines of each file with -s / --serial' {
        (Invoke-TestGnu paste '-s', 'nums.txt', 'letters.txt' -WorkingDirectory $dir).Output | Should -Be @("1`t2", "x`ty`tz")
        (Invoke-TestGnu paste '--serial', '-d', ',', 'letters.txt' -WorkingDirectory $dir).Output | Should -Be @('x,y,z')
        (Invoke-TestGnu paste '-s', 'empty.txt', 'nums.txt' -WorkingDirectory $dir).Output | Should -Be @('', "1`t2")
    }

    It 'reads successive pipeline lines for each -' {
        (Invoke-TestGnu paste '-', '-', '-' -InputObject (1..6)).Output | Should -Be @("1`t2`t3", "4`t5`t6")
        (Invoke-TestGnu paste -InputObject 'a', 'b').Output | Should -Be @('a', 'b')
        (Invoke-TestGnu paste '-s', '-', '-' -InputObject 'a', 'b').Output | Should -Be @("a`tb", '')
    }

    It 'splits on NUL with -z / --zero-terminated' {
        $null = New-TestFile -Path (Join-Path $dir 'z1') -Content "a`0b`0"
        $null = New-TestFile -Path (Join-Path $dir 'z2') -Content "c`0d`0"
        (Invoke-TestGnu paste '-z', 'z1', 'z2' -WorkingDirectory $dir).Output | Should -Be @("a`tc`0b`td`0")
        (Invoke-TestGnu paste '--zero-terminated', '-s', 'z1' -WorkingDirectory $dir).Output | Should -Be @("a`tb`0")
    }

    It 'stops without output when a file cannot be opened' {
        $r = Invoke-TestGnu paste 'nums.txt', 'missing.txt' -WorkingDirectory $dir
        $r.ErrorText | Should -Match 'missing.txt: No such file or directory'
        $r.Output.Count | Should -Be 0
        (Invoke-TestGnu paste '-z', 'missing.txt' -WorkingDirectory $dir).ExitCode | Should -Be 1
        $r.ExitCode | Should -Be 1
    }
}
