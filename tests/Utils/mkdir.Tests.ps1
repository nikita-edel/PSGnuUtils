BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'mkdir' {
    It 'creates directories' {
        $r = Invoke-TestGnu mkdir 'one', 'two' -WorkingDirectory $TestDrive
        $r.ExitCode | Should -Be 0
        Test-Path -LiteralPath (Join-Path $TestDrive 'one') -PathType Container | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $TestDrive 'two') -PathType Container | Should -BeTrue
    }

    It 'fails for existing directories and missing parents without -p' {
        $null = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'exists')
        (Invoke-TestGnu mkdir 'exists' -WorkingDirectory $TestDrive).ErrorText | Should -Match "cannot create directory 'exists': File exists"
        $r = Invoke-TestGnu mkdir 'no/such/parent' -WorkingDirectory $TestDrive
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match 'No such file or directory'
    }

    It 'creates parents and accepts existing directories with -p / --parents' {
        (Invoke-TestGnu mkdir '-p', 'p1/p2/p3' -WorkingDirectory $TestDrive).ExitCode | Should -Be 0
        Test-Path -LiteralPath (Join-Path $TestDrive 'p1/p2/p3') -PathType Container | Should -BeTrue
        (Invoke-TestGnu mkdir '--parents', 'p1/p2' -WorkingDirectory $TestDrive).ExitCode | Should -Be 0
    }

    It 'reports every created directory with -v / --verbose' {
        $r = Invoke-TestGnu mkdir '-pv', 'v1/v2' -WorkingDirectory $TestDrive
        $r.Output | Should -Be @("mkdir: created directory 'v1'", "mkdir: created directory 'v1/v2'")
        (Invoke-TestGnu mkdir '--verbose', 'v3' -WorkingDirectory $TestDrive).Output | Should -Be @("mkdir: created directory 'v3'")
    }

    It 'refuses to create a directory over a file' {
        $null = New-TestFile -Path (Join-Path $TestDrive 'plain-file') -Content 'x'
        $r = Invoke-TestGnu mkdir '-p', 'plain-file' -WorkingDirectory $TestDrive
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match 'File exists'
        (Invoke-TestGnu mkdir '-p', 'plain-file/sub' -WorkingDirectory $TestDrive).ErrorText | Should -Match 'Not a directory'
    }

    It 'accepts octal modes with -m / --mode and rejects others' {
        (Invoke-TestGnu mkdir '-m', '700', 'm1' -WorkingDirectory $TestDrive).ExitCode | Should -Be 0
        (Invoke-TestGnu mkdir '--mode=0755', 'm2' -WorkingDirectory $TestDrive).ExitCode | Should -Be 0
        $r = Invoke-TestGnu mkdir '-m', 'u+rwx', 'm3' -WorkingDirectory $TestDrive
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match "invalid mode 'u\+rwx'"
        Test-Path -LiteralPath (Join-Path $TestDrive 'm3') | Should -BeFalse
    }

    It 'applies the mode on Unix with PowerShell 7.3+' {
        if ((Test-IsWindowsPlatform) -or $PSVersionTable.PSVersion -lt [version]'7.3') { Set-ItResult -Skipped -Because 'needs Unix and .NET 7+' }
        $null = Invoke-TestGnu mkdir '-m', '700', 'mode-check' -WorkingDirectory $TestDrive
        [int][System.IO.File]::GetUnixFileMode((Join-Path $TestDrive 'mode-check')) | Should -Be 448
    }

    It 'accepts -Z / --context for compatibility' {
        (Invoke-TestGnu mkdir '-Z', 'z1' -WorkingDirectory $TestDrive).ExitCode | Should -Be 0
        (Invoke-TestGnu mkdir '--context=ctx', 'z2' -WorkingDirectory $TestDrive).ExitCode | Should -Be 0
    }

    It 'reports a missing operand' {
        (Invoke-TestGnu mkdir).ErrorText | Should -Match 'missing operand'
    }
}
