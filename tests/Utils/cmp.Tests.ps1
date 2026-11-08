BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# Expected outputs come from GNU diffutils cmp 3.12.
Describe 'cmp' {
    BeforeAll {
        $script:dir = Join-Path $TestDrive 'cmp'
        $null = New-Item -ItemType Directory -Path $dir -Force
        $null = New-TestFile -Path (Join-Path $dir 'a') -Content "line one`nline two`nline three`n"
        $null = New-TestFile -Path (Join-Path $dir 'b') -Content "line one`nline TWO`nline three`nextra`n"
        $null = New-TestFile -Path (Join-Path $dir 'c') -Content "line one`n"
        $null = New-TestFile -Path (Join-Path $dir 'x') -Bytes ([byte[]](97, 98, 99, 1, 255, 10))
        $null = New-TestFile -Path (Join-Path $dir 'y') -Bytes ([byte[]](97, 98, 99, 2, 254, 10))
        $null = New-TestFile -Path (Join-Path $dir 'e') -Content ''
        $null = New-TestFile -Path (Join-Path $dir 's') -Content 'xxabc'
        $null = New-TestFile -Path (Join-Path $dir 'big1') -Content ((1..200 | ForEach-Object { "$_`n" }) -join '')
        $null = New-TestFile -Path (Join-Path $dir 'big2') -Content ((1..200 | ForEach-Object { if ($_ -eq 150) { "15X`n" } else { "$_`n" } }) -join '')
    }

    It 'reports the first difference (exit code 1) and nothing for identical files (0)' {
        $r = Invoke-TestGnu cmp 'a', 'b' -WorkingDirectory $dir
        $r.Output | Should -Be @('a b differ: char 15, line 2')
        $r.ExitCode | Should -Be 1
        $r = Invoke-TestGnu cmp 'a', 'a' -WorkingDirectory $dir
        $r.Output | Should -BeNullOrEmpty
        $r.ExitCode | Should -Be 0
    }

    It 'prints differing bytes with -b / --print-bytes' {
        (Invoke-TestGnu cmp '-b', 'a', 'b' -WorkingDirectory $dir).Output | Should -Be @('a b differ: byte 15, line 2 is 164 t 124 T')
        (Invoke-TestGnu cmp '--print-bytes', 'x', 'y' -WorkingDirectory $dir).Output | Should -Be @('x y differ: byte 4, line 1 is   1 ^A   2 ^B')
    }

    It 'lists every difference with -l / --verbose' {
        $r = Invoke-TestGnu cmp '-l', 'a', 'b' -WorkingDirectory $dir
        $r.Output | Should -Be @('15 164 124', '16 167 127', '17 157 117')
        $r.ErrorText | Should -Be "cmp: EOF on 'a' after byte 29"
        (Invoke-TestGnu cmp '-l', '-b', 'x', 'y' -WorkingDirectory $dir).Output | Should -Be @('4   1 ^A     2 ^B', '5 377 M-^? 376 M-~')
        (Invoke-TestGnu cmp '--verbose', 'big1', 'big2' -WorkingDirectory $dir).Output | Should -Be @('491  60 130')
        $r = Invoke-TestGnu cmp '-l', 'x', 'y' -WorkingDirectory $dir
        $r.Output | Should -Be @('4   1   2', '5 377 376')
        $r.ExitCode | Should -Be 1
    }

    It 'is silent with -s / --quiet / --silent' {
        foreach ($quiet in '-s', '--quiet', '--silent') {
            $r = Invoke-TestGnu cmp $quiet, 'a', 'b' -WorkingDirectory $dir
            $r.Output | Should -BeNullOrEmpty
            $r.ExitCode | Should -Be 1
        }
        $r = Invoke-TestGnu cmp '-s', 'a', 'c' -WorkingDirectory $dir
        $r.Errors | Should -BeNullOrEmpty
        $r.ExitCode | Should -Be 1
    }

    It 'reports a shorter input' {
        (Invoke-TestGnu cmp 'a', 'c' -WorkingDirectory $dir).ErrorText | Should -Be "cmp: EOF on 'c' after byte 9, line 1"
        (Invoke-TestGnu cmp 'c', 'a' -WorkingDirectory $dir).ErrorText | Should -Be "cmp: EOF on 'c' after byte 9, line 1"
        (Invoke-TestGnu cmp 'a', 'e' -WorkingDirectory $dir).ErrorText | Should -Be "cmp: EOF on 'e' which is empty"
        (Invoke-TestGnu cmp 'e', 'a' -WorkingDirectory $dir).ErrorText | Should -Be "cmp: EOF on 'e' which is empty"
        (Invoke-TestGnu cmp '-l', 'a', 'c' -WorkingDirectory $dir).ErrorText | Should -Be "cmp: EOF on 'c' after byte 9"
    }

    It 'skips bytes with -i / --ignore-initial and SKIP operands' {
        (Invoke-TestGnu cmp '-i', '5', 'a', 'b' -WorkingDirectory $dir).Output | Should -Be @('a b differ: char 10, line 2')
        (Invoke-TestGnu cmp '-i', '2:0', 's', 'x' -WorkingDirectory $dir).ErrorText | Should -Be "cmp: EOF on 's' after byte 3, in line 1"
        (Invoke-TestGnu cmp 's', 'x', '2', '0' -WorkingDirectory $dir).ErrorText | Should -Be "cmp: EOF on 's' after byte 3, in line 1"
        (Invoke-TestGnu cmp '--ignore-initial=0x1', 's', 's' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu cmp '-i', '1K', 'a', 'b' -WorkingDirectory $dir).ExitCode | Should -Be 0
    }

    It 'compares at most LIMIT bytes with -n / --bytes' {
        (Invoke-TestGnu cmp '-n', '5', 'a', 'b' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu cmp '--bytes=2', 'x', 'y' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu cmp '-n', '9', 'a', 'c' -WorkingDirectory $dir).ExitCode | Should -Be 0
    }

    It 'reads standard input for - or a missing FILE2' {
        (Invoke-TestGnu cmp '-', 'c' -InputObject 'line one' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu cmp 'c' -InputObject 'line two' -WorkingDirectory $dir).Output | Should -Be @('c - differ: char 6, line 1')
    }

    It 'reports trouble with exit code 2' {
        $r = Invoke-TestGnu cmp 'a', 'nosuch' -WorkingDirectory $dir
        $r.ErrorText | Should -Be 'cmp: nosuch: No such file or directory'
        $r.ExitCode | Should -Be 2
        $r = Invoke-TestGnu cmp -WorkingDirectory $dir
        $r.ErrorText | Should -Match "missing operand after 'cmp'"
        $r.ExitCode | Should -Be 2
        (Invoke-TestGnu cmp '-l', '-s', 'a', 'b' -WorkingDirectory $dir).ErrorText | Should -Match 'options -l and -s are incompatible'
        (Invoke-TestGnu cmp '-i', 'x', 'a', 'b' -WorkingDirectory $dir).ErrorText | Should -Match "invalid --ignore-initial value 'x'"
        (Invoke-TestGnu cmp '-i', '1:2:3', 'a', 'b' -WorkingDirectory $dir).ErrorText | Should -Match "invalid --ignore-initial value '1:2:3'"
        (Invoke-TestGnu cmp 'a', 'b', 'c', 'd', 'e' -WorkingDirectory $dir).ErrorText | Should -Match "invalid --ignore-initial value 'c'"
        (Invoke-TestGnu cmp 'a', 'b', '1', '2', 'e' -WorkingDirectory $dir).ErrorText | Should -Match "extra operand 'e'"
        (Invoke-TestGnu cmp '-n', 'z', 'a', 'b' -WorkingDirectory $dir).ErrorText | Should -Match "invalid --bytes value 'z'"
    }
}
