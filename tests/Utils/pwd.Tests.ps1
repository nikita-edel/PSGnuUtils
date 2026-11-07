BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'pwd' {
    It 'prints the current PowerShell location with -L / --logical' {
        $expected = (Get-Item -LiteralPath $TestDrive).FullName.TrimEnd('\', '/')
        (Invoke-TestGnu pwd '-L' -WorkingDirectory $TestDrive).Output | Should -Be @($expected)
        (Invoke-TestGnu pwd '--logical' -WorkingDirectory $TestDrive).Output | Should -Be @($expected)
    }

    It 'prints a physical path by default and with -P / --physical' {
        $r = Invoke-TestGnu pwd -WorkingDirectory $TestDrive
        $r.ExitCode | Should -Be 0
        $r.Output.Count | Should -Be 1
        [System.IO.Path]::IsPathRooted($r.Output[0]) | Should -BeTrue
        (Invoke-TestGnu pwd '-P' -WorkingDirectory $TestDrive).Output | Should -Be $r.Output
        (Invoke-TestGnu pwd '--physical' -WorkingDirectory $TestDrive).Output | Should -Be $r.Output
    }

    It 'resolves symbolic links with -P but not with -L' {
        if (-not (Test-CanCreateSymbolicLink -Directory $TestDrive)) { Set-ItResult -Skipped -Because 'symbolic links cannot be created here' }
        $real = Join-Path $TestDrive 'pwd-real'
        $link = Join-Path $TestDrive 'pwd-link'
        $null = New-Item -ItemType Directory -Path $real
        $null = New-Item -ItemType SymbolicLink -Path $link -Value $real
        (Invoke-TestGnu pwd '-P' -WorkingDirectory $link).Output[0] | Should -Be ([System.IO.Path]::GetFullPath($real))
        (Invoke-TestGnu pwd '-L' -WorkingDirectory $link).Output[0] | Should -Be ([System.IO.Path]::GetFullPath($link))
    }

    It 'warns about non-option arguments' {
        $r = Invoke-TestGnu pwd 'extra' -WorkingDirectory $TestDrive
        $r.WarningText | Should -Match 'ignoring non-option arguments'
        $r.ExitCode | Should -Be 0
    }
}
