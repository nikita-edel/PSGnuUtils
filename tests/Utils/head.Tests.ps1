BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'head' {
    BeforeAll {
        $script:dir = Join-Path $TestDrive 'head'
        $null = New-TestFile -Path (Join-Path $dir 'twelve.txt') -Content ((1..12 | ForEach-Object { "line$_" }) -join "`n")
        $null = New-TestFile -Path (Join-Path $dir 'short.txt') -Content "a`nb`n"
        $null = New-TestFile -Path (Join-Path $dir 'zero.txt') -Content "r1`0r2`0r3`0"
    }

    It 'prints the first 10 lines by default' {
        $r = Invoke-TestGnu head 'twelve.txt' -WorkingDirectory $dir
        $r.Output.Count | Should -Be 10
        $r.Output[9] | Should -Be 'line10'
    }

    It 'prints NUM lines with -n / --lines and -NUM' {
        (Invoke-TestGnu head '-n', '2', 'twelve.txt' -WorkingDirectory $dir).Output | Should -Be @('line1', 'line2')
        (Invoke-TestGnu head '--lines=3', 'twelve.txt' -WorkingDirectory $dir).Output.Count | Should -Be 3
        (Invoke-TestGnu head '-1', 'twelve.txt' -WorkingDirectory $dir).Output | Should -Be @('line1')
        (Invoke-TestGnu head '-n', '0', 'twelve.txt' -WorkingDirectory $dir).Output.Count | Should -Be 0
    }

    It 'prints all but the last NUM lines with -n -NUM' {
        (Invoke-TestGnu head '-n', '-10', 'twelve.txt' -WorkingDirectory $dir).Output | Should -Be @('line1', 'line2')
        (Invoke-TestGnu head '-n', '-20', 'twelve.txt' -WorkingDirectory $dir).Output.Count | Should -Be 0
    }

    It 'prints bytes with -c / --bytes' {
        (Invoke-TestGnu head '-c', '3', 'short.txt' -WorkingDirectory $dir).Output | Should -Be @('a', 'b')
        (Invoke-TestGnu head '--bytes=1', 'short.txt' -WorkingDirectory $dir).Output | Should -Be @('a')
        (Invoke-TestGnu head '-c', '-2', 'short.txt' -WorkingDirectory $dir).Output | Should -Be @('a')
        (Invoke-TestGnu head '-c', '1K', 'short.txt' -WorkingDirectory $dir).Output | Should -Be @('a', 'b')
    }

    It 'uses the last of -c and -n' {
        (Invoke-TestGnu head '-c', '1', '-n', '1', 'twelve.txt' -WorkingDirectory $dir).Output | Should -Be @('line1')
    }

    It 'streams pipeline input' {
        (Invoke-TestGnu head '-n', '2' -InputObject 'a', 'b', 'c').Output | Should -Be @('a', 'b')
        (Invoke-TestGnu head -InputObject (1..100)).Output.Count | Should -Be 10
    }

    It 'prints headers for several files, -q / --quiet / --silent hide them' {
        $r = Invoke-TestGnu head '-n', '1', 'short.txt', 'twelve.txt' -WorkingDirectory $dir
        $r.Output | Should -Be @('==> short.txt <==', 'a', '', '==> twelve.txt <==', 'line1')
        (Invoke-TestGnu head '-q', '-n', '1', 'short.txt', 'twelve.txt' -WorkingDirectory $dir).Output | Should -Be @('a', 'line1')
        (Invoke-TestGnu head '--quiet', '-n', '1', 'short.txt', 'twelve.txt' -WorkingDirectory $dir).Output | Should -Be @('a', 'line1')
        (Invoke-TestGnu head '--silent', '-n', '1', 'short.txt', 'twelve.txt' -WorkingDirectory $dir).Output | Should -Be @('a', 'line1')
    }

    It 'always prints headers with -v / --verbose' {
        (Invoke-TestGnu head '-v', '-n', '1', 'short.txt' -WorkingDirectory $dir).Output | Should -Be @('==> short.txt <==', 'a')
        (Invoke-TestGnu head '--verbose', '-n', '1' -InputObject 'p').Output | Should -Be @('==> standard input <==', 'p')
    }

    It 'splits on NUL with -z / --zero-terminated' {
        (Invoke-TestGnu head '-z', '-n', '2', 'zero.txt' -WorkingDirectory $dir).Output | Should -Be @("r1`0r2`0")
        (Invoke-TestGnu head '--zero-terminated', '-n', '1', 'zero.txt' -WorkingDirectory $dir).Output | Should -Be @("r1`0")
    }

    It 'rejects invalid counts' {
        $r = Invoke-TestGnu head '-n', 'abc', 'short.txt' -WorkingDirectory $dir
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match "invalid number of lines: 'abc'"
        (Invoke-TestGnu head '-c', 'x' -InputObject 'a').ErrorText | Should -Match "invalid number of bytes: 'x'"
    }

    It 'reports missing files like GNU and continues' {
        $r = Invoke-TestGnu head '-n', '1', 'missing.txt', 'short.txt' -WorkingDirectory $dir
        $r.ErrorText | Should -BeExactly "head: cannot open 'missing.txt' for reading: No such file or directory"
        $r.Output | Should -Be @('==> short.txt <==', 'a')
        $r.ExitCode | Should -Be 1
        (Invoke-TestGnu head $dir).ErrorText | Should -Match 'Is a directory'
    }
}
