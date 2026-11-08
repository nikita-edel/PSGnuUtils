BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# Messages follow GNU coreutils install.
Describe 'install' {
    BeforeEach {
        $script:dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $null = New-Item -ItemType Directory -Path $dir
        $null = New-TestFile -Path (Join-Path $dir 'src') -Content 'data'
    }

    It 'copies SOURCE to DEST, verbosely with -v / --verbose' {
        $r = Invoke-TestGnu install '-v', 'src', 'dst' -WorkingDirectory $dir
        $r.Output | Should -Be @("'src' -> 'dst'")
        [System.IO.File]::ReadAllText((Join-Path $dir 'dst')) | Should -Be 'data'
        (Invoke-TestGnu install '--verbose', '-c', 'src', 'dst' -WorkingDirectory $dir).Output | Should -Be @("'src' -> 'dst'")
        (Invoke-TestGnu install 'src', 'quiet' -WorkingDirectory $dir).Output | Should -BeNullOrEmpty
    }

    It 'copies into a directory and with -t / --target-directory' {
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'bin')
        $null = New-TestFile -Path (Join-Path $dir 'two') -Content '2'
        (Invoke-TestGnu install '-v', 'src', 'two', 'bin' -WorkingDirectory $dir).Output | Should -Be @("'src' -> 'bin/src'", "'two' -> 'bin/two'")
        (Invoke-TestGnu install '-v', '-t', 'bin', 'src' -WorkingDirectory $dir).Output | Should -Be @("'src' -> 'bin/src'")
        (Invoke-TestGnu install '-v', '--target-directory=bin', 'two' -WorkingDirectory $dir).Output | Should -Be @("'two' -> 'bin/two'")
    }

    It 'creates directories with -d / --directory' {
        $r = Invoke-TestGnu install '-v', '-d', 'd1/d2', 'd3' -WorkingDirectory $dir
        $r.Warnings | Should -Be @("install: creating directory 'd1'", "install: creating directory 'd1/d2'", "install: creating directory 'd3'")
        Test-Path -LiteralPath (Join-Path $dir 'd1/d2') -PathType Container | Should -BeTrue
        (Invoke-TestGnu install '--directory', '-m', '700', 'd1/d2' -WorkingDirectory $dir).Warnings | Should -BeNullOrEmpty
        (Invoke-TestGnu install '-d', '-m', '700', 'fresh' -WorkingDirectory $dir).ExitCode | Should -Be 0
    }

    It 'creates leading directories with -D' {
        $r = Invoke-TestGnu install '-v', '-D', 'src', 'deep/a/file' -WorkingDirectory $dir
        $r.Warnings | Should -Be @("install: creating directory 'deep'", "install: creating directory 'deep/a'")
        $r.Output | Should -Be @("'src' -> 'deep/a/file'")
        (Invoke-TestGnu install '-D', '-t', 'other/sub', 'src' -WorkingDirectory $dir).ExitCode | Should -Be 0
        Test-Path -LiteralPath (Join-Path $dir 'other/sub/src') | Should -BeTrue
    }

    It 'treats DEST as a file with -T / --no-target-directory' {
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'd1')
        (Invoke-TestGnu install '-T', 'src', 'd1' -WorkingDirectory $dir).ErrorText | Should -Match "cannot overwrite directory 'd1' with non-directory"
        (Invoke-TestGnu install '--no-target-directory', 'src', 'file' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu install '-T', 'src', 'file', 'x' -WorkingDirectory $dir).ErrorText | Should -Match "extra operand 'x'"
        (Invoke-TestGnu install '-T', '-t', 'd1', 'src' -WorkingDirectory $dir).ErrorText | Should -Match 'cannot combine --target-directory'
    }

    It 'skips identical files with -C / --compare and keeps timestamps with -p / --preserve-timestamps' {
        $source = Join-Path $dir 'src'
        [System.IO.File]::SetLastWriteTimeUtc($source, [datetime]::new(2001, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc))
        $null = Invoke-TestGnu install '-p', 'src', 'dst' -WorkingDirectory $dir
        [System.IO.File]::GetLastWriteTimeUtc((Join-Path $dir 'dst')).Year | Should -Be 2001
        (Invoke-TestGnu install '-C', '-v', 'src', 'dst' -WorkingDirectory $dir).Output | Should -BeNullOrEmpty
        [System.IO.File]::WriteAllText((Join-Path $dir 'dst'), 'datx')
        (Invoke-TestGnu install '--compare', '-v', 'src', 'dst' -WorkingDirectory $dir).Output | Should -Be @("'src' -> 'dst'")
        [System.IO.File]::WriteAllText((Join-Path $dir 'dst'), 'longer data')
        (Invoke-TestGnu install '-C', '-v', 'src', 'dst' -WorkingDirectory $dir).Output | Should -Be @("'src' -> 'dst'")
        (Invoke-TestGnu install '--preserve-timestamps', 'src', 'dst2' -WorkingDirectory $dir).ExitCode | Should -Be 0
    }

    It 'sets modes with -m / --mode (Unix) and rejects symbolic modes' {
        (Invoke-TestGnu install '-m', '644', 'src', 'dst' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu install '--mode=600', 'src', 'dst' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu install '-m', 'u+x', 'src', 'dst' -WorkingDirectory $dir).ErrorText | Should -Match "invalid mode 'u\+x'"
    }

    It 'changes owner and group with -o / --owner and -g / --group on Unix only' {
        Mock -ModuleName PSGnuUtils Test-GnuWindows { $true }
        $r = Invoke-TestGnu install '-o', 'root', '--group=wheel', 'src', 'dst' -WorkingDirectory $dir
        $r.WarningText | Should -Match '--owner is ignored on Windows'
        $r.WarningText | Should -Match '--group is ignored on Windows'
    }

    It 'runs chown and chgrp on Unix' {
        Mock -ModuleName PSGnuUtils Test-GnuWindows { $false }
        Mock -ModuleName PSGnuUtils Set-GnuUnixMode { $true }
        Mock -ModuleName PSGnuUtils Start-Process { [pscustomobject]@{ ExitCode = [int]($FilePath -eq 'chgrp') } }
        $r = Invoke-TestGnu install '--owner', 'root', '-g', 'wheel', 'src', 'dst' -WorkingDirectory $dir
        $r.ErrorText | Should -Match "cannot change group of 'dst' to 'wheel'"
        Should -Invoke -ModuleName PSGnuUtils Start-Process -Times 2
    }

    It 'reports errors like GNU' {
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'folder')
        (Invoke-TestGnu install -WorkingDirectory $dir).ErrorText | Should -Match 'missing file operand'
        (Invoke-TestGnu install '-d' -WorkingDirectory $dir).ErrorText | Should -Match 'missing file operand'
        (Invoke-TestGnu install 'src' -WorkingDirectory $dir).ErrorText | Should -Match "missing destination file operand after 'src'"
        (Invoke-TestGnu install 'nosuch', 'x' -WorkingDirectory $dir).ErrorText | Should -Match "cannot stat 'nosuch': No such file or directory"
        (Invoke-TestGnu install 'folder', 'x' -WorkingDirectory $dir).ErrorText | Should -Match "omitting directory 'folder'"
        (Invoke-TestGnu install 'src', 'src' -WorkingDirectory $dir).ErrorText | Should -Match "'src' and 'src' are the same file"
        (Invoke-TestGnu install 'src', 'src', 'notadir' -WorkingDirectory $dir).ErrorText | Should -Match "target 'notadir' is not a directory"
        (Invoke-TestGnu install 'src', 'no/such/dir/file' -WorkingDirectory $dir).ErrorText | Should -Match "cannot create regular file 'no/such/dir/file'"
        $null = New-TestFile -Path (Join-Path $dir 'blocker') -Content 'x'
        (Invoke-TestGnu install '-d', 'blocker/sub' -WorkingDirectory $dir).ErrorText | Should -Match "cannot create directory 'blocker/sub'"
        (Invoke-TestGnu install '-D', 'src', 'blocker/sub/file' -WorkingDirectory $dir).ExitCode | Should -Be 1
        (Invoke-TestGnu install '-D', '-t', 'blocker/sub', 'src' -WorkingDirectory $dir).ExitCode | Should -Be 1
    }
}
