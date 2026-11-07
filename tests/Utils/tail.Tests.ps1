BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'tail' {
    BeforeAll {
        $script:dir = Join-Path $TestDrive 'tail'
        $null = New-TestFile -Path (Join-Path $dir 'twelve.txt') -Content (((1..12 | ForEach-Object { "line$_" }) -join "`n") + "`n")
        $null = New-TestFile -Path (Join-Path $dir 'short.txt') -Content "a`nb`n"
        $null = New-TestFile -Path (Join-Path $dir 'zero.txt') -Content "r1`0r2`0r3`0"
    }

    It 'prints the last 10 lines by default' {
        $r = Invoke-TestGnu tail 'twelve.txt' -WorkingDirectory $dir
        $r.Output.Count | Should -Be 10
        $r.Output[0] | Should -Be 'line3'
    }

    It 'prints the last NUM lines with -n / --lines and -NUM' {
        (Invoke-TestGnu tail '-n', '2', 'twelve.txt' -WorkingDirectory $dir).Output | Should -Be @('line11', 'line12')
        (Invoke-TestGnu tail '--lines=1', 'twelve.txt' -WorkingDirectory $dir).Output | Should -Be @('line12')
        (Invoke-TestGnu tail '-3', 'twelve.txt' -WorkingDirectory $dir).Output | Should -Be @('line10', 'line11', 'line12')
        (Invoke-TestGnu tail '-n', '-2', 'short.txt' -WorkingDirectory $dir).Output | Should -Be @('a', 'b')
    }

    It 'starts at line NUM with -n +NUM' {
        (Invoke-TestGnu tail '-n', '+11', 'twelve.txt' -WorkingDirectory $dir).Output | Should -Be @('line11', 'line12')
        (Invoke-TestGnu tail '-n', '+2' -InputObject 'header', 'x', 'y').Output | Should -Be @('x', 'y')
        (Invoke-TestGnu tail '-n', '+0', 'short.txt' -WorkingDirectory $dir).Output | Should -Be @('a', 'b')
    }

    It 'prints bytes with -c / --bytes' {
        (Invoke-TestGnu tail '-c', '2', 'short.txt' -WorkingDirectory $dir).Output | Should -Be @('b')
        (Invoke-TestGnu tail '--bytes=+3', 'short.txt' -WorkingDirectory $dir).Output | Should -Be @('b')
    }

    It 'reads pipeline input' {
        (Invoke-TestGnu tail '-n', '1' -InputObject 'a', 'b', 'c').Output | Should -Be @('c')
    }

    It 'prints headers for several files, -q / --quiet / --silent hide them' {
        (Invoke-TestGnu tail '-n', '1', 'short.txt', 'twelve.txt' -WorkingDirectory $dir).Output | Should -Be @('==> short.txt <==', 'b', '', '==> twelve.txt <==', 'line12')
        (Invoke-TestGnu tail '-q', '-n', '1', 'short.txt', 'twelve.txt' -WorkingDirectory $dir).Output | Should -Be @('b', 'line12')
        (Invoke-TestGnu tail '--quiet', '-n', '1', 'short.txt', 'short.txt' -WorkingDirectory $dir).Output | Should -Be @('b', 'b')
        (Invoke-TestGnu tail '--silent', '-n', '1', 'short.txt', 'short.txt' -WorkingDirectory $dir).Output | Should -Be @('b', 'b')
    }

    It 'always prints headers with -v / --verbose' {
        (Invoke-TestGnu tail '-v', '-n', '1', 'short.txt' -WorkingDirectory $dir).Output | Should -Be @('==> short.txt <==', 'b')
        (Invoke-TestGnu tail '--verbose', '-n', '1' -InputObject 'p').Output | Should -Be @('==> standard input <==', 'p')
    }

    It 'splits on NUL with -z / --zero-terminated' {
        (Invoke-TestGnu tail '-z', '-n', '1', 'zero.txt' -WorkingDirectory $dir).Output | Should -Be @("r3`0")
        (Invoke-TestGnu tail '--zero-terminated', '-n', '+2', 'zero.txt' -WorkingDirectory $dir).Output | Should -Be @("r2`0r3`0")
    }

    It 'rejects invalid counts' {
        $r = Invoke-TestGnu tail '-n', 'abc' -InputObject 'a'
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match "invalid number of lines: 'abc'"
    }

    It 'reports missing files like GNU' {
        $r = Invoke-TestGnu tail 'missing.txt' -WorkingDirectory $dir
        $r.ErrorText | Should -BeExactly "tail: cannot open 'missing.txt' for reading: No such file or directory"
        $r.ExitCode | Should -Be 1
    }
}
