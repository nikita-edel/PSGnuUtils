BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')

    function New-CpSandbox {
        $dir = Join-Path $TestDrive ('cp-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $null = New-TestFile -Path (Join-Path $dir 'a.txt') -Content 'A'
        $null = New-TestFile -Path (Join-Path $dir 'b.txt') -Content 'B'
        $null = New-TestFile -Path (Join-Path $dir 'tree/inner.txt') -Content 'I'
        $null = New-TestFile -Path (Join-Path $dir 'tree/sub/deep.txt') -Content 'D'
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'dest')
        $old = [datetime]'2001-02-03 04:05:06'
        (Get-Item -LiteralPath (Join-Path $dir 'a.txt')).LastWriteTime = $old
        $dir
    }
    function Get-Text([string]$Path) { [System.IO.File]::ReadAllText($Path) }
}

Describe 'cp' {
    It 'copies a file, sets the time to now, keeps the source' {
        $dir = New-CpSandbox
        (Invoke-TestGnu cp 'a.txt', 'copy.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        Get-Text (Join-Path $dir 'copy.txt') | Should -Be 'A'
        (Get-Item -LiteralPath (Join-Path $dir 'copy.txt')).LastWriteTime | Should -BeGreaterThan ([datetime]::Now.AddMinutes(-1))
        Test-Path -LiteralPath (Join-Path $dir 'a.txt') | Should -BeTrue
    }

    It 'copies into a directory and with -t / --target-directory' {
        $dir = New-CpSandbox
        (Invoke-TestGnu cp 'a.txt', 'b.txt', 'dest' -WorkingDirectory $dir).ExitCode | Should -Be 0
        @(Get-ChildItem -LiteralPath (Join-Path $dir 'dest')).Name | Should -Be @('a.txt', 'b.txt')
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'd2')
        $null = Invoke-TestGnu cp '-t', 'd2', 'a.txt' -WorkingDirectory $dir
        $null = Invoke-TestGnu cp '--target-directory=d2', 'b.txt' -WorkingDirectory $dir
        @(Get-ChildItem -LiteralPath (Join-Path $dir 'd2')).Count | Should -Be 2
    }

    It 'needs -r / -R / --recursive for directories' {
        $dir = New-CpSandbox
        (Invoke-TestGnu cp 'tree', 'copy' -WorkingDirectory $dir).ErrorText | Should -BeExactly "cp: -r not specified; omitting directory 'tree'"
        foreach ($option in @('-r', '-R', '--recursive')) {
            $target = 'copy' + $option.Replace('-', '')
            (Invoke-TestGnu cp $option, 'tree', $target -WorkingDirectory $dir).ExitCode | Should -Be 0
            Get-Text (Join-Path $dir "$target/sub/deep.txt") | Should -Be 'D'
        }
        (Invoke-TestGnu cp '-r', 'tree', 'dest' -WorkingDirectory $dir).ExitCode | Should -Be 0
        Get-Text (Join-Path $dir 'dest/tree/inner.txt') | Should -Be 'I'
        (Invoke-TestGnu cp '-r', 'tree', 'dest' -WorkingDirectory $dir).ExitCode | Should -Be 0
    }

    It 'explains with -v / --verbose' {
        $dir = New-CpSandbox
        (Invoke-TestGnu cp '-v', 'a.txt', 'v.txt' -WorkingDirectory $dir).Output | Should -Be @("'a.txt' -> 'v.txt'")
        (Invoke-TestGnu cp '--verbose', '-r', 'tree', 'vt' -WorkingDirectory $dir).Output | Should -Be @("'tree' -> 'vt'", "'tree/inner.txt' -> 'vt/inner.txt'", "'tree/sub' -> 'vt/sub'", "'tree/sub/deep.txt' -> 'vt/sub/deep.txt'")
    }

    It 'preserves timestamps and attributes with -p, --preserve and -a / --archive' {
        $dir = New-CpSandbox
        $old = (Get-Item -LiteralPath (Join-Path $dir 'a.txt')).LastWriteTime
        $null = Invoke-TestGnu cp '-p', 'a.txt', 'p1' -WorkingDirectory $dir
        (Get-Item -LiteralPath (Join-Path $dir 'p1')).LastWriteTime | Should -Be $old
        $null = Invoke-TestGnu cp '--preserve', 'a.txt', 'p2' -WorkingDirectory $dir
        (Get-Item -LiteralPath (Join-Path $dir 'p2')).LastWriteTime | Should -Be $old
        $null = Invoke-TestGnu cp '--preserve=timestamps', 'a.txt', 'p3' -WorkingDirectory $dir
        (Get-Item -LiteralPath (Join-Path $dir 'p3')).LastWriteTime | Should -Be $old
        $null = Invoke-TestGnu cp '-p', '--no-preserve=timestamps', 'a.txt', 'p4' -WorkingDirectory $dir
        (Get-Item -LiteralPath (Join-Path $dir 'p4')).LastWriteTime | Should -BeGreaterThan $old
        (Get-Item -LiteralPath (Join-Path $dir 'tree')).LastWriteTime = $old
        $null = Invoke-TestGnu cp '-a', 'tree', 'arch' -WorkingDirectory $dir
        (Get-Item -LiteralPath (Join-Path $dir 'arch')).LastWriteTime | Should -Be $old
        $null = Invoke-TestGnu cp '--archive', 'tree', 'arch2' -WorkingDirectory $dir
        Get-Text (Join-Path $dir 'arch2/sub/deep.txt') | Should -Be 'D'
        (Invoke-TestGnu cp '--preserve=colors', 'a.txt', 'p5' -WorkingDirectory $dir).ErrorText | Should -Match "invalid argument 'colors' for '--preserve'"
    }

    It 'keeps existing files with -n / --no-clobber, asks with -i / --interactive, replaces with -f / --force' {
        $dir = New-CpSandbox
        (Invoke-TestGnu cp '-n', 'a.txt', 'b.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu cp '--no-clobber', 'a.txt', 'b.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        Get-Text (Join-Path $dir 'b.txt') | Should -Be 'B'
        (Use-TestConsoleInput -Text "n`n" -Script { Invoke-TestGnu cp '-i', 'a.txt', 'b.txt' -WorkingDirectory $dir }).ConsoleError | Should -Match "cp: overwrite 'b.txt'\? "
        Get-Text (Join-Path $dir 'b.txt') | Should -Be 'B'
        $null = Use-TestConsoleInput -Text "y`n" -Script { Invoke-TestGnu cp '--interactive', 'a.txt', 'b.txt' -WorkingDirectory $dir }
        Get-Text (Join-Path $dir 'b.txt') | Should -Be 'A'
        $null = New-TestFile -Path (Join-Path $dir 'ro.txt') -Content 'R'
        (Get-Item -LiteralPath (Join-Path $dir 'ro.txt')).IsReadOnly = $true
        (Invoke-TestGnu cp 'b.txt', 'ro.txt' -WorkingDirectory $dir).ErrorText | Should -Match "cannot create regular file 'ro.txt'"
        (Invoke-TestGnu cp '-f', 'b.txt', 'ro.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu cp '--force', 'b.txt', 'ro.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        Get-Text (Join-Path $dir 'ro.txt') | Should -Be 'A'
    }

    It 'only replaces older files with -u / --update' {
        $dir = New-CpSandbox
        (Invoke-TestGnu cp '-u', 'a.txt', 'b.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        Get-Text (Join-Path $dir 'b.txt') | Should -Be 'B'
        (Get-Item -LiteralPath (Join-Path $dir 'b.txt')).LastWriteTime = [datetime]'1999-01-01'
        $null = Invoke-TestGnu cp '--update', 'a.txt', 'b.txt' -WorkingDirectory $dir
        Get-Text (Join-Path $dir 'b.txt') | Should -Be 'A'
    }

    It 'makes hard links with -l / --link and symbolic links with -s / --symbolic-link' {
        $dir = New-CpSandbox
        (Invoke-TestGnu cp '-l', 'a.txt', 'hard' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu cp '--link', 'a.txt', 'b.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        [System.IO.File]::WriteAllText((Join-Path $dir 'a.txt'), 'changed')
        Get-Text (Join-Path $dir 'hard') | Should -Be 'changed'
        Get-Text (Join-Path $dir 'b.txt') | Should -Be 'changed'
        $global:PSGnuLinks = New-Object 'System.Collections.Generic.List[object]'
        Push-Location -LiteralPath $dir
        try {
            InModuleScope PSGnuUtils {
                Mock New-GnuSymbolicLink { $global:PSGnuLinks.Add($Target) }
                Invoke-GnuCp -s a.txt sym
                Invoke-GnuCp --symbolic-link a.txt b.txt
            }
            $global:PSGnuLinks.Count | Should -Be 2
            $global:PSGnuLinks[0] | Should -Be (Join-Path $dir 'a.txt')
        }
        finally {
            Pop-Location
            Remove-Variable -Name PSGnuLinks -Scope Global
        }
    }

    It 'copies links as links when recursive, follows them with -L / --dereference' {
        $dir = New-CpSandbox
        if (-not (New-TestDirectoryLink -Path (Join-Path $dir 'tree/link') -Target (Join-Path $dir 'dest'))) { Set-ItResult -Skipped -Because 'directory links cannot be created here' }
        $null = New-TestFile -Path (Join-Path $dir 'dest/in-dest.txt') -Content 'X'
        (Invoke-TestGnu cp '-r', 'tree', 'c1' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Get-Item -LiteralPath (Join-Path $dir 'c1/link') -Force).LinkType | Should -BeIn @('Junction', 'SymbolicLink')
        $null = New-TestDirectoryLink -Path (Join-Path $dir 'c1/link-again') -Target (Join-Path $dir 'dest')
        (Invoke-TestGnu cp '-r', '-P', 'tree', 'c1' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu cp '-n', '-r', 'tree', 'c1' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu cp '-rL', 'tree', 'c2' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu cp '-r', '--dereference', 'tree', 'c3' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Get-Item -LiteralPath (Join-Path $dir 'c2/link') -Force).LinkType | Should -BeNullOrEmpty
        Get-Text (Join-Path $dir 'c2/link/in-dest.txt') | Should -Be 'X'
        (Invoke-TestGnu cp '--no-dereference', '-r', 'tree', 'c4' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu cp '-d', '-r', 'tree', 'c5' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Get-Item -LiteralPath (Join-Path $dir 'c5/link') -Force).LinkType | Should -BeIn @('Junction', 'SymbolicLink')
    }

    It 'recreates symbolic links (mocked)' {
        $dir = New-CpSandbox
        Push-Location -LiteralPath $dir
        try {
            $created = InModuleScope PSGnuUtils {
                Mock Get-GnuLinkTarget { 'b.txt' } -ParameterFilter { $Path -like '*a.txt' }
                Mock Get-GnuLinkTarget { }
                Mock New-GnuSymbolicLink { "link:$Target" }
                Invoke-GnuCp -P a.txt l
            }
            $created | Should -Be 'link:b.txt'
        }
        finally { Pop-Location }
    }

    It 'treats DEST as a file with -T / --no-target-directory' {
        $dir = New-CpSandbox
        (Invoke-TestGnu cp '-T', 'a.txt', 'dest' -WorkingDirectory $dir).ErrorText | Should -Match "cannot overwrite directory 'dest' with non-directory"
        (Invoke-TestGnu cp '--no-target-directory', '-r', 'tree', 'dest' -WorkingDirectory $dir).ExitCode | Should -Be 0
        Get-Text (Join-Path $dir 'dest/inner.txt') | Should -Be 'I'
        (Invoke-TestGnu cp '-T', '-r', 'tree', 'a.txt' -WorkingDirectory $dir).ErrorText | Should -Match "cannot overwrite non-directory 'a.txt' with directory 'tree'"
    }

    It 'reports errors' {
        $dir = New-CpSandbox
        (Invoke-TestGnu cp 'missing', 'x' -WorkingDirectory $dir).ErrorText | Should -BeExactly "cp: cannot stat 'missing': No such file or directory"
        (Invoke-TestGnu cp 'a.txt', 'a.txt' -WorkingDirectory $dir).ErrorText | Should -Match "'a.txt' and 'a.txt' are the same file"
        (Invoke-TestGnu cp '-r', 'tree', 'tree/sub/copy' -WorkingDirectory $dir).ErrorText | Should -Match "cannot copy a directory, 'tree', into itself, 'tree/sub/copy'"
        (Invoke-TestGnu cp 'a.txt' -WorkingDirectory $dir).ErrorText | Should -Match "missing destination file operand after 'a.txt'"
        (Invoke-TestGnu cp 'a.txt', 'no/dir/x' -WorkingDirectory $dir).ErrorText | Should -Match "cannot create regular file 'no/dir/x'"
    }

    It 'refuses to copy a directory onto itself' {
        $dir = New-CpSandbox
        (Invoke-TestGnu cp '-rT', 'tree', 'tree' -WorkingDirectory $dir).ErrorText | Should -Match "cannot copy a directory, 'tree', into itself, 'tree'"
    }

    It 'replaces existing links and reports copied links with -v' {
        $dir = New-CpSandbox
        if (-not (New-TestDirectoryLink -Path (Join-Path $dir 'tree/link') -Target (Join-Path $dir 'dest'))) { Set-ItResult -Skipped -Because 'directory links cannot be created here' }
        $null = Invoke-TestGnu cp '-r', 'tree', 'c1' -WorkingDirectory $dir
        $r = Invoke-TestGnu cp '-rTv', 'tree', 'c1' -WorkingDirectory $dir
        $r.ExitCode | Should -Be 0
        $r.Output | Should -Contain "'tree/link' -> 'c1/link'"
        Push-Location -LiteralPath $dir
        try {
            InModuleScope PSGnuUtils {
                # A file link (needs symlink rights for real): replace an existing file with it.
                Mock Get-GnuLinkTarget { 'b.txt' } -ParameterFilter { $Path -like '*a.txt' }
                Mock Get-GnuLinkTarget { }
                Mock New-GnuSymbolicLink { }
                Invoke-GnuCp -P a.txt b.txt
            }
        }
        finally { Pop-Location }
        Test-Path -LiteralPath (Join-Path $dir 'b.txt') | Should -BeFalse
    }
}
