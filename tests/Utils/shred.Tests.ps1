BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# Messages follow GNU coreutils shred.
Describe 'shred' {
    BeforeEach {
        $script:dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $null = New-Item -ItemType Directory -Path $dir
        $script:file = New-TestFile -Path (Join-Path $dir 'f') -Content "hello world`n"
    }

    It 'overwrites files 3 times, rounded up to 4 KiB blocks' {
        $r = Invoke-TestGnu shred 'f' -WorkingDirectory $dir
        $r.ExitCode | Should -Be 0
        (Get-Item -LiteralPath $file).Length | Should -Be 4096
        [System.IO.File]::ReadAllText($file) | Should -Not -Match 'hello'
    }

    It 'reports passes with -v / --verbose and sets them with -n / --iterations' {
        (Invoke-TestGnu shred '-v', '-n', '2', 'f' -WorkingDirectory $dir).Warnings | Should -Be @('shred: f: pass 1/2 (random)...', 'shred: f: pass 2/2 (random)...')
        (Invoke-TestGnu shred '--verbose', '--iterations=1', 'f' -WorkingDirectory $dir).Warnings.Count | Should -Be 1
        (Invoke-TestGnu shred '-n', '0', 'f' -WorkingDirectory $dir).ExitCode | Should -Be 0
    }

    It 'adds a final pass of zeros with -z / --zero' {
        $r = Invoke-TestGnu shred '-v', '-n', '1', '-z', 'f' -WorkingDirectory $dir
        $r.Warnings | Should -Be @('shred: f: pass 1/2 (random)...', 'shred: f: pass 2/2 (000000)...')
        @([System.IO.File]::ReadAllBytes($file) | Where-Object { $_ -ne 0 }).Count | Should -Be 0
        (Invoke-TestGnu shred '--zero', '-n', '0', 'f' -WorkingDirectory $dir).ExitCode | Should -Be 0
    }

    It 'keeps the exact size with -x / --exact and shreds -s / --size bytes' {
        $null = Invoke-TestGnu shred '-x', 'f' -WorkingDirectory $dir
        (Get-Item -LiteralPath $file).Length | Should -Be 12
        $null = Invoke-TestGnu shred '--exact', '-n', '1', 'f' -WorkingDirectory $dir
        (Get-Item -LiteralPath $file).Length | Should -Be 12
        $null = Invoke-TestGnu shred '-s', '20', '-n', '1', 'f' -WorkingDirectory $dir
        (Get-Item -LiteralPath $file).Length | Should -Be 20
        $null = Invoke-TestGnu shred '--size=1K', '-n', '1', 'f' -WorkingDirectory $dir
        (Get-Item -LiteralPath $file).Length | Should -Be 1024
        (Invoke-TestGnu shred '-s', 'x', 'f' -WorkingDirectory $dir).ErrorText | Should -Match "invalid file size: 'x'"
    }

    It 'removes the file with -u, renaming it to shorter names of zeros' {
        $null = New-TestFile -Path (Join-Path $dir 'abcd') -Content 'x'
        $r = Invoke-TestGnu shred '-v', '-u', '-n', '1', 'abcd' -WorkingDirectory $dir
        $r.Warnings | Should -Be @('shred: abcd: pass 1/1 (random)...', 'shred: abcd: removing', 'shred: abcd: renamed to 0000', 'shred: 0000: renamed to 000', 'shred: 000: renamed to 00', 'shred: 00: renamed to 0', 'shred: abcd: removed')
        @(Get-ChildItem -LiteralPath $dir -Name) | Should -Be @('f')
    }

    It 'keeps the directory part when renaming and skips names that exist' {
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'dd')
        $null = New-TestFile -Path (Join-Path $dir 'dd/file1') -Content 'y'
        $null = New-TestFile -Path (Join-Path $dir 'dd/0000') -Content 'keep'
        $r = Invoke-TestGnu shred '-v', '--remove=wipe', '-n', '0', 'dd/file1' -WorkingDirectory $dir
        $r.Warnings | Should -Contain 'shred: dd/file1: renamed to dd/00000'
        $r.Warnings | Should -Contain 'shred: dd/00000: renamed to dd/000'
        @(Get-ChildItem -LiteralPath (Join-Path $dir 'dd') -Name) | Should -Be @('0000')
    }

    It 'removes directly with --remove=unlink and --remove' {
        $r = Invoke-TestGnu shred '-v', '--remove=unlink', '-n', '0', 'f' -WorkingDirectory $dir
        $r.Warnings | Should -Be @('shred: f: removing', 'shred: f: removed')
        $null = New-TestFile -Path (Join-Path $dir 'g') -Content 'x'
        (Invoke-TestGnu shred '--remove', '-n', '0', 'g' -WorkingDirectory $dir).ExitCode | Should -Be 0
        Test-Path -LiteralPath (Join-Path $dir 'g') | Should -BeFalse
        (Invoke-TestGnu shred '--remove=burn', 'f' -WorkingDirectory $dir).ErrorText | Should -Match "invalid argument 'burn' for '--remove'"
    }

    It 'makes read-only files writable with -f / --force' {
        (Get-Item -LiteralPath $file).Attributes = 'ReadOnly'
        try {
            (Invoke-TestGnu shred '-n', '1', 'f' -WorkingDirectory $dir).ErrorText | Should -Match 'f: failed to open for writing'
            (Invoke-TestGnu shred '-f', '-n', '1', 'f' -WorkingDirectory $dir).ExitCode | Should -Be 0
            (Invoke-TestGnu shred '--force', '-n', '1', 'f' -WorkingDirectory $dir).ExitCode | Should -Be 0
        }
        finally { (Get-Item -LiteralPath $file).Attributes = 'Normal' }
    }

    It 'uses --random-source to seed the data' {
        $seed = New-TestFile -Path (Join-Path $dir 'seed') -Content 'seed'
        $null = New-TestFile -Path (Join-Path $dir 'g') -Content "hello world`n"
        $null = Invoke-TestGnu shred '--random-source=seed', '-x', '-n', '1', 'f' -WorkingDirectory $dir
        $null = Invoke-TestGnu shred '--random-source', $seed, '-x', '-n', '1', 'g' -WorkingDirectory $dir
        [System.IO.File]::ReadAllBytes($file) | Should -Be ([System.IO.File]::ReadAllBytes((Join-Path $dir 'g')))
        (Invoke-TestGnu shred '--random-source=nope', 'f' -WorkingDirectory $dir).ExitCode | Should -Be 1
    }

    It 'reports errors like GNU' {
        $r = Invoke-TestGnu shred -WorkingDirectory $dir
        $r.ErrorText | Should -Match 'missing file operand'
        $r.ExitCode | Should -Be 1
        (Invoke-TestGnu shred '-n', 'x', 'f' -WorkingDirectory $dir).ErrorText | Should -Match "invalid number of passes: 'x'"
        (Invoke-TestGnu shred 'nosuch' -WorkingDirectory $dir).ErrorText | Should -Match 'nosuch: failed to open for writing: No such file or directory'
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'sub')
        (Invoke-TestGnu shred 'sub' -WorkingDirectory $dir).ErrorText | Should -Match 'sub: failed to open for writing: Is a directory'
        (Invoke-TestGnu shred '-' -WorkingDirectory $dir).ErrorText | Should -Match 'shredding standard output is not supported'
    }

    It 'reports files that cannot be removed' {
        InModuleScope PSGnuUtils -Parameters @{ Dir = $dir } {
            param($Dir)
            $ctx = @{ Name = 'shred'; ExitCode = 0; ErrorCount = 0 }
            Mock Resolve-GnuPath { Join-Path $Dir 'locked\file' }
            Remove-GnuShreddedFile -Context $ctx -Operand 'gone' -How 'unlink' 2>&1 | ForEach-Object { "$_" } | Should -Match 'gone: failed to remove'
        }
    }
}
