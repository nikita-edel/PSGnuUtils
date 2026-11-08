BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')

    function Set-DiffFile {
        param([string]$Name, [string[]]$Lines, [switch]$NoFinalNewline)
        $text = ''
        if ($Lines.Count -gt 0) { $text = ($Lines -join "`n"); if (-not $NoFinalNewline) { $text += "`n" } }
        New-TestFile -Path (Join-Path $dir $Name) -Content $text
    }

    function Test-DiffScript {
        # Applying the changes to one sequence must give the other, whatever the search chose.
        param([string[]]$Old, [string[]]$New, [switch]$Minimal)
        $changes = InModuleScope PSGnuUtils -Parameters @{ O = $Old; N = $New; M = [bool]$Minimal } {
            param($O, $N, $M)
            $state = @{ Ed = $false; IgnoreSpaceChange = $false; IgnoreAllSpace = $false; IgnoreTrailing = $false; IgnoreTabs = $false; IgnoreCase = $false; IgnoreBlank = $false; Horizon = 0; Minimal = $M; TabSize = 8 }
            Get-GnuDiffScript -State $state -First @{ Lines = $O; Missing = $false } -Second @{ Lines = $N; Missing = $false }
        }
        $result = New-Object 'System.Collections.Generic.List[string]'
        $i = 0
        foreach ($change in @($changes)) {
            while ($i -lt $change.Line0) { $result.Add($Old[$i]); $i++ }
            $i += $change.Deleted
            for ($k = 0; $k -lt $change.Inserted; $k++) { $result.Add($New[$change.Line1 + $k]) }
        }
        while ($i -lt $Old.Count) { $result.Add($Old[$i]); $i++ }
        @($result) | Should -Be $New
    }
}

# Expected results were compared with GNU diffutils 3.12 (see docs/DEVLOG.md).
Describe 'diff' {
    BeforeEach {
        $script:dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $null = New-Item -ItemType Directory -Path $dir
        $script:letters = [string[]][char[]]'abcdefghijklmnopqrst'
        $null = Set-DiffFile 'base' $letters
        $null = Set-DiffFile 'two' @($letters | ForEach-Object { if ($_ -ceq 'c') { 'C' } elseif ($_ -ceq 'r') { 'R' } else { $_ } })
        $null = Set-DiffFile 'del' @($letters | Where-Object { $_ -cne 'e' })
        $null = Set-DiffFile 'ins' @('a', 'b', 'c', 'd', 'e', 'new', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't')
        $null = Set-DiffFile 'empty' @()
    }

    Context 'normal format' {
        It 'prints changes, deletions and additions' {
            $r = Invoke-TestGnu diff 'base', 'two' -WorkingDirectory $dir
            $r.Output | Should -Be @('3c3', '< c', '---', '> C', '18c18', '< r', '---', '> R')
            $r.ExitCode | Should -Be 1
            (Invoke-TestGnu diff 'base', 'del' -WorkingDirectory $dir).Output | Should -Be @('5d4', '< e')
            (Invoke-TestGnu diff 'base', 'ins' -WorkingDirectory $dir).Output | Should -Be @('5a6', '> new')
            (Invoke-TestGnu diff '--normal', 'base', 'del' -WorkingDirectory $dir).Output | Should -Be @('5d4', '< e')
        }

        It 'exits 0 without output for identical files' {
            $r = Invoke-TestGnu diff 'base', 'base' -WorkingDirectory $dir
            $r.Output | Should -BeNullOrEmpty
            $r.ExitCode | Should -Be 0
        }

        It 'handles empty files and ranges' {
            (Invoke-TestGnu diff 'empty', 'empty' -WorkingDirectory $dir).ExitCode | Should -Be 0
            $null = Set-DiffFile 'three' @('x', 'y', 'z')
            (Invoke-TestGnu diff 'empty', 'three' -WorkingDirectory $dir).Output[0] | Should -Be '0a1,3'
            (Invoke-TestGnu diff 'three', 'empty' -WorkingDirectory $dir).Output[0] | Should -Be '1,3d0'
            (Invoke-TestGnu diff 'three', 'base' -WorkingDirectory $dir).Output[0] | Should -Be '1,3c1,20'
        }

        It 'marks a missing final newline' {
            $null = Set-DiffFile 'nonl' @('a', 'b') -NoFinalNewline
            $null = Set-DiffFile 'nl' @('a', 'b')
            (Invoke-TestGnu diff 'nonl', 'nl' -WorkingDirectory $dir).Output | Should -Be @('2c2', '< b', '\ No newline at end of file', '---', '> b')
            (Invoke-TestGnu diff 'nl', 'nonl' -WorkingDirectory $dir).Output | Should -Be @('2c2', '< b', '---', '> b', '\ No newline at end of file')
            (Invoke-TestGnu diff '-b', 'nonl', 'nl' -WorkingDirectory $dir).ExitCode | Should -Be 0
        }

        It 'reads standard input for -' {
            (Invoke-TestGnu diff '-', 'base' -WorkingDirectory $dir -InputObject $letters).ExitCode | Should -Be 0
            (Invoke-TestGnu diff 'del', '-' -WorkingDirectory $dir -InputObject $letters).Output | Should -Be @('4a5', '> e')
        }
    }

    Context 'unified format' {
        It 'prints headers and hunks with -u, -U and --unified' {
            $r = Invoke-TestGnu diff '-u', 'base', 'del' -WorkingDirectory $dir
            $r.Output[0] | Should -Match '^--- base\t\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{9} [-+]\d{4}$'
            $r.Output[1] | Should -Match '^\+\+\+ del\t'
            $r.Output[2..9] | Should -Be @('@@ -2,7 +2,6 @@', ' b', ' c', ' d', '-e', ' f', ' g', ' h')
            (Invoke-TestGnu diff '-U', '0', 'base', 'two' -WorkingDirectory $dir).Output[2..4] | Should -Be @('@@ -3 +3 @@', '-c', '+C')
            (Invoke-TestGnu diff '-U1', 'base', 'two' -WorkingDirectory $dir).Output[2] | Should -Be '@@ -2,3 +2,3 @@'
            (Invoke-TestGnu diff '--unified', 'base', 'del' -WorkingDirectory $dir).Output[2] | Should -Be '@@ -2,7 +2,6 @@'
            (Invoke-TestGnu diff '--unified=1', 'base', 'del' -WorkingDirectory $dir).Output[2] | Should -Be '@@ -4,3 +4,2 @@'
            (Invoke-TestGnu diff '-U', '0', 'base', 'del' -WorkingDirectory $dir).Output[2] | Should -Be '@@ -5 +4,0 @@'
            (Invoke-TestGnu diff '-U', '0', 'base', 'ins' -WorkingDirectory $dir).Output[2] | Should -Be '@@ -5,0 +6 @@'
        }

        It 'merges hunks whose context touches' {
            (Invoke-TestGnu diff '-U', '20', 'base', 'two' -WorkingDirectory $dir).Output[2] | Should -Be '@@ -1,20 +1,20 @@'
        }

        It 'marks a missing final newline' {
            $null = Set-DiffFile 'nonl' @('a', 'b') -NoFinalNewline
            $null = Set-DiffFile 'nl' @('a', 'b')
            (Invoke-TestGnu diff '-u', 'nonl', 'nl' -WorkingDirectory $dir).Output[2..6] | Should -Be @('@@ -1,2 +1,2 @@', ' a', '-b', '\ No newline at end of file', '+b')
        }

        It 'shows ranges for empty sides' {
            $null = Set-DiffFile 'three' @('x', 'y', 'z')
            (Invoke-TestGnu diff '-u', 'empty', 'three' -WorkingDirectory $dir).Output[2] | Should -Be '@@ -0,0 +1,3 @@'
            (Invoke-TestGnu diff '-u', 'three', 'empty' -WorkingDirectory $dir).Output[2] | Should -Be '@@ -1,3 +0,0 @@'
        }
    }

    Context 'context format' {
        It 'prints headers and hunks with -c, -C and --context' {
            $r = Invoke-TestGnu diff '-c', 'base', 'two' -WorkingDirectory $dir
            $r.Output[0] | Should -Match '^\*\*\* base\t'
            $r.Output[1] | Should -Match '^--- two\t'
            $r.Output[2..10] | Should -Be @('***************', '*** 1,6 ****', '  a', '  b', '! c', '  d', '  e', '  f', '--- 1,6 ----')
            (Invoke-TestGnu diff '-C', '0', 'base', 'two' -WorkingDirectory $dir).Output[2..7] | Should -Be @('***************', '*** 3 ****', '! c', '--- 3 ----', '! C', '***************')
            (Invoke-TestGnu diff '-C1', 'base', 'del' -WorkingDirectory $dir).Output[2..7] | Should -Be @('***************', '*** 4,6 ****', '  d', '- e', '  f', '--- 4,5 ----')
            (Invoke-TestGnu diff '--context', 'base', 'ins' -WorkingDirectory $dir).Output[-1] | Should -Be '  h'
            (Invoke-TestGnu diff '--context=1', 'base', 'ins' -WorkingDirectory $dir).Output[2..7] | Should -Be @('***************', '*** 5,6 ****', '--- 5,7 ----', '  e', '+ new', '  f')
        }
    }

    Context 'ed format' {
        It 'prints an ed script from the end of the file' {
            (Invoke-TestGnu diff '-e', 'base', 'two' -WorkingDirectory $dir).Output | Should -Be @('18c', 'R', '.', '3c', 'C', '.')
            (Invoke-TestGnu diff '--ed', 'base', 'del' -WorkingDirectory $dir).Output | Should -Be @('5d')
            (Invoke-TestGnu diff '-e', 'base', 'ins' -WorkingDirectory $dir).Output | Should -Be @('5a', 'new', '.')
        }

        It 'protects a lone dot' {
            $null = Set-DiffFile 'd1' @('a', '.', 'b')
            $null = Set-DiffFile 'd2' @('a', '.', '.', 'c')
            (Invoke-TestGnu diff '-e', 'd1', 'd2' -WorkingDirectory $dir).Output | Should -Be @('3c', '..', '.', 's/.//', 'a', 'c', '.')
        }

        It 'refuses an incomplete last line' {
            $null = Set-DiffFile 'nonl' @('a', 'b') -NoFinalNewline
            $null = Set-DiffFile 'nl' @('a', 'b')
            $r = Invoke-TestGnu diff '-e', 'nonl', 'nl' -WorkingDirectory $dir
            $r.ErrorText | Should -Match '^diff: nonl: No newline at end of file'
            $r.ExitCode | Should -Be 2
        }
    }

    Context 'ignoring differences' {
        It 'ignores case with -i / --ignore-case' {
            $null = Set-DiffFile 'a1' @('ONE')
            $null = Set-DiffFile 'a2' @('one')
            (Invoke-TestGnu diff '-i', 'a1', 'a2' -WorkingDirectory $dir).ExitCode | Should -Be 0
            (Invoke-TestGnu diff '--ignore-case', 'a1', 'a2' -WorkingDirectory $dir).ExitCode | Should -Be 0
        }

        It 'ignores space with -b, -w, -Z and -E' {
            $null = Set-DiffFile 's1' @('a  b', "`tc d", 'e')
            $null = Set-DiffFile 's2' @('a b', '        c   d', 'e  ')
            (Invoke-TestGnu diff 's1', 's2' -WorkingDirectory $dir).ExitCode | Should -Be 1
            (Invoke-TestGnu diff '-b', 's1', 's2' -WorkingDirectory $dir).ExitCode | Should -Be 0
            (Invoke-TestGnu diff '--ignore-space-change', 's1', 's2' -WorkingDirectory $dir).ExitCode | Should -Be 0
            (Invoke-TestGnu diff '-w', 's1', 's2' -WorkingDirectory $dir).ExitCode | Should -Be 0
            (Invoke-TestGnu diff '--ignore-all-space', 's1', 's2' -WorkingDirectory $dir).ExitCode | Should -Be 0
            $null = Set-DiffFile 'z1' @('a')
            $null = Set-DiffFile 'z2' @('a   ')
            (Invoke-TestGnu diff '-Z', 'z1', 'z2' -WorkingDirectory $dir).ExitCode | Should -Be 0
            (Invoke-TestGnu diff '--ignore-trailing-space', 'z1', 'z2' -WorkingDirectory $dir).ExitCode | Should -Be 0
            $null = Set-DiffFile 't1' @("a`tb")
            $null = Set-DiffFile 't2' @('a       b')
            (Invoke-TestGnu diff '-E', 't1', 't2' -WorkingDirectory $dir).ExitCode | Should -Be 0
            (Invoke-TestGnu diff '--ignore-tab-expansion', 't1', 't2' -WorkingDirectory $dir).ExitCode | Should -Be 0
        }

        It 'ignores blank line changes with -B / --ignore-blank-lines' {
            $null = Set-DiffFile 'b1' @('keep', '', '', 'last')
            $null = Set-DiffFile 'b2' @('keep', 'last')
            (Invoke-TestGnu diff '-B', 'b1', 'b2' -WorkingDirectory $dir).Output | Should -BeNullOrEmpty
            (Invoke-TestGnu diff '--ignore-blank-lines', 'b1', 'b2' -WorkingDirectory $dir).ExitCode | Should -Be 0
            (Invoke-TestGnu diff '-uB', 'b1', 'b2' -WorkingDirectory $dir).ExitCode | Should -Be 0
            (Invoke-TestGnu diff '-B', 'base', 'two' -WorkingDirectory $dir).Output[0] | Should -Be '3c3'
            $null = Set-DiffFile 'b3' @('keep', '', 'x', '', 'y', 'z', 'last')
            $null = Set-DiffFile 'b4' @('keep', 'x', 'CHANGED', 'y', 'z', 'last')
            (Invoke-TestGnu diff '-uB', 'b3', 'b4' -WorkingDirectory $dir).Output[2..4] | Should -Be @('@@ -1,7 +1,6 @@', ' keep', '-')
            (Invoke-TestGnu diff '-U', '0', '-B', 'b3', 'b4' -WorkingDirectory $dir).Output[2] | Should -Be '@@ -4 +3 @@'
            $null = Set-DiffFile 'b5' @('keep', 'old', 'x', '', 'y', 'z', 'last')
            $null = Set-DiffFile 'b6' @('keep', 'NEW', 'x', 'y', 'z', 'last')
            (Invoke-TestGnu diff '-U', '1', '-B', 'b5', 'b6' -WorkingDirectory $dir).Output[2..5] | Should -Be @('@@ -1,3 +1,3 @@', ' keep', '-old', '+NEW')
        }

        It 'strips carriage returns with --strip-trailing-cr' {
            $null = New-TestFile -Path (Join-Path $dir 'crlf') -Content "a`r`nb`r`n"
            $null = Set-DiffFile 'lf' @('a', 'b')
            (Invoke-TestGnu diff 'crlf', 'lf' -WorkingDirectory $dir).ExitCode | Should -Be 1
            (Invoke-TestGnu diff '--strip-trailing-cr', 'crlf', 'lf' -WorkingDirectory $dir).ExitCode | Should -Be 0
        }
    }

    Context 'reports' {
        It 'only reports differences with -q / --brief' {
            (Invoke-TestGnu diff '-q', 'base', 'two' -WorkingDirectory $dir).Output | Should -Be @('Files base and two differ')
            (Invoke-TestGnu diff '--brief', 'base', 'base' -WorkingDirectory $dir).Output | Should -BeNullOrEmpty
        }

        It 'reports identical files with -s / --report-identical-files' {
            (Invoke-TestGnu diff '-s', 'base', 'base' -WorkingDirectory $dir).Output | Should -Be @('Files base and base are identical')
            (Invoke-TestGnu diff '--report-identical-files', 'base', 'del' -WorkingDirectory $dir).Output[0] | Should -Be '5d4'
        }

        It 'treats files with NUL bytes as binary unless -a / --text' {
            $null = New-TestFile -Path (Join-Path $dir 'bin1') -Bytes ([byte[]](97, 0, 98, 10))
            $null = New-TestFile -Path (Join-Path $dir 'bin2') -Bytes ([byte[]](97, 0, 99, 10))
            $null = New-TestFile -Path (Join-Path $dir 'bin3') -Bytes ([byte[]](97, 0, 98, 10))
            $r = Invoke-TestGnu diff 'bin1', 'bin2' -WorkingDirectory $dir
            $r.Output | Should -Be @('Binary files bin1 and bin2 differ')
            $r.ExitCode | Should -Be 1
            (Invoke-TestGnu diff 'bin1', 'bin3' -WorkingDirectory $dir).ExitCode | Should -Be 0
            (Invoke-TestGnu diff '-a', 'bin1', 'bin2' -WorkingDirectory $dir).Output[0] | Should -Be '1c1'
            (Invoke-TestGnu diff '--text', 'bin1', 'bin2' -WorkingDirectory $dir).Output[0] | Should -Be '1c1'
            (Invoke-TestGnu diff '-q', 'bin1', 'bin2' -WorkingDirectory $dir).Output | Should -Be @('Files bin1 and bin2 differ')
        }
    }

    Context 'output details' {
        BeforeEach {
            $null = Set-DiffFile 't1' @("tab`tline")
            $null = Set-DiffFile 't2' @("tab`tLINE")
        }

        It 'expands tabs with -t / --expand-tabs and --tabsize' {
            (Invoke-TestGnu diff '-t', 't1', 't2' -WorkingDirectory $dir).Output[1] | Should -Be '< tab     line'
            (Invoke-TestGnu diff '--expand-tabs', 't1', 't2' -WorkingDirectory $dir).Output[1] | Should -Be '< tab     line'
            (Invoke-TestGnu diff '-t', '--tabsize=4', 't1', 't2' -WorkingDirectory $dir).Output[1] | Should -Be '< tab line'
        }

        It 'lines up with -T / --initial-tab' {
            (Invoke-TestGnu diff '-T', 't1', 't2' -WorkingDirectory $dir).Output[1] | Should -Be "<`ttab`tline"
            (Invoke-TestGnu diff '--initial-tab', 't1', 't2' -WorkingDirectory $dir).Output[3] | Should -Be ">`ttab`tLINE"
            (Invoke-TestGnu diff '-uT', 't1', 't2' -WorkingDirectory $dir).Output[3] | Should -Be "-`ttab`tline"
            (Invoke-TestGnu diff '-cT', 't1', 't2' -WorkingDirectory $dir).Output[4] | Should -Be "!`ttab`tline"
        }

        It 'shows the enclosing function with -p / --show-c-function and -F / --show-function-line' {
            $null = Set-DiffFile 'c1' @('int main(void)', '{', '  a;', '  b;', '  c;', '  d;', '  e;', '}', 'int other(void)', '{', '  f;', '  g;', '  h;', '  i;', '}')
            $null = Set-DiffFile 'c2' @('int main(void)', '{', '  a;', '  b;', '  c;', '  d;', '  e;', '}', 'int other(void)', '{', '  f;', '  g;', '  H;', '  i;', '}')
            (Invoke-TestGnu diff '-p', '-u', 'c1', 'c2' -WorkingDirectory $dir).Output[2] | Should -Be '@@ -10,6 +10,6 @@ int other(void)'
            (Invoke-TestGnu diff '--show-c-function', '-c', 'c1', 'c2' -WorkingDirectory $dir).Output[2] | Should -Be '*************** int other(void)'
            (Invoke-TestGnu diff '-p', 'c1', 'c2' -WorkingDirectory $dir).Output[2] | Should -Be '*************** int other(void)' -Because '-p alone selects the context format'
            (Invoke-TestGnu diff '-F', '^{', '-u', 'c1', 'c2' -WorkingDirectory $dir).Output[2] | Should -Be '@@ -10,6 +10,6 @@ {'
            (Invoke-TestGnu diff '--show-function-line=^int main', '-u', 'c1', 'c2' -WorkingDirectory $dir).Output[2] | Should -Be '@@ -10,6 +10,6 @@ int main(void)'
            (Invoke-TestGnu diff '-F', '^nothing', '-u', 'c1', 'c2' -WorkingDirectory $dir).Output[2] | Should -Be '@@ -10,6 +10,6 @@'
            $null = Set-DiffFile 'l1' @(('f' * 60), ' x', 'a')
            $null = Set-DiffFile 'l2' @(('f' * 60), ' x', 'b')
            (Invoke-TestGnu diff '-p', '-U0', 'l1', 'l2' -WorkingDirectory $dir).Output[2] | Should -Be ('@@ -3 +3 @@ ' + ('f' * 40))
        }

        It 'uses labels with -L / --label' {
            $r = Invoke-TestGnu diff '-L', 'left', '-L', 'right', '-u', 'base', 'del' -WorkingDirectory $dir
            $r.Output[0..1] | Should -Be @('--- left', '+++ right')
            (Invoke-TestGnu diff '--label', 'left', '-c', 'base', 'del' -WorkingDirectory $dir).Output[0] | Should -Be '*** left'
            $r = Invoke-TestGnu diff '-L', 'a', '-L', 'b', '-L', 'c', 'base', 'del' -WorkingDirectory $dir
            $r.ErrorText | Should -Be 'diff: too many file label options'
            $r.ExitCode | Should -Be 2
        }

        It 'accepts -d / --minimal, --speed-large-files and --horizon-lines' {
            foreach ($option in '-d', '--minimal', '--speed-large-files', '--horizon-lines=3') { (Invoke-TestGnu diff $option, 'base', 'del' -WorkingDirectory $dir).Output | Should -Be @('5d4', '< e') }
        }
    }

    Context 'directories' {
        BeforeEach {
            foreach ($name in 'd1/sub', 'd2/sub', 'd1/only1dir', 'd2/only2dir', 'd2/kind') { $null = New-Item -ItemType Directory -Path (Join-Path $dir $name) -Force }
            foreach ($row in @(@('d1/same', 'same'), @('d2/same', 'same'), @('d1/chg', 'a'), @('d2/chg', 'b'), @('d1/only1', 'o1'), @('d2/only2', 'o2'), @('d1/sub/f', 's1'), @('d2/sub/f', 's2'), @('d1/kind', 'x'), @('d1/only1dir/in', 'y'))) {
                $null = New-TestFile -Path (Join-Path $dir $row[0]) -Content "$($row[1])`n"
            }
        }

        It 'compares two directories' {
            $r = Invoke-TestGnu diff 'd1', 'd2' -WorkingDirectory $dir
            $r.Output | Should -Be @(
                'diff d1/chg d2/chg', '1c1', '< a', '---', '> b',
                'File d1/kind is a regular file while file d2/kind is a directory',
                'Only in d1: only1', 'Only in d1: only1dir', 'Only in d2: only2', 'Only in d2: only2dir',
                'Common subdirectories: d1/sub and d2/sub')
            $r.ExitCode | Should -Be 1
        }

        It 'descends with -r / --recursive and repeats the options' {
            (Invoke-TestGnu diff '-r', 'd1', 'd2' -WorkingDirectory $dir).Output | Should -Contain 'diff -r d1/sub/f d2/sub/f'
            (Invoke-TestGnu diff '--recursive', '-u', 'd1', 'd2' -WorkingDirectory $dir).Output | Should -Contain 'diff --recursive -u d1/sub/f d2/sub/f'
            (Invoke-TestGnu diff '-rq', 'd1', 'd2' -WorkingDirectory $dir).Output | Should -Contain 'Files d1/sub/f and d2/sub/f differ'
            (Invoke-TestGnu diff '-rs', 'd1', 'd2' -WorkingDirectory $dir).Output | Should -Contain 'Files d1/same and d2/same are identical'
        }

        It 'treats absent files as empty with -N / --new-file and --unidirectional-new-file' {
            $r = Invoke-TestGnu diff '-rN', 'd1', 'd2' -WorkingDirectory $dir
            $r.Output | Should -Contain 'diff -rN d1/only1 d2/only1'
            $r.Output | Should -Contain 'diff -rN d1/only1dir/in d2/only1dir/in'
            $r.Output | Should -Not -Contain 'Only in d2: only2'
            (Invoke-TestGnu diff '-r', '--new-file', 'd1', 'd2' -WorkingDirectory $dir).ExitCode | Should -Be 1
            $r = Invoke-TestGnu diff '-r', '--unidirectional-new-file', 'd1', 'd2' -WorkingDirectory $dir
            $r.Output | Should -Contain 'Only in d1: only1'
            $r.Output | Should -Contain 'diff -r --unidirectional-new-file d1/only2 d2/only2'
            (Invoke-TestGnu diff '-N', 'base', 'nofile' -WorkingDirectory $dir).Output[0] | Should -Be '1,20d0'
            (Invoke-TestGnu diff '-Nu', 'nofile', 'del' -WorkingDirectory $dir).Output[0] | Should -Match '^--- nofile\t1970-01-01'
            (Invoke-TestGnu diff '--unidirectional-new-file', 'nofile', 'base' -WorkingDirectory $dir).ExitCode | Should -Be 1
            (Invoke-TestGnu diff '--unidirectional-new-file', 'base', 'nofile' -WorkingDirectory $dir).ExitCode | Should -Be 2
            (Invoke-TestGnu diff '-N', 'nofile', 'nofile2' -WorkingDirectory $dir).ExitCode | Should -Be 2
        }

        It 'excludes with -x / --exclude and -X / --exclude-from' {
            $r = Invoke-TestGnu diff '-r', '-x', 'only*', 'd1', 'd2' -WorkingDirectory $dir
            $r.Output | Should -Not -Contain 'Only in d1: only1'
            $r.Output | Should -Contain 'diff -r -x ''only*'' d1/chg d2/chg'
            (Invoke-TestGnu diff '-r', '--exclude=sub', 'd1', 'd2' -WorkingDirectory $dir).Output | Should -Not -Contain 'diff -r ''--exclude=sub'' d1/sub/f d2/sub/f'
            $null = New-TestFile -Path (Join-Path $dir 'pats') -Content "*only*`n`n"
            (Invoke-TestGnu diff '-r', '-X', 'pats', 'd1', 'd2' -WorkingDirectory $dir).Output | Should -Not -Contain 'Only in d2: only2'
            (Invoke-TestGnu diff '-r', '--exclude-from=pats', 'd1', 'd2' -WorkingDirectory $dir).Output | Should -Not -Contain 'Only in d1: only1'
        }

        It 'finds the file of the same name in a directory' {
            (Invoke-TestGnu diff 'd1/chg', 'd2' -WorkingDirectory $dir).Output | Should -Be @('1c1', '< a', '---', '> b')
            (Invoke-TestGnu diff 'd1', 'd2/chg' -WorkingDirectory $dir).Output | Should -Be @('1c1', '< a', '---', '> b')
            (Invoke-TestGnu diff 'd1', 'base' -WorkingDirectory $dir).ErrorText | Should -Be 'diff: d1/base: No such file or directory'
        }

        It 'refuses standard input against a directory' {
            foreach ($pair in @(@('-', 'd1'), @('d1', '-'))) {
                $r = Invoke-TestGnu diff $pair -WorkingDirectory $dir
                $r.ErrorText | Should -Be 'diff: cannot compare ''-'' to a directory'
                $r.ExitCode | Should -Be 2
            }
        }
    }

    Context 'errors' {
        It 'takes operands after --' {
            (Invoke-TestGnu diff '--', 'base', 'del' -WorkingDirectory $dir).Output | Should -Be @('5d4', '< e')
        }

        It 'reports <Name>' -ForEach @(
            @{ Name = 'no operands'; Arguments = @(); Message = "diff: missing operand after 'diff'`ndiff: Try 'diff --help' for more information." }
            @{ Name = 'one operand'; Arguments = @('base'); Message = "diff: missing operand after 'base'`ndiff: Try 'diff --help' for more information." }
            @{ Name = 'three operands'; Arguments = @('base', 'two', 'x'); Message = "diff: extra operand 'x'`ndiff: Try 'diff --help' for more information." }
            @{ Name = 'two styles'; Arguments = @('-c', '-u', 'base', 'two'); Message = "diff: conflicting output style options`ndiff: Try 'diff --help' for more information." }
            @{ Name = 'a bad context length'; Arguments = @('-U', 'x', 'base', 'two'); Message = "diff: invalid context length 'x'`ndiff: Try 'diff --help' for more information." }
            @{ Name = 'a bad tab size'; Arguments = @('--tabsize=0', 'base', 'two'); Message = "diff: invalid tabsize '0'`ndiff: Try 'diff --help' for more information." }
            @{ Name = 'a bad horizon'; Arguments = @('--horizon-lines=x', 'base', 'two'); Message = "diff: invalid horizon length 'x'`ndiff: Try 'diff --help' for more information." }
        ) {
            $r = Invoke-TestGnu diff $Arguments -WorkingDirectory $dir
            $r.ErrorText | Should -Be $Message
            $r.ExitCode | Should -Be 2
        }

        It 'reports missing files' {
            $r = Invoke-TestGnu diff 'base', 'nofile' -WorkingDirectory $dir
            $r.ErrorText | Should -Be 'diff: nofile: No such file or directory'
            $r.ExitCode | Should -Be 2
            (Invoke-TestGnu diff 'nofile', 'nofile2' -WorkingDirectory $dir).Errors.Count | Should -Be 2
        }
    }
}

Describe 'diff search' {
    It 'produces a valid edit script for <Name>' -ForEach @(
        @{ Name = 'reordered lines'; Old = @('a', 'b', 'c', 'a', 'b', 'c', 'a', 'b', 'c'); New = @('c', 'b', 'a', 'c', 'b', 'a') }
        @{ Name = 'a shifted repeat'; Old = @('x', 'a', 'b', 'a', 'b', 'y'); New = @('x', 'a', 'b', 'y') }
        @{ Name = 'nothing in common'; Old = @('a', 'b', 'c'); New = @('x', 'y') }
        @{ Name = 'one empty side'; Old = @(); New = @('x', 'y') }
    ) {
        Test-DiffScript -Old $Old -New $New
        Test-DiffScript -Old $Old -New $New -Minimal
    }

    It 'stays valid on repetitive files' -ForEach @(1, 2, 3, 4, 5, 6) {
        # Lines that repeat far more often than the discard threshold reach the provisional runs of GNU's heuristic.
        $random = New-Object System.Random -ArgumentList $_
        $words = @('common', 'common', 'common', 'other', 'blue', 'green')
        $old = [string[]]@(for ($i = 0; $i -lt 400; $i++) { if ($random.Next(5) -eq 0) { "only-old-$i" } else { $words[$random.Next($words.Count)] } })
        $new = [string[]]@(for ($i = 0; $i -lt 400; $i++) { if ($random.Next(5) -eq 0) { "only-new-$i" } else { $words[$random.Next($words.Count)] } })
        Test-DiffScript -Old $old -New $new
    }

    It 'stays valid on short sequences of few different lines' {
        # Every tie between equally short scripts is resolved somewhere, including the boundary shifting.
        foreach ($seed in 1..150) {
            $random = New-Object System.Random -ArgumentList $seed
            $old = [string[]]@(for ($i = 0; $i -lt 24; $i++) { [string][char](97 + $random.Next(3)) })
            $new = [string[]]@(for ($i = 0; $i -lt 22; $i++) { [string][char](97 + $random.Next(3)) })
            Test-DiffScript -Old $old -New $new
        }
    }

    It 'handles a run of discards with provisional lines' {
        # Non-matching lines around lines that match too often: the cases of GNU's discard_confusing_lines.
        $head = @('g0', 'P', 'g1', 'P', 'P', 'P', 'g2', 'P', 'g3')
        $middle = @(1..24 | ForEach-Object { "m$_" })
        $foot = @('h3', 'P', 'h2', 'P', 'P', 'P', 'h1', 'P', 'h0')
        Test-DiffScript -Old ([string[]]($head + $middle + $foot)) -New ([string[]]@(1..8 | ForEach-Object { 'P' }))
    }

    It 'keeps long runs of discards valid' {
        $old = [string[]]@(1..30 | ForEach-Object { "gone$_" }) + @(1..40 | ForEach-Object { 'shared' }) + @(1..30 | ForEach-Object { "away$_" })
        $new = [string[]]@(1..50 | ForEach-Object { 'shared' })
        Test-DiffScript -Old $old -New $new
        $mixed = [string[]]@(for ($i = 0; $i -lt 200; $i++) { if ($i % 4 -eq 0) { 'shared' } else { "gone$i" } })
        Test-DiffScript -Old $mixed -New $new
        $dense = [string[]]@(for ($i = 0; $i -lt 300; $i++) { if ($i % 16 -lt 3) { 'shared' } else { "gone$i" } })
        Test-DiffScript -Old $dense -New $new
    }
}
