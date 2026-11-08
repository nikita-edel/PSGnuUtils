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

Describe 'tail --follow' {
    BeforeAll {
        # Each poll (Wait-GnuTailInterval) runs the next action; --pid "dies" after the last one.
        function Set-TailScript {
            param([scriptblock[]]$Actions)
            $global:PSGnuTailActions = $Actions
            $global:PSGnuTailStep = 0
        }
    }

    BeforeEach {
        $script:dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $null = New-Item -ItemType Directory -Path $dir
        $script:log = Join-Path $dir 'log.txt'
        [System.IO.File]::WriteAllText($log, "a`nb`n")
        Mock -ModuleName PSGnuUtils Wait-GnuTailInterval {
            $step = $global:PSGnuTailStep
            $global:PSGnuTailStep++
            if ($step -lt $global:PSGnuTailActions.Count) { & $global:PSGnuTailActions[$step] }
        }
        Mock -ModuleName PSGnuUtils Test-GnuProcessAlive { $global:PSGnuTailStep -lt $global:PSGnuTailActions.Count }
    }

    AfterAll {
        Remove-Variable -Name PSGnuTailActions, PSGnuTailStep -Scope Global -ErrorAction SilentlyContinue
    }

    It 'prints appended lines with -f until --pid dies, unfinished lines once the file stops growing' {
        Set-TailScript @(
            { [System.IO.File]::AppendAllText($log, "c`n") },
            { [System.IO.File]::AppendAllText($log, 'par') },
            { [System.IO.File]::AppendAllText($log, "tial`nd") },
            { },
            { }
        )
        $r = Invoke-TestGnu tail '-f', '--pid=1', 'log.txt' -WorkingDirectory $dir
        $r.Output | Should -Be @('a', 'b', 'c', 'partial', 'd')
        $r.ExitCode | Should -Be 0
    }

    It 'prints an unfinished line when --pid dies' {
        Set-TailScript @({ [System.IO.File]::AppendAllText($log, 'end') })
        (Invoke-TestGnu tail '-n', '1', '--follow', '--pid', '1', '-s', '0.1', 'log.txt' -WorkingDirectory $dir).Output | Should -Be @('b', 'end')
    }

    It 'reports truncated files' {
        Set-TailScript @({ [System.IO.File]::WriteAllText($log, "n`n") }, { })
        $r = Invoke-TestGnu tail '-f', '--pid=1', '--sleep-interval=0.5', 'log.txt' -WorkingDirectory $dir
        $r.Output | Should -Be @('a', 'b', 'n')
        $r.WarningText | Should -Match 'log.txt: file truncated'
    }

    It 'follows the name with -F / --follow=name across removal and re-creation' {
        Set-TailScript @(
            { Remove-Item -LiteralPath $log },
            { [System.IO.File]::WriteAllText($log, "fresh`n") },
            { }
        )
        $r = Invoke-TestGnu tail '-F', '--pid=1', 'log.txt' -WorkingDirectory $dir
        $r.Output | Should -Be @('a', 'b', 'fresh')
        $r.WarningText | Should -Match "'log.txt' has become inaccessible: No such file or directory"
        $r.WarningText | Should -Match "'log.txt' has appeared;  following new file"
        Set-TailScript @({ [System.IO.File]::AppendAllText($log, "more`n") }, { })
        (Invoke-TestGnu tail '--follow=name', '--max-unchanged-stats=5', '--pid=1', 'log.txt' -WorkingDirectory $dir).Output | Should -Be @('fresh', 'more')
    }

    It 'waits for missing files with --retry' {
        Set-TailScript @({ [System.IO.File]::WriteAllText((Join-Path $dir 'later.txt'), "late`n") }, { })
        $r = Invoke-TestGnu tail '--follow=name', '--retry', '--pid=1', 'later.txt' -WorkingDirectory $dir
        $r.Output | Should -Be @('late')
        $r.WarningText | Should -Match 'has appeared'
    }

    It 'prints headers when switching between files' {
        $other = Join-Path $dir 'other.txt'
        [System.IO.File]::WriteAllText($other, "x`n")
        Set-TailScript @({ [System.IO.File]::AppendAllText($log, "c`n") }, { [System.IO.File]::AppendAllText($other, "y`n"); [System.IO.File]::AppendAllText($log, "d`n") }, { })
        (Invoke-TestGnu tail '-f', '--pid=1', 'log.txt', 'other.txt' -WorkingDirectory $dir).Output |
            Should -Be @('==> log.txt <==', 'a', 'b', '', '==> other.txt <==', 'x', '', '==> log.txt <==', 'c', 'd', '', '==> other.txt <==', 'y')
    }

    It 'stops when the pipeline stops' {
        Set-TailScript @({ [System.IO.File]::AppendAllText($log, "c`n") }, { [System.IO.File]::AppendAllText($log, "d`n") })
        Mock -ModuleName PSGnuUtils Test-GnuProcessAlive { $true }
        @(Invoke-GnuTail -f (Join-Path $dir 'log.txt') | Select-Object -First 3) | Should -Be @('a', 'b', 'c')
    }

    It 'does not follow standard input or missing files' {
        $r = Invoke-TestGnu tail '-f' -InputObject 'p', 'q'
        $r.Output | Should -Be @('p', 'q')
        $r.WarningText | Should -Match 'following standard input indefinitely is ineffective'
        $r = Invoke-TestGnu tail '-f', 'missing.txt' -WorkingDirectory $dir
        $r.ErrorText | Should -Match 'no files remaining'
        $r.ExitCode | Should -Be 1
    }

    It 'rejects bad follow arguments' {
        (Invoke-TestGnu tail '--follow=xyz', 'log.txt' -WorkingDirectory $dir).ErrorText | Should -Match "invalid argument 'xyz' for '--follow'"
        (Invoke-TestGnu tail '-f', '-s', 'x', 'log.txt' -WorkingDirectory $dir).ErrorText | Should -Match "invalid number of seconds: 'x'"
        (Invoke-TestGnu tail '-f', '--pid=x', 'log.txt' -WorkingDirectory $dir).ErrorText | Should -Match "invalid PID: 'x'"
    }

}

Describe 'tail --follow helpers' {
    It 'has working helpers' {
        InModuleScope PSGnuUtils {
            $clock = [System.Diagnostics.Stopwatch]::StartNew()
            Wait-GnuTailInterval -Seconds 0.05
            $clock.ElapsedMilliseconds | Should -BeGreaterOrEqual 30
            Test-GnuProcessAlive -Id $PID | Should -BeTrue
            Test-GnuProcessAlive -Id 999999 | Should -BeFalse
            Read-GnuTailAppended -File @{ Path = (Join-Path $TestDrive 'nope'); Stream = $null; Position = 0 } | Should -BeNullOrEmpty
        }
    }
}
