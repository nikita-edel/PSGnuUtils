BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')

    function Get-TestSize([string]$Name) { (Get-Item -LiteralPath (Join-Path $TestDrive $Name)).Length }
}

Describe 'truncate' {
    It 'sets absolute sizes with -s / --size and creates missing files' {
        (Invoke-TestGnu truncate '-s', '10', 'new.bin' -WorkingDirectory $TestDrive).ExitCode | Should -Be 0
        Get-TestSize 'new.bin' | Should -Be 10
        (Invoke-TestGnu truncate '--size=1K', 'new.bin' -WorkingDirectory $TestDrive).ExitCode | Should -Be 0
        Get-TestSize 'new.bin' | Should -Be 1024
        (Invoke-TestGnu truncate '-s', '0', 'new.bin' -WorkingDirectory $TestDrive).ExitCode | Should -Be 0
        Get-TestSize 'new.bin' | Should -Be 0
    }

    It 'keeps existing data when shrinking' {
        $null = New-TestFile -Path (Join-Path $TestDrive 'data.txt') -Content 'abcdef'
        $null = Invoke-TestGnu truncate '-s', '3', 'data.txt' -WorkingDirectory $TestDrive
        [System.IO.File]::ReadAllText((Join-Path $TestDrive 'data.txt')) | Should -Be 'abc'
    }

    It 'supports relative sizes' -ForEach @(
        @{ Size = '+5'; Expected = 15 }
        @{ Size = '-4'; Expected = 6 }
        @{ Size = '-50'; Expected = 0 }
        @{ Size = '<4'; Expected = 4 }
        @{ Size = '<40'; Expected = 10 }
        @{ Size = '>40'; Expected = 40 }
        @{ Size = '>4'; Expected = 10 }
        @{ Size = '/4'; Expected = 8 }
        @{ Size = '%4'; Expected = 12 }
    ) {
        $name = 'rel-' + [guid]::NewGuid() + '.bin'
        $null = New-TestFile -Path (Join-Path $TestDrive $name) -Bytes (New-Object byte[] 10)
        (Invoke-TestGnu truncate '-s', $Size, $name -WorkingDirectory $TestDrive).ExitCode | Should -Be 0
        Get-TestSize $name | Should -Be $Expected
    }

    It 'does not create files with -c / --no-create' {
        (Invoke-TestGnu truncate '-c', '-s', '1', 'not-created' -WorkingDirectory $TestDrive).ExitCode | Should -Be 0
        (Invoke-TestGnu truncate '--no-create', '-s', '1', 'not-created' -WorkingDirectory $TestDrive).ExitCode | Should -Be 0
        Test-Path -LiteralPath (Join-Path $TestDrive 'not-created') | Should -BeFalse
    }

    It 'counts IO blocks of 4096 bytes with -o / --io-blocks' {
        $null = Invoke-TestGnu truncate '-o', '-s', '2', 'blocks.bin' -WorkingDirectory $TestDrive
        Get-TestSize 'blocks.bin' | Should -Be 8192
        $null = Invoke-TestGnu truncate '--io-blocks', '-s', '1', 'blocks.bin' -WorkingDirectory $TestDrive
        Get-TestSize 'blocks.bin' | Should -Be 4096
    }

    It 'copies the size of a reference file with -r / --reference' {
        $null = New-TestFile -Path (Join-Path $TestDrive 'ref.bin') -Bytes (New-Object byte[] 7)
        $null = Invoke-TestGnu truncate '-r', 'ref.bin', 'copy.bin' -WorkingDirectory $TestDrive
        Get-TestSize 'copy.bin' | Should -Be 7
        $null = Invoke-TestGnu truncate '--reference=ref.bin', '-s', '+3', 'copy.bin' -WorkingDirectory $TestDrive
        Get-TestSize 'copy.bin' | Should -Be 10
    }

    It 'validates its options' {
        (Invoke-TestGnu truncate 'x' -WorkingDirectory $TestDrive).ErrorText | Should -Match "you must specify either '--size' or '--reference'"
        (Invoke-TestGnu truncate '-s', '1' -WorkingDirectory $TestDrive).ErrorText | Should -Match 'missing file operand'
        (Invoke-TestGnu truncate '-s', 'abc', 'x' -WorkingDirectory $TestDrive).ErrorText | Should -Match "Invalid number: 'abc'"
        (Invoke-TestGnu truncate '-s', '/0', 'x' -WorkingDirectory $TestDrive).ErrorText | Should -Match 'division by zero'
        (Invoke-TestGnu truncate '-r', 'missing-ref', 'x' -WorkingDirectory $TestDrive).ErrorText | Should -Match "cannot stat 'missing-ref'"
        $null = New-TestFile -Path (Join-Path $TestDrive 'r2.bin') -Content 'x'
        (Invoke-TestGnu truncate '-r', 'r2.bin', '-s', '5', 'x' -WorkingDirectory $TestDrive).ErrorText | Should -Match "relative '--size' with '--reference'"
    }

    It 'refuses directories and missing parents' {
        $null = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'a-dir')
        (Invoke-TestGnu truncate '-s', '0', 'a-dir' -WorkingDirectory $TestDrive).ErrorText | Should -Match 'Is a directory'
        $r = Invoke-TestGnu truncate '-s', '0', 'no/parent.bin' -WorkingDirectory $TestDrive
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match "cannot open 'no/parent.bin' for writing"
    }

    It 'treats a directory reference as size 0' {
        $null = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'ref-dir') -Force
        $null = New-TestFile -Path (Join-Path $TestDrive 'from-dir.bin') -Bytes (New-Object byte[] 5)
        $null = Invoke-TestGnu truncate '-r', 'ref-dir', '-s', '+2', 'from-dir.bin' -WorkingDirectory $TestDrive
        Get-TestSize 'from-dir.bin' | Should -Be 2
    }
}
