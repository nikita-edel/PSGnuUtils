BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'tac' {
    BeforeAll {
        $script:dir = Join-Path $TestDrive 'tac'
        $null = New-TestFile -Path (Join-Path $dir 'lines.txt') -Content "1`n2`n3`n"
        $null = New-TestFile -Path (Join-Path $dir 'open.txt') -Content "a`nb`nc"
        $null = New-TestFile -Path (Join-Path $dir 'crlf.txt') -Content "x`r`ny`r`n"
        $null = New-TestFile -Path (Join-Path $dir 'sep.txt') -Content 'a,b,c,'
    }

    It 'reverses lines of files and pipeline input' {
        (Invoke-TestGnu tac 'lines.txt' -WorkingDirectory $dir).Output | Should -Be @('3', '2', '1')
        (Invoke-TestGnu tac -InputObject 1, 2, 3).Output | Should -Be @('3', '2', '1')
        (Invoke-TestGnu tac 'crlf.txt' -WorkingDirectory $dir).Output | Should -Be @('y', 'x')
    }

    It 'joins an unterminated last line with the next record like GNU' {
        (Invoke-TestGnu tac 'open.txt' -WorkingDirectory $dir).Output | Should -Be @('cb', 'a')
    }

    It 'uses a custom separator with -s / --separator' {
        (Invoke-TestGnu tac '-s', ',', 'sep.txt' -WorkingDirectory $dir).Output | Should -Be @('c,b,a,')
        (Invoke-TestGnu tac '--separator=,', 'sep.txt' -WorkingDirectory $dir).Output | Should -Be @('c,b,a,')
    }

    It 'attaches the separator before records with -b / --before' {
        (Invoke-TestGnu tac '-b', '-s', ',', 'sep.txt' -WorkingDirectory $dir).Output | Should -Be @(',,c,ba')
        # printf 'a\nb\n' | tac -b  ->  "\n\nba"
        (Invoke-TestGnu tac '--before' -InputObject 'a', 'b').Output | Should -Be @('', '', 'ba')
    }

    It 'treats the separator as a regular expression with -r / --regex' {
        $null = New-TestFile -Path (Join-Path $dir 'regex.txt') -Content 'a1b22c333'
        (Invoke-TestGnu tac '-r', '-s', '[0-9]+', 'regex.txt' -WorkingDirectory $dir).Output | Should -Be @('c333b22a1')
        # records: a1 b2 2 c3 3 3
        (Invoke-TestGnu tac '--regex', '--separator=\d', 'regex.txt' -WorkingDirectory $dir).Output | Should -Be @('33c32b2a1')
    }

    It 'rejects an empty separator' {
        $r = Invoke-TestGnu tac '-s', '' -InputObject 'x'
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match 'separator cannot be empty'
    }

    It 'reports missing files' {
        $r = Invoke-TestGnu tac 'missing.txt' -WorkingDirectory $dir
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match "failed to open 'missing.txt' for reading: No such file or directory"
    }
}
