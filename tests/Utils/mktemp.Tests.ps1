BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'mktemp' {
    BeforeEach {
        $script:savedTmp = $env:TMPDIR
        $env:TMPDIR = Join-Path $TestDrive 'tmp'
        $null = New-Item -ItemType Directory -Path $env:TMPDIR -Force
    }
    AfterEach {
        $env:TMPDIR = $script:savedTmp
    }

    It 'creates a file in $TMPDIR by default' {
        $r = Invoke-TestGnu mktemp
        $r.ExitCode | Should -Be 0
        $r.Output[0] | Should -Match 'tmp\.[A-Za-z0-9]{10}$'
        [System.IO.Path]::GetDirectoryName($r.Output[0]) | Should -Be $env:TMPDIR
        Test-Path -LiteralPath $r.Output[0] -PathType Leaf | Should -BeTrue
    }

    It 'creates a directory with -d / --directory' {
        $r = Invoke-TestGnu mktemp '-d'
        Test-Path -LiteralPath $r.Output[0] -PathType Container | Should -BeTrue
        $r = Invoke-TestGnu mktemp '--directory'
        Test-Path -LiteralPath $r.Output[0] -PathType Container | Should -BeTrue
    }

    It 'uses a template relative to the current directory' {
        $r = Invoke-TestGnu mktemp 'job.XXXXXX' -WorkingDirectory $TestDrive
        $r.Output[0] | Should -Match '^job\.[A-Za-z0-9]{6}$'
        Test-Path -LiteralPath (Join-Path $TestDrive $r.Output[0]) | Should -BeTrue
    }

    It 'puts the template into a directory with -p / --tmpdir' {
        $directory = Join-Path $TestDrive 'custom'
        $null = New-Item -ItemType Directory -Path $directory
        $r = Invoke-TestGnu mktemp '-p', $directory, 'xXXXXX'
        [System.IO.Path]::GetDirectoryName($r.Output[0]) | Should -Be $directory
        $r = Invoke-TestGnu mktemp "--tmpdir=$directory", 'yXXXXX'
        [System.IO.Path]::GetDirectoryName($r.Output[0]) | Should -Be $directory
        $r = Invoke-TestGnu mktemp '--tmpdir', 'zXXXXX'
        [System.IO.Path]::GetDirectoryName($r.Output[0]) | Should -Be $env:TMPDIR
    }

    It 'interprets the template relative to $TMPDIR with -t' {
        $r = Invoke-TestGnu mktemp '-t', 'tee.XXXX'
        [System.IO.Path]::GetDirectoryName($r.Output[0]) | Should -Be $env:TMPDIR
    }

    It 'appends --suffix and detects implicit suffixes' {
        (Invoke-TestGnu mktemp '--suffix=.txt', 'sXXXX' -WorkingDirectory $TestDrive).Output[0] | Should -Match '^s[A-Za-z0-9]{4}\.txt$'
        (Invoke-TestGnu mktemp 'iXXXX.log' -WorkingDirectory $TestDrive).Output[0] | Should -Match '^i[A-Za-z0-9]{4}\.log$'
    }

    It 'only prints a name with -u / --dry-run' {
        $r = Invoke-TestGnu mktemp '-u'
        Test-Path -LiteralPath $r.Output[0] | Should -BeFalse
        $r = Invoke-TestGnu mktemp '--dry-run'
        Test-Path -LiteralPath $r.Output[0] | Should -BeFalse
    }

    It 'validates templates' {
        (Invoke-TestGnu mktemp 'aXX').ErrorText | Should -Match "too few X's in template 'aXX'"
        (Invoke-TestGnu mktemp 'a', 'b').ErrorText | Should -Match 'too many templates'
        (Invoke-TestGnu mktemp '--suffix=a/b', 'cXXX').ErrorText | Should -Match 'contains directory separator'
        $absolute = Join-Path $TestDrive 'absXXX'
        (Invoke-TestGnu mktemp '-p', $TestDrive, $absolute).ErrorText | Should -Match 'may not be absolute'
    }

    It 'reports creation failures, silently with -q / --quiet' {
        $template = Join-Path $TestDrive 'missing-dir/fXXXX'
        $r = Invoke-TestGnu mktemp $template
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match 'failed to create file via template'
        $r = Invoke-TestGnu mktemp '-q', $template
        $r.ExitCode | Should -Be 1
        $r.Errors.Count | Should -Be 0
        $r = Invoke-TestGnu mktemp '--quiet', '-d', (Join-Path $TestDrive 'missing-dir/sub/dXXXX')
        $r.ExitCode | Should -Be 1
        $r.Errors.Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path $TestDrive 'missing-dir') | Should -BeFalse
    }
}
