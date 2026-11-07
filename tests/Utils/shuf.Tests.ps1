BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'shuf' {
    BeforeAll {
        $script:dir = Join-Path $TestDrive 'shuf'
        $null = New-TestFile -Path (Join-Path $dir 'lines.txt') -Content "a`nb`nc`nd`n"
        $null = New-TestFile -Path (Join-Path $dir 'seed') -Content 'some random bytes'
    }

    It 'prints a permutation of the input lines' {
        $r = Invoke-TestGnu shuf 'lines.txt' -WorkingDirectory $dir
        $r.Output | Sort-Object | Should -Be @('a', 'b', 'c', 'd')
        $r.ExitCode | Should -Be 0
        (Invoke-TestGnu shuf -InputObject 'x', 'y').Output | Sort-Object | Should -Be @('x', 'y')
    }

    It 'shuffles arguments with -e / --echo' {
        (Invoke-TestGnu shuf '-e', 'p', 'q', 'r').Output | Sort-Object | Should -Be @('p', 'q', 'r')
        (Invoke-TestGnu shuf '--echo', 'only').Output | Should -Be @('only')
    }

    It 'shuffles a number range with -i / --input-range' {
        (Invoke-TestGnu shuf '-i', '1-5').Output | Sort-Object { [int]$_ } | Should -Be @('1', '2', '3', '4', '5')
        (Invoke-TestGnu shuf '--input-range=7-7').Output | Should -Be @('7')
        (Invoke-TestGnu shuf '-i', '3-2').Output | Should -BeNullOrEmpty
    }

    It 'limits the output with -n / --head-count' {
        $r = Invoke-TestGnu shuf '-n', '2', '-i', '1-10'
        $r.Output.Count | Should -Be 2
        ($r.Output | Select-Object -Unique).Count | Should -Be 2
        (Invoke-TestGnu shuf '--head-count=9', '-e', 'a', 'b').Output.Count | Should -Be 2
        (Invoke-TestGnu shuf '-n', '0', '-e', 'a').Output | Should -BeNullOrEmpty
    }

    It 'repeats lines with -r / --repeat' {
        (Invoke-TestGnu shuf '-r', '-n', '5', '-e', 'a').Output | Should -Be @('a', 'a', 'a', 'a', 'a')
        (Invoke-TestGnu shuf '--repeat', '--head-count', '3', '-i', '1-2').Output.Count | Should -Be 3
    }

    It 'repeats endlessly without -n (until the pipeline stops it)' {
        @(Invoke-GnuShuf -r -e x | Select-Object -First 4) | Should -Be @('x', 'x', 'x', 'x')
    }

    It 'is reproducible with --random-source' {
        $first = (Invoke-TestGnu shuf '--random-source=seed', '-i', '1-50' -WorkingDirectory $dir).Output
        $second = (Invoke-TestGnu shuf '--random-source', 'seed', '-i', '1-50' -WorkingDirectory $dir).Output
        $second | Should -Be $first
        (Invoke-TestGnu shuf '--random-source=nope', '-e', 'a' -WorkingDirectory $dir).ExitCode | Should -Be 1
    }

    It 'writes to a file with -o / --output' {
        $r = Invoke-TestGnu shuf '-o', 'out.txt', '-e', 'one' -WorkingDirectory $dir
        $r.Output | Should -BeNullOrEmpty
        [System.IO.File]::ReadAllText((Join-Path $dir 'out.txt')) | Should -Be "one`n"
        $null = Invoke-TestGnu shuf '--output=empty.txt', '-i', '2-1' -WorkingDirectory $dir
        [System.IO.File]::ReadAllText((Join-Path $dir 'empty.txt')) | Should -Be ''
        $r = Invoke-TestGnu shuf '-o', 'rep.txt', '-r', '-e', 'z' -WorkingDirectory $dir
        $r.ErrorText | Should -Match '--repeat with --output needs --head-count'
        $r.ExitCode | Should -Be 1
        (Invoke-TestGnu shuf '-o', (Join-Path $dir 'no/such/file'), '-e', 'a').ErrorText | Should -Match 'No such file or directory'
    }

    It 'uses NUL as the delimiter with -z / --zero-terminated' {
        $null = New-TestFile -Path (Join-Path $dir 'nul.txt') -Content "a`0b`0"
        $r = Invoke-TestGnu shuf '-z', 'nul.txt' -WorkingDirectory $dir
        $r.Output.Count | Should -Be 1
        @($r.Output[0].Split([char]0) | Where-Object { $_ } | Sort-Object) | Should -Be @('a', 'b')
        $null = Invoke-TestGnu shuf '--zero-terminated', '-o', 'z.txt', '-e', 'q' -WorkingDirectory $dir
        [System.IO.File]::ReadAllText((Join-Path $dir 'z.txt')) | Should -Be "q`0"
    }

    It 'rejects bad arguments' {
        (Invoke-TestGnu shuf '-i', '5-1').ErrorText | Should -Match "invalid input range: '5-1'"
        (Invoke-TestGnu shuf '-i', 'x').ErrorText | Should -Match "invalid input range: 'x'"
        (Invoke-TestGnu shuf '-i', '1-2', 'extra').ErrorText | Should -Match "extra operand 'extra'"
        (Invoke-TestGnu shuf 'a', 'b').ErrorText | Should -Match "extra operand 'b'"
        (Invoke-TestGnu shuf '-n', 'x', '-e', 'a').ErrorText | Should -Match "invalid line count: 'x'"
        (Invoke-TestGnu shuf 'nope' -WorkingDirectory $dir).ExitCode | Should -Be 1
        $r = Invoke-TestGnu shuf '-r', '-e'
        $r.ErrorText | Should -Match 'no lines to repeat'
        $r.ExitCode | Should -Be 1
        (Invoke-TestGnu shuf '-r', '-n', '0', '-e').ExitCode | Should -Be 0
    }
}
