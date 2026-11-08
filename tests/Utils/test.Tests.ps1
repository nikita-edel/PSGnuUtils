BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# Expected exit codes and messages come from GNU coreutils test.
Describe 'test' {
    BeforeAll {
        $script:dir = Join-Path $TestDrive 'test'
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'sub') -Force
        $script:file = New-TestFile -Path (Join-Path $dir 'file.txt') -Content 'data'
        $script:empty = New-TestFile -Path (Join-Path $dir 'empty.txt') -Content ''
        $script:old = New-TestFile -Path (Join-Path $dir 'old.txt') -Content 'old'
        [System.IO.File]::SetLastWriteTimeUtc($old, [datetime]::new(2000, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc))
        $script:program = New-TestFile -Path (Join-Path $dir 'tool.exe') -Content 'x'
    }

    It 'evaluates <Expression> with exit code <ExitCode>' -ForEach @(
        @{ Expression = @(); ExitCode = 1 }
        @{ Expression = @('x'); ExitCode = 0 }
        @{ Expression = @(''); ExitCode = 1 }
        @{ Expression = @('-n'); ExitCode = 0 }
        @{ Expression = @('-l'); ExitCode = 0 }
        @{ Expression = @('-a'); ExitCode = 0 }
        @{ Expression = @('!', 'x'); ExitCode = 1 }
        @{ Expression = @('-z', ''); ExitCode = 0 }
        @{ Expression = @('-n', 'a'); ExitCode = 0 }
        @{ Expression = @('a', '=', 'a'); ExitCode = 0 }
        @{ Expression = @('a', '==', 'a'); ExitCode = 0 }
        @{ Expression = @('a', '!=', 'a'); ExitCode = 1 }
        @{ Expression = @('a', '<', 'b'); ExitCode = 0 }
        @{ Expression = @('a', '>', 'b'); ExitCode = 1 }
        @{ Expression = @('1', '-eq', '01'); ExitCode = 0 }
        @{ Expression = @('1', '-ne', '2'); ExitCode = 0 }
        @{ Expression = @('-5', '-lt', '3'); ExitCode = 0 }
        @{ Expression = @('2', '-le', '1'); ExitCode = 1 }
        @{ Expression = @('3', '-gt', '2'); ExitCode = 0 }
        @{ Expression = @('2', '-ge', '2'); ExitCode = 0 }
        @{ Expression = @(' 5 ', '-eq', '+5'); ExitCode = 0 }
        @{ Expression = @('99999999999999999999', '-gt', '1'); ExitCode = 0 }
        @{ Expression = @('-l', 'abc', '-eq', '3'); ExitCode = 0 }
        @{ Expression = @('3', '-eq', '-l', 'abc'); ExitCode = 0 }
        @{ Expression = @('(', 'a', ')'); ExitCode = 0 }
        @{ Expression = @('!', 'a', '=', 'b'); ExitCode = 0 }
        @{ Expression = @('(', '-n', 'x', ')'); ExitCode = 0 }
        @{ Expression = @('3', '=', '-l', 'abc'); ExitCode = 1 }
        @{ Expression = @('=', '=', '-l', '='); ExitCode = 0 }
        @{ Expression = @('-l', 'abc', '=', 'abc'); ExitCode = 0 }
        @{ Expression = @('(', '', ')'); ExitCode = 1 }
        @{ Expression = @('!', '(', 'a', '=', 'b', ')'); ExitCode = 0 }
        @{ Expression = @('(', 'a', '=', 'a', ')', '-a', 'b'); ExitCode = 0 }
        @{ Expression = @('(', 'a', '-o', '(', '', ')', ')'); ExitCode = 0 }
        @{ Expression = @('(', '!', ')'); ExitCode = 0 }
        @{ Expression = @('!', '!', 'a'); ExitCode = 0 }
        @{ Expression = @('!', '-z', 'a', '-a', 'b'); ExitCode = 0 }
        @{ Expression = @('a', '-a', ''); ExitCode = 1 }
        @{ Expression = @('', '-o', 'b'); ExitCode = 0 }
        @{ Expression = @('1', '-gt', '2', '-o', '3', '-gt', '2'); ExitCode = 0 }
        @{ Expression = @('a', '=', 'b', '-o', 'c', '=', 'c', '-a', 'd', '=', 'e'); ExitCode = 1 }
        @{ Expression = @('-n', '-n'); ExitCode = 0 }
        @{ Expression = @('=', '=', '='); ExitCode = 0 }
        @{ Expression = @('!', '=', 'x'); ExitCode = 1 }
        @{ Expression = @('!', '-n'); ExitCode = 1 }
        @{ Expression = @('-z'); ExitCode = 0 }
        @{ Expression = @(')'); ExitCode = 0 }
        @{ Expression = @('-t', '7'); ExitCode = 1 }
    ) {
        $r = Invoke-TestGnu test $Expression
        $r.Errors | Should -BeNullOrEmpty
        $r.Output | Should -BeNullOrEmpty
        $r.ExitCode | Should -Be $ExitCode
    }

    It 'reports <Message> for <Expression> (exit code 2)' -ForEach @(
        @{ Expression = @('x', '-eq', '1'); Message = "test: invalid integer 'x'" }
        @{ Expression = @('a', '-lt', 'b'); Message = "test: invalid integer 'a'" }
        @{ Expression = @('1', '-lt'); Message = "test: missing argument after '-lt'" }
        @{ Expression = @('a', 'b', 'c'); Message = "test: 'b': binary operator expected" }
        @{ Expression = @('-q', 'x'); Message = "test: '-q': unary operator expected" }
        @{ Expression = @('-o', 'x'); Message = "test: '-o': unary operator expected" }
        @{ Expression = @('(', 'a'); Message = "test: missing argument after 'a'" }
        @{ Expression = @('(', 'a', 'b'); Message = "test: 'a': binary operator expected" }
        @{ Expression = @('(', 'a', '=', 'a', 'b'); Message = "test: ')' expected, found 'b'" }
        @{ Expression = @('(', 'a', '=', 'a', '-a', 'b'); Message = "test: ')' expected" }
        @{ Expression = @('a', '=', 'b', '=', 'c'); Message = "test: extra argument '='" }
        @{ Expression = @('x', '-a'); Message = "test: missing argument after '-a'" }
        @{ Expression = @('a', '-a', '!'); Message = "test: missing argument after '!'" }
        @{ Expression = @('a', '-a', 'b', '-a', '-q', 'c'); Message = "test: '-q': unary operator expected" }
        @{ Expression = @('a', '-a', 'b', '-a'); Message = "test: missing argument after '-a'" }
        @{ Expression = @('-l', 'a', '=', 'b', 'c'); Message = "test: extra argument 'c'" }
    ) {
        $r = Invoke-TestGnu test $Expression
        $r.ErrorText | Should -Be $Message
        $r.ExitCode | Should -Be 2
    }

    It 'tests files: -e -f -d -s' {
        (Invoke-TestGnu test '-e', $file).ExitCode | Should -Be 0
        (Invoke-TestGnu test '-e', (Join-Path $dir 'nope')).ExitCode | Should -Be 1
        (Invoke-TestGnu test '-e', '').ExitCode | Should -Be 1
        (Invoke-TestGnu test '-f', $file).ExitCode | Should -Be 0
        (Invoke-TestGnu test '-f', (Join-Path $dir 'sub')).ExitCode | Should -Be 1
        (Invoke-TestGnu test '-d', (Join-Path $dir 'sub')).ExitCode | Should -Be 0
        (Invoke-TestGnu test '-d', $file).ExitCode | Should -Be 1
        (Invoke-TestGnu test '-s', $file).ExitCode | Should -Be 0
        (Invoke-TestGnu test '-s', $empty).ExitCode | Should -Be 1
        (Invoke-TestGnu test '-s', (Join-Path $dir 'sub')).ExitCode | Should -Be 0
        (Invoke-TestGnu test '-O', $file).ExitCode | Should -Be 0
        (Invoke-TestGnu test '-G', $file).ExitCode | Should -Be 0
    }

    It 'compares files with -nt / -ot / -ef' {
        (Invoke-TestGnu test $file, '-nt', $old).ExitCode | Should -Be 0
        (Invoke-TestGnu test $file, '-ot', $old).ExitCode | Should -Be 1
        (Invoke-TestGnu test $old, '-ot', $file).ExitCode | Should -Be 0
        (Invoke-TestGnu test $file, '-nt', 'nope' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu test 'nope', '-nt', $file -WorkingDirectory $dir).ExitCode | Should -Be 1
        (Invoke-TestGnu test 'sub', '-nt', '' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu test 'file.txt', '-ef', './sub/../file.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu test 'file.txt', '-ef', 'old.txt' -WorkingDirectory $dir).ExitCode | Should -Be 1
        (Invoke-TestGnu test 'file.txt', '-ef', 'nope' -WorkingDirectory $dir).ExitCode | Should -Be 1
    }

    It 'tests links with -h / -L' {
        $link = Join-Path $dir 'link'
        if (-not (New-TestDirectoryLink -Path $link -Target (Join-Path $dir 'sub'))) { Set-ItResult -Skipped -Because 'links cannot be created here'; return }
        (Invoke-TestGnu test '-h', $link).ExitCode | Should -Be 0
        (Invoke-TestGnu test '-L', $link).ExitCode | Should -Be 0
        (Invoke-TestGnu test '-L', $file).ExitCode | Should -Be 1
    }

    It 'tests permissions without Unix modes: -r -w -x' {
        Mock -ModuleName PSGnuUtils Get-GnuUnixFileMode { }
        Mock -ModuleName PSGnuUtils Get-GnuUnixModeString { }
        (Invoke-TestGnu test '-r', $file).ExitCode | Should -Be 0
        (Invoke-TestGnu test '-r', (Join-Path $dir 'sub')).ExitCode | Should -Be 0
        (Invoke-TestGnu test '-w', $file).ExitCode | Should -Be 0
        (Invoke-TestGnu test '-w', (Join-Path $dir 'sub')).ExitCode | Should -Be 0
        $readOnly = New-TestFile -Path (Join-Path $dir 'readonly.txt') -Content 'r'
        (Get-Item -LiteralPath $readOnly).Attributes = 'ReadOnly'
        try { (Invoke-TestGnu test '-w', $readOnly).ExitCode | Should -Be 1 }
        finally { (Get-Item -LiteralPath $readOnly).Attributes = 'Normal' }
        (Invoke-TestGnu test '-x', $program).ExitCode | Should -Be 0
        (Invoke-TestGnu test '-x', $file).ExitCode | Should -Be 1
        (Invoke-TestGnu test '-x', (Join-Path $dir 'sub')).ExitCode | Should -Be 0
        (Invoke-TestGnu test '-x', (New-TestFile -Path (Join-Path $dir 'noext') -Content '')).ExitCode | Should -Be 1
        $saved = $env:PATHEXT
        try {
            $env:PATHEXT = $null
            (Invoke-TestGnu test '-x', (New-TestFile -Path (Join-Path $dir 'run.cmd') -Content '')).ExitCode | Should -Be 0
        }
        finally { $env:PATHEXT = $saved }
        (Invoke-TestGnu test '-b', $file).ExitCode | Should -Be 1
        (Invoke-TestGnu test '-u', $file).ExitCode | Should -Be 1
    }

    It 'fails -r for files that cannot be opened' {
        $locked = New-TestFile -Path (Join-Path $dir 'locked.txt') -Content 'x'
        $stream = Lock-TestFile -Path $locked
        if ($null -eq $stream) { Set-ItResult -Skipped -Because 'the OS does not enforce file locks'; return }
        try { (Invoke-TestGnu test '-r', $locked).ExitCode | Should -Be 1 }
        finally { $stream.Dispose() }
    }

    It 'tests Unix file types with -b -c -p -S and -f' {
        Mock -ModuleName PSGnuUtils Get-GnuUnixModeString { 'crw-rw-rw-' }
        (Invoke-TestGnu test '-c', $file).ExitCode | Should -Be 0
        (Invoke-TestGnu test '-b', $file).ExitCode | Should -Be 1
        (Invoke-TestGnu test '-p', $file).ExitCode | Should -Be 1
        (Invoke-TestGnu test '-S', $file).ExitCode | Should -Be 1
        (Invoke-TestGnu test '-f', $file).ExitCode | Should -Be 1
    }

    It 'tests Unix block devices, pipes and sockets' {
        Mock -ModuleName PSGnuUtils Get-GnuUnixModeString { 'brw-rw----' }
        (Invoke-TestGnu test '-b', $file).ExitCode | Should -Be 0
    }

    It 'tests Unix named pipes' {
        Mock -ModuleName PSGnuUtils Get-GnuUnixModeString { 'prw-r--r--' }
        (Invoke-TestGnu test '-p', $file).ExitCode | Should -Be 0
    }

    It 'tests Unix sockets' {
        Mock -ModuleName PSGnuUtils Get-GnuUnixModeString { 'srwxr-xr-x' }
        (Invoke-TestGnu test '-S', $file).ExitCode | Should -Be 0
    }

    It 'tests Unix mode bits with -u -g -k -w -x' {
        # setuid + setgid + sticky + rwx for the owner only.
        Mock -ModuleName PSGnuUtils Get-GnuUnixFileMode { 2048 + 1024 + 512 + 448 }
        foreach ($operator in '-u', '-g', '-k', '-w', '-x') { (Invoke-TestGnu test $operator, $file).ExitCode | Should -Be 0 }
    }

    It 'tests Unix files without w and x bits' {
        Mock -ModuleName PSGnuUtils Get-GnuUnixFileMode { 256 }   # r--------
        foreach ($operator in '-u', '-g', '-k', '-w', '-x') { (Invoke-TestGnu test $operator, $file).ExitCode | Should -Be 1 }
    }

    It 'tests -N (modified since last read)' {
        $fresh = New-TestFile -Path (Join-Path $dir 'fresh.txt') -Content 'x'
        [System.IO.File]::SetLastAccessTimeUtc($fresh, [datetime]::new(2000, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc))
        (Invoke-TestGnu test '-N', $fresh).ExitCode | Should -Be 0
        [System.IO.File]::SetLastAccessTimeUtc($fresh, [datetime]::UtcNow.AddDays(1))
        (Invoke-TestGnu test '-N', $fresh).ExitCode | Should -Be 1
    }

    It 'tests terminals with -t' {
        foreach ($descriptor in '0', '1', '2') { (Invoke-TestGnu test '-t', $descriptor).ExitCode | Should -BeIn @(0, 1) }
        (Invoke-TestGnu test '-t', 'x').ExitCode | Should -Be 2
    }

    It 'reads Unix mode strings only off Windows' {
        InModuleScope PSGnuUtils -Parameters @{ Path = $file } {
            param($Path)
            Mock Test-GnuWindows { $true }
            Get-GnuUnixModeString -Path $Path | Should -BeNullOrEmpty
        }
        InModuleScope PSGnuUtils -Parameters @{ Path = $file } {
            param($Path)
            Mock Test-GnuWindows { $false }
            { Get-GnuUnixModeString -Path $Path } | Should -Not -Throw
        }
    }

    It 'does not hide unexpected errors' {
        Mock -ModuleName PSGnuUtils Invoke-GnuTestPosix { throw 'boom' }
        { Invoke-GnuTest a } | Should -Throw 'boom'
    }
}
