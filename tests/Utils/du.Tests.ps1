BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# Expected values follow GNU coreutils du; disk usage is estimated with 4 KiB clusters.
Describe 'du' {
    BeforeAll {
        $script:dir = Join-Path $TestDrive 'du'
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'a/b') -Force
        $null = New-TestFile -Path (Join-Path $dir 'a/f1') -Bytes (New-Object byte[] 5000)
        $null = New-TestFile -Path (Join-Path $dir 'a/b/f2') -Bytes (New-Object byte[] 10)
        $null = New-TestFile -Path (Join-Path $dir 'a/e') -Content ''
        # Directories themselves: 0 on Windows, 4 KiB elsewhere.
        $script:d = 0
        if (-not (Test-IsWindowsPlatform)) { $script:d = 4096 }
        $script:k = [int]($d / 1024)
    }

    It 'prints the usage of every directory in 1K blocks' {
        $r = Invoke-TestGnu du 'a' -WorkingDirectory $dir
        $r.Output | Should -Be @("$(4 + $k)`ta/b", "$(12 + 2 * $k)`ta")
        $r.ExitCode | Should -Be 0
    }

    It 'includes files with -a / --all' {
        (Invoke-TestGnu du '-a', 'a' -WorkingDirectory $dir).Output | Should -Be @("4`ta/b/f2", "$(4 + $k)`ta/b", "0`ta/e", "8`ta/f1", "$(12 + 2 * $k)`ta")
        (Invoke-TestGnu du '--all', 'a/f1' -WorkingDirectory $dir).Output | Should -Be @("8`ta/f1")
    }

    It 'summarizes with -s / --summarize and -d / --max-depth' {
        (Invoke-TestGnu du '-s', 'a' -WorkingDirectory $dir).Output | Should -Be @("$(12 + 2 * $k)`ta")
        (Invoke-TestGnu du '--summarize', 'a' -WorkingDirectory $dir).Output.Count | Should -Be 1
        (Invoke-TestGnu du '-d', '0', 'a' -WorkingDirectory $dir).Output.Count | Should -Be 1
        (Invoke-TestGnu du '--max-depth=1', '-a', 'a' -WorkingDirectory $dir).Output | Should -Be @("$(4 + $k)`ta/b", "0`ta/e", "8`ta/f1", "$(12 + 2 * $k)`ta")
        $r = Invoke-TestGnu du '-s', '-d', '1', 'a' -WorkingDirectory $dir
        $r.ErrorText | Should -Match 'du: warning: summarizing conflicts with --max-depth=1'
        $r.ExitCode | Should -Be 1
        $r = Invoke-TestGnu du '-s', '-d', '0', 'a' -WorkingDirectory $dir
        $r.WarningText | Should -Match 'summarizing is the same as using --max-depth=0'
        $r.Output.Count | Should -Be 1
        (Invoke-TestGnu du '-d', '99999999999999999999999', 'a' -WorkingDirectory $dir).ErrorText | Should -Match "invalid maximum depth '9+'"
        (Invoke-TestGnu du '-d', 'x', 'a' -WorkingDirectory $dir).ErrorText | Should -Match "invalid maximum depth 'x'"
        (Invoke-TestGnu du '-a', '-s', 'a' -WorkingDirectory $dir).ErrorText | Should -Match 'cannot both summarize and show all entries'
    }

    It 'counts bytes with -b / --bytes and --apparent-size' {
        (Invoke-TestGnu du '-b', 'a' -WorkingDirectory $dir).Output | Should -Be @("10`ta/b", "5010`ta")
        (Invoke-TestGnu du '--bytes', 'a/f1' -WorkingDirectory $dir).Output | Should -Be @("5000`ta/f1")
        (Invoke-TestGnu du '--apparent-size', 'a/f1', 'a/b/f2' -WorkingDirectory $dir).Output | Should -Be @("5`ta/f1", "1`ta/b/f2")
    }

    It 'prints human readable sizes with -h / --human-readable and --si' {
        (Invoke-TestGnu du '-h', 'a/f1' -WorkingDirectory $dir).Output | Should -Be @("8.0K`ta/f1")
        (Invoke-TestGnu du '--human-readable', '-b', 'a/b/f2' -WorkingDirectory $dir).Output | Should -Be @("10`ta/b/f2")
        (Invoke-TestGnu du '-b', '--si', 'a/f1' -WorkingDirectory $dir).Output | Should -Be @("5.0k`ta/f1")
        (Invoke-TestGnu du '--si', '-b', 'a/f1' -WorkingDirectory $dir).Output | Should -Be @("5000`ta/f1") -Because 'the last size option wins'
    }

    It 'scales with -B / --block-size, -k and -m' {
        (Invoke-TestGnu du '-B', '2K', 'a/f1' -WorkingDirectory $dir).Output | Should -Be @("4`ta/f1")
        (Invoke-TestGnu du '--block-size=1', 'a/f1' -WorkingDirectory $dir).Output | Should -Be @("8192`ta/f1")
        (Invoke-TestGnu du '-k', 'a/f1' -WorkingDirectory $dir).Output | Should -Be @("8`ta/f1")
        (Invoke-TestGnu du '-m', 'a/f1' -WorkingDirectory $dir).Output | Should -Be @("1`ta/f1")
        (Invoke-TestGnu du '-BK', 'a/f1' -WorkingDirectory $dir).Output | Should -Be @("8K`ta/f1") -Because 'a size without digits prints its unit'
        (Invoke-TestGnu du '-BMB', 'a/f1' -WorkingDirectory $dir).Output | Should -Be @("1MB`ta/f1")
        (Invoke-TestGnu du '-B', 'x', 'a' -WorkingDirectory $dir).ErrorText | Should -Match "invalid -B argument 'x'"
        (Invoke-TestGnu du '--block-size=x', 'a' -WorkingDirectory $dir).ErrorText | Should -Match "invalid --block-size argument 'x'"
        (Invoke-TestGnu du '-B', '5b', 'a' -WorkingDirectory $dir).ErrorText | Should -Match "invalid suffix in -B argument '5b'"
        (Invoke-TestGnu du '-B', '99999999999999999999999', 'a' -WorkingDirectory $dir).ErrorText | Should -Match "-B argument '9+' too large"
    }

    It 'rounds human readable sizes up across unit boundaries' -ForEach @(
        @{ Size = 10239; Option = '-h'; Expected = '10K' },
        @{ Size = 1048575; Option = '-h'; Expected = '1.0M' },
        @{ Size = 999999; Option = '--si'; Expected = '1.0M' }
    ) {
        $file = New-TestFile -Path (Join-Path $TestDrive "size$Size") -Bytes (New-Object byte[] $Size)
        (Invoke-TestGnu du '--apparent-size', $Option, $file).Output | Should -Be @("$Expected`t$file")
    }

    It 'rejects a block size of zero' {
        (Invoke-TestGnu du '-B', '0', 'a' -WorkingDirectory $dir).ErrorText | Should -Match "invalid -B argument '0'"
    }

    It 'adds a total with -c / --total' {
        (Invoke-TestGnu du '-c', 'a/f1', 'a/b' -WorkingDirectory $dir).Output | Should -Be @("8`ta/f1", "$(4 + $k)`ta/b", "$(12 + $k)`ttotal")
        (Invoke-TestGnu du '--total', 'a/f1' -WorkingDirectory $dir).Output[-1] | Should -Be "8`ttotal"
    }

    It 'leaves out subdirectories with -S / --separate-dirs' {
        (Invoke-TestGnu du '-S', 'a' -WorkingDirectory $dir).Output | Should -Be @("$(4 + $k)`ta/b", "$(8 + $k)`ta")
        (Invoke-TestGnu du '--separate-dirs', 'a' -WorkingDirectory $dir).Output.Count | Should -Be 2
    }

    It 'filters with -t / --threshold, --exclude and -X / --exclude-from' {
        (Invoke-TestGnu du '-t', '9K', 'a' -WorkingDirectory $dir).Output | Should -Be @("$(12 + 2 * $k)`ta")
        (Invoke-TestGnu du '-a', '-b', '--threshold=-100', 'a' -WorkingDirectory $dir).Output | Should -Be @("10`ta/b/f2", "10`ta/b", "0`ta/e") -Because 'negative thresholds hide larger entries'
        (Invoke-TestGnu du '-t', 'x', 'a' -WorkingDirectory $dir).ErrorText | Should -Match "invalid -t argument 'x'"
        (Invoke-TestGnu du '--threshold=x', 'a' -WorkingDirectory $dir).ErrorText | Should -Match "invalid --threshold argument 'x'"
        (Invoke-TestGnu du '--threshold=-0', 'a' -WorkingDirectory $dir).ErrorText | Should -Match "invalid --threshold argument '-0'"
        (Invoke-TestGnu du '-t', '0', 'a/e' -WorkingDirectory $dir).Output | Should -Be @("0`ta/e")
        (Invoke-TestGnu du '--exclude=f*', '-a', 'a' -WorkingDirectory $dir).Output | Should -Be @("$k`ta/b", "0`ta/e", "$(2 * $k)`ta")
        $list = New-TestFile -Path (Join-Path $TestDrive 'excludes') -Content "f1`n`nb`n"
        (Invoke-TestGnu du '-X', $list, '-a', 'a' -WorkingDirectory $dir).Output | Should -Be @("0`ta/e", "$k`ta")
        (Invoke-TestGnu du "--exclude-from=$list", 'a' -WorkingDirectory $dir).Output | Should -Be @("$k`ta")
    }

    It 'ends records with NUL with -0 / --null' {
        (Invoke-TestGnu du '-0', 'a/f1' -WorkingDirectory $dir).Output | Should -Be @("8`ta/f1`0")
        (Invoke-TestGnu du '--null', 'a/f1' -WorkingDirectory $dir).Output | Should -Be @("8`ta/f1`0")
    }

    It 'does not follow links unless -L / --dereference; -x / --one-file-system skips them' {
        $link = Join-Path $dir 'link'
        if (-not (New-TestDirectoryLink -Path $link -Target (Join-Path $dir 'a'))) { Set-ItResult -Skipped -Because 'links cannot be created here'; return }
        try {
            (Invoke-TestGnu du '-s', 'link' -WorkingDirectory $dir).Output | Should -Be @("0`tlink")
            (Invoke-TestGnu du '-P', '-s', 'link' -WorkingDirectory $dir).Output | Should -Be @("0`tlink")
            (Invoke-TestGnu du '--no-dereference', '-s', 'link' -WorkingDirectory $dir).Output | Should -Be @("0`tlink")
            (Invoke-TestGnu du '-L', '-s', 'link' -WorkingDirectory $dir).Output | Should -Be @("$(12 + 2 * $k)`tlink")
            (Invoke-TestGnu du '--dereference', '-s', 'link' -WorkingDirectory $dir).Output | Should -Be @("$(12 + 2 * $k)`tlink")
            (Invoke-TestGnu du '-x', '-a', '.' -WorkingDirectory $dir).Output | Should -Not -Contain "0`t./link"
            (Invoke-TestGnu du '--one-file-system', '-a', '.' -WorkingDirectory $dir).Output | Should -Contain "8`t./a/f1"
        }
        # Remove-Item fails on directory links in Windows PowerShell 5.1.
        finally { [System.IO.Directory]::Delete($link) }
    }

    It 'reports errors and reads the current directory by default' {
        $r = Invoke-TestGnu du 'nosuch', 'a/f1' -WorkingDirectory $dir
        $r.ErrorText | Should -Be "du: cannot access 'nosuch': No such file or directory"
        $r.Output | Should -Be @("8`ta/f1")
        $r.ExitCode | Should -Be 1
        (Invoke-TestGnu du -WorkingDirectory (Join-Path $dir 'a/b')).Output | Should -Be @("$(4 + $k)`t.")
    }

    It 'counts directories as 4 KiB off Windows and links as 0' {
        InModuleScope PSGnuUtils -Parameters @{ Dir = $dir } {
            param($Dir)
            Mock Test-GnuWindows { $false }
            Get-GnuDuSize -Item (Get-Item -LiteralPath (Join-Path $Dir 'a')) -Apparent $false | Should -Be 4096
        }
        InModuleScope PSGnuUtils -Parameters @{ Dir = $dir } {
            param($Dir)
            Mock Get-GnuLinkTarget { 'target' }
            Get-GnuDuSize -Item (Get-Item -LiteralPath (Join-Path $Dir 'a/f1')) -Apparent $true | Should -Be 6 -Because 'the apparent size of a link is the length of its target'
            Get-GnuDuSize -Item (Get-Item -LiteralPath (Join-Path $Dir 'a/f1')) -Apparent $false | Should -Be 0
        }
    }

    It 'ends on a link loop with -L and does not count it' {
        $loop = Join-Path $dir 'a/loop'
        if (-not (New-TestDirectoryLink -Path $loop -Target (Join-Path $dir 'a'))) { Set-ItResult -Skipped -Because 'links cannot be created here'; return }
        try {
            $r = Invoke-TestGnu du '-L', '-s', 'a' -WorkingDirectory $dir
            $r.Output | Should -Be @("$(12 + 2 * $k)`ta")
            $r.ExitCode | Should -Be 0
        }
        finally { [System.IO.Directory]::Delete($loop) }
    }

    It 'reports a link it cannot follow with -L' {
        Mock -ModuleName PSGnuUtils Get-GnuCanonicalPath { @{ Error = 'No such file or directory' } }
        $r = Invoke-TestGnu du '-L', 'a/f1' -WorkingDirectory $dir
        $r.ErrorText | Should -Be "du: cannot access 'a/f1': No such file or directory"
        $r.ExitCode | Should -Be 1
    }

    It 'reports directories it cannot read' {
        Mock -ModuleName PSGnuUtils Get-ChildItem { throw [System.UnauthorizedAccessException]::new('denied') }
        $r = Invoke-TestGnu du 'a' -WorkingDirectory $dir
        $r.ErrorText | Should -Be "du: cannot read directory 'a': Permission denied"
        $r.Output | Should -Be @("$k`ta")
    }
}
