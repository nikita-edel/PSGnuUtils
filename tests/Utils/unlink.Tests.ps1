BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'unlink' {
    It 'removes a file' {
        $file = New-TestFile -Path (Join-Path $TestDrive 'remove-me.txt') -Content 'x'
        $r = Invoke-TestGnu unlink $file
        $r.ExitCode | Should -Be 0
        Test-Path -LiteralPath $file | Should -BeFalse
    }

    It 'refuses directories' {
        $directory = Join-Path $TestDrive 'keep-dir'
        $null = New-Item -ItemType Directory -Path $directory
        $r = Invoke-TestGnu unlink $directory
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match 'Is a directory'
        Test-Path -LiteralPath $directory | Should -BeTrue
    }

    It 'removes a symbolic link to a directory but not the directory' {
        if (-not (Test-CanCreateSymbolicLink -Directory $TestDrive)) { Set-ItResult -Skipped -Because 'symbolic links cannot be created here' }
        $target = Join-Path $TestDrive 'link-target'
        $link = Join-Path $TestDrive 'dir-link'
        $null = New-Item -ItemType Directory -Path $target
        $null = New-Item -ItemType SymbolicLink -Path $link -Value $target
        (Invoke-TestGnu unlink $link).ExitCode | Should -Be 0
        Test-Path -LiteralPath $link | Should -BeFalse
        Test-Path -LiteralPath $target | Should -BeTrue
    }

    It 'reports missing files' {
        $r = Invoke-TestGnu unlink (Join-Path $TestDrive 'missing')
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match 'No such file or directory'
    }

    It 'checks the operand count' {
        (Invoke-TestGnu unlink).ErrorText | Should -Match 'missing operand'
        (Invoke-TestGnu unlink 'a', 'b').ErrorText | Should -Match "extra operand 'b'"
    }
}
