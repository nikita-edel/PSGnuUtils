BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'rmdir' {
    It 'removes empty directories' {
        $null = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'empty')
        $r = Invoke-TestGnu rmdir 'empty' -WorkingDirectory $TestDrive
        $r.ExitCode | Should -Be 0
        Test-Path -LiteralPath (Join-Path $TestDrive 'empty') | Should -BeFalse
    }

    It 'refuses non-empty directories, files and missing paths' {
        $null = New-TestFile -Path (Join-Path $TestDrive 'full/file.txt') -Content 'x'
        (Invoke-TestGnu rmdir 'full' -WorkingDirectory $TestDrive).ErrorText | Should -Match "failed to remove 'full': Directory not empty"
        (Invoke-TestGnu rmdir 'full/file.txt' -WorkingDirectory $TestDrive).ErrorText | Should -Match 'Not a directory'
        $r = Invoke-TestGnu rmdir 'missing-dir' -WorkingDirectory $TestDrive
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match 'No such file or directory'
    }

    It 'silently skips non-empty directories with --ignore-fail-on-non-empty' {
        $null = New-TestFile -Path (Join-Path $TestDrive 'busy/file.txt') -Content 'x'
        $r = Invoke-TestGnu rmdir '--ignore-fail-on-non-empty', 'busy' -WorkingDirectory $TestDrive
        $r.ExitCode | Should -Be 0
        $r.Errors.Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path $TestDrive 'busy') | Should -BeTrue
    }

    It 'removes ancestors with -p / --parents' {
        $null = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'r1/r2/r3') -Force
        (Invoke-TestGnu rmdir '-p', 'r1/r2/r3' -WorkingDirectory $TestDrive).ExitCode | Should -Be 0
        Test-Path -LiteralPath (Join-Path $TestDrive 'r1') | Should -BeFalse

        $null = New-Item -ItemType Directory -Path (Join-Path $TestDrive 's1/s2') -Force
        $null = New-TestFile -Path (Join-Path $TestDrive 's1/keep.txt') -Content 'x'
        $r = Invoke-TestGnu rmdir '--parents', 's1/s2' -WorkingDirectory $TestDrive
        $r.ErrorText | Should -Match "failed to remove 's1': Directory not empty"
        Test-Path -LiteralPath (Join-Path $TestDrive 's1/s2') | Should -BeFalse
    }

    It 'reports every directory with -v / --verbose' {
        $null = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'v1/v2') -Force
        $r = Invoke-TestGnu rmdir '-pv', 'v1/v2' -WorkingDirectory $TestDrive
        $r.Output | Should -Be @("rmdir: removing directory, 'v1/v2'", "rmdir: removing directory, 'v1'")
        $null = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'v3')
        (Invoke-TestGnu rmdir '--verbose', 'v3' -WorkingDirectory $TestDrive).Output | Should -Be @("rmdir: removing directory, 'v3'")
    }

    It 'expands wildcards' {
        $null = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'w-a'), (Join-Path $TestDrive 'w-b')
        (Invoke-TestGnu rmdir 'w-*' -WorkingDirectory $TestDrive).ExitCode | Should -Be 0
        @(Get-ChildItem -LiteralPath $TestDrive -Filter 'w-*').Count | Should -Be 0
    }

    It 'reports a missing operand' {
        (Invoke-TestGnu rmdir).ErrorText | Should -Match 'missing operand'
    }
}
