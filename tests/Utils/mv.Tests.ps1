BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')

    function New-MvSandbox {
        $dir = Join-Path $TestDrive ('mv-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $null = New-TestFile -Path (Join-Path $dir 'a.txt') -Content 'A'
        $null = New-TestFile -Path (Join-Path $dir 'b.txt') -Content 'B'
        $null = New-TestFile -Path (Join-Path $dir 'tree/inner.txt') -Content 'I'
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'dest')
        $dir
    }
    function Get-Text([string]$Path) { [System.IO.File]::ReadAllText($Path) }
}

Describe 'mv' {
    It 'renames files and directories' {
        $dir = New-MvSandbox
        (Invoke-TestGnu mv 'a.txt', 'renamed.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        Get-Text (Join-Path $dir 'renamed.txt') | Should -Be 'A'
        Test-Path -LiteralPath (Join-Path $dir 'a.txt') | Should -BeFalse
        (Invoke-TestGnu mv 'tree', 'moved' -WorkingDirectory $dir).ExitCode | Should -Be 0
        Get-Text (Join-Path $dir 'moved/inner.txt') | Should -Be 'I'
    }

    It 'moves several sources into a directory, also with -t / --target-directory' {
        $dir = New-MvSandbox
        (Invoke-TestGnu mv 'a.txt', 'tree', 'dest' -WorkingDirectory $dir).ExitCode | Should -Be 0
        @(Get-ChildItem -LiteralPath (Join-Path $dir 'dest') | Sort-Object -Property Name).Name | Should -Be @('a.txt', 'tree')
        (Invoke-TestGnu mv '-t', 'dest', 'b.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        $null = New-TestFile -Path (Join-Path $dir 'c.txt') -Content 'C'
        (Invoke-TestGnu mv '--target-directory=dest', 'c.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        @(Get-ChildItem -LiteralPath (Join-Path $dir 'dest')).Count | Should -Be 4
    }

    It 'overwrites by default and with -f / --force' {
        $dir = New-MvSandbox
        (Get-Item -LiteralPath (Join-Path $dir 'b.txt')).IsReadOnly = $true
        (Invoke-TestGnu mv 'a.txt', 'b.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        Get-Text (Join-Path $dir 'b.txt') | Should -Be 'A'
        $null = New-TestFile -Path (Join-Path $dir 'c.txt') -Content 'C'
        (Invoke-TestGnu mv '-f', 'c.txt', 'b.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        $null = New-TestFile -Path (Join-Path $dir 'd.txt') -Content 'D'
        (Invoke-TestGnu mv '--force', 'd.txt', 'b.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        Get-Text (Join-Path $dir 'b.txt') | Should -Be 'D'
    }

    It 'keeps existing files with -n / --no-clobber and asks with -i / --interactive' {
        $dir = New-MvSandbox
        (Invoke-TestGnu mv '-n', 'a.txt', 'b.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu mv '--no-clobber', 'a.txt', 'b.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        Get-Text (Join-Path $dir 'b.txt') | Should -Be 'B'
        $r = Use-TestConsoleInput -Text "n`n" -Script { Invoke-TestGnu mv '-i', 'a.txt', 'b.txt' -WorkingDirectory $dir }
        $r.ConsoleError | Should -Match "mv: overwrite 'b.txt'\? "
        Get-Text (Join-Path $dir 'b.txt') | Should -Be 'B'
        $null = Use-TestConsoleInput -Text "y`n" -Script { Invoke-TestGnu mv '--interactive', 'a.txt', 'b.txt' -WorkingDirectory $dir }
        Get-Text (Join-Path $dir 'b.txt') | Should -Be 'A'
        $null = New-TestFile -Path (Join-Path $dir 'e.txt') -Content 'E'
        (Invoke-TestGnu mv '-i', '-f', 'e.txt', 'b.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        Get-Text (Join-Path $dir 'b.txt') | Should -Be 'E'
    }

    It 'only replaces older files with -u / --update' {
        $dir = New-MvSandbox
        (Get-Item -LiteralPath (Join-Path $dir 'a.txt')).LastWriteTime = [datetime]'2000-01-01'
        (Invoke-TestGnu mv '-u', 'a.txt', 'b.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        Get-Text (Join-Path $dir 'b.txt') | Should -Be 'B'
        (Get-Item -LiteralPath (Join-Path $dir 'b.txt')).LastWriteTime = [datetime]'1999-01-01'
        (Invoke-TestGnu mv '--update', 'a.txt', 'b.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        Get-Text (Join-Path $dir 'b.txt') | Should -Be 'A'
    }

    It 'explains with -v / --verbose' {
        $dir = New-MvSandbox
        (Invoke-TestGnu mv '-v', 'a.txt', 'x.txt' -WorkingDirectory $dir).Output | Should -Be @("renamed 'a.txt' -> 'x.txt'")
        (Invoke-TestGnu mv '--verbose', 'x.txt', 'dest' -WorkingDirectory $dir).Output | Should -Be @("renamed 'x.txt' -> 'dest/x.txt'")
    }

    It 'treats DEST as a file with -T / --no-target-directory and strips slashes with --strip-trailing-slashes' {
        $dir = New-MvSandbox
        (Invoke-TestGnu mv '-T', 'tree', 'dest' -WorkingDirectory $dir).ExitCode | Should -Be 0
        Get-Text (Join-Path $dir 'dest/inner.txt') | Should -Be 'I'
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'full')
        $null = New-TestFile -Path (Join-Path $dir 'full/x') -Content 'x'
        (Invoke-TestGnu mv '--no-target-directory', 'dest', 'full' -WorkingDirectory $dir).ErrorText | Should -Match "cannot move 'dest' to 'full': Directory not empty"
        $r = Invoke-TestGnu mv '--strip-trailing-slashes', '-v', 'dest/', 'renamed' -WorkingDirectory $dir
        $r.Output | Should -Be @("renamed 'dest' -> 'renamed'")
    }

    It 'replaces links to directories and moves links themselves' {
        $dir = New-MvSandbox
        if (-not (New-TestDirectoryLink -Path (Join-Path $dir 'link') -Target (Join-Path $dir 'tree'))) { Set-ItResult -Skipped -Because 'directory links cannot be created here' }
        (Invoke-TestGnu mv 'link', 'link2' -WorkingDirectory $dir).ExitCode | Should -Be 0
        Test-Path -LiteralPath (Join-Path $dir 'tree/inner.txt') | Should -BeTrue
        Get-Text (Join-Path $dir 'link2/inner.txt') | Should -Be 'I'
        $null = New-TestDirectoryLink -Path (Join-Path $dir 'link3') -Target (Join-Path $dir 'tree')
        (Invoke-TestGnu mv '-T', 'link2', 'link3' -WorkingDirectory $dir).ExitCode | Should -Be 0
        Test-Path -LiteralPath (Join-Path $dir 'tree/inner.txt') | Should -BeTrue
    }

    It 'copies and deletes directories across drives (simulated)' {
        $dir = New-MvSandbox
        $null = New-TestFile -Path (Join-Path $dir 'tree/deep/x.txt') -Content 'X'
        $null = New-TestFile -Path (Join-Path $dir 'tree/ro.txt') -Content 'R'
        (Get-Item -LiteralPath (Join-Path $dir 'tree/ro.txt')).IsReadOnly = $true
        $hasLink = New-TestDirectoryLink -Path (Join-Path $dir 'tree/link') -Target (Join-Path $dir 'dest')
        Push-Location -LiteralPath $dir
        try {
            $errors = InModuleScope PSGnuUtils {
                Mock Test-GnuSameVolume { $false }
                Invoke-GnuMv tree elsewhere 2>&1
            }
        }
        finally { Pop-Location }
        "$errors" | Should -BeNullOrEmpty
        if ($hasLink) { (Get-Item -LiteralPath (Join-Path $dir 'elsewhere/link') -Force).LinkType | Should -BeIn @('Junction', 'SymbolicLink') }
        Test-Path -LiteralPath (Join-Path $dir 'tree') | Should -BeFalse
        Get-Text (Join-Path $dir 'elsewhere/deep/x.txt') | Should -Be 'X'
        Test-Path -LiteralPath (Join-Path $dir 'dest') | Should -BeTrue
    }

    It 'reports errors' {
        $dir = New-MvSandbox
        (Invoke-TestGnu mv 'missing', 'x' -WorkingDirectory $dir).ErrorText | Should -BeExactly "mv: cannot stat 'missing': No such file or directory"
        (Invoke-TestGnu mv 'a.txt', 'a.txt' -WorkingDirectory $dir).ErrorText | Should -Match "'a.txt' and 'a.txt' are the same file"
        (Invoke-TestGnu mv 'tree', 'tree/sub' -WorkingDirectory $dir).ErrorText | Should -Match "cannot move 'tree' to a subdirectory of itself, 'tree/sub'"
        (Invoke-TestGnu mv '-T', 'tree', 'a.txt' -WorkingDirectory $dir).ErrorText | Should -Match "cannot overwrite non-directory 'a.txt' with directory 'tree'"
        (Invoke-TestGnu mv '-T', 'a.txt', 'dest' -WorkingDirectory $dir).ErrorText | Should -Match "cannot overwrite directory 'dest' with non-directory"
        (Invoke-TestGnu mv 'a.txt' -WorkingDirectory $dir).ErrorText | Should -Match "missing destination file operand after 'a.txt'"
        $r = Invoke-TestGnu mv 'a.txt', 'no/dir/x' -WorkingDirectory $dir
        $r.ErrorText | Should -Match "cannot move 'a.txt' to 'no/dir/x'"
        $r.ExitCode | Should -Be 1
    }

    It 'recreates symbolic links when copying across drives (mocked)' {
        $dir = New-MvSandbox
        Push-Location -LiteralPath $dir
        try {
            $made = InModuleScope PSGnuUtils {
                Mock Test-GnuSameVolume { $false }
                Mock Get-GnuLinkTarget { 'b.txt' } -ParameterFilter { $Path -like '*inner.txt' }
                Mock Get-GnuLinkTarget { }
                Mock New-GnuSymbolicLink { "symlink:$Target" }
                Mock Remove-GnuTree { }
                Invoke-GnuMv tree elsewhere
            }
        }
        finally { Pop-Location }
        $made | Should -Be 'symlink:b.txt'
    }

    It 'reports destinations that cannot be removed' {
        $dir = New-MvSandbox
        $lock = Block-TestFileRemoval -Path (Join-Path $dir 'b.txt')
        try { (Invoke-TestGnu mv 'a.txt', 'b.txt' -WorkingDirectory $dir).ErrorText | Should -Match "cannot remove 'b.txt'" }
        finally { $lock.Dispose() }
    }

    It 'removes trees with file links and read-only files' {
        $dir = New-MvSandbox
        $null = New-TestFile -Path (Join-Path $dir 'tree/fake-link') -Content 'x'
        InModuleScope PSGnuUtils -Parameters @{ T = (Join-Path $dir 'tree') } {
            param($T)
            Mock Get-GnuLinkTarget { 'target' } -ParameterFilter { $Path -like '*fake-link' }
            Mock Get-GnuLinkTarget { }
            Remove-GnuTree -Path $T
        }
        Test-Path -LiteralPath (Join-Path $dir 'tree') | Should -BeFalse
    }

    It 'strips trailing separators but keeps a lone root' {
        InModuleScope PSGnuUtils {
            Remove-GnuTrailingSeparator -Path 'dir//' | Should -Be 'dir'
            Remove-GnuTrailingSeparator -Path '//' | Should -Be '/'
            Remove-GnuTrailingSeparator -Path '' | Should -Be ''
        }
    }
}
