BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')

    # Every test works inside its own folder under $TestDrive; nothing outside it is ever touched.
    function New-RmSandbox {
        $dir = Join-Path $TestDrive ('rm-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $null = New-Item -ItemType Directory -Path $dir
        $dir
    }
}

Describe 'rm' {
    It 'removes files and expands wildcards' {
        $dir = New-RmSandbox
        'a.tmp', 'b.tmp', 'keep.txt' | ForEach-Object { $null = New-TestFile -Path (Join-Path $dir $_) -Content 'x' }
        $r = Invoke-TestGnu rm '*.tmp' -WorkingDirectory $dir
        $r.ExitCode | Should -Be 0
        @(Get-ChildItem -LiteralPath $dir).Name | Should -Be @('keep.txt')
    }

    It 'reports missing files, silently skips them with -f / --force' {
        $dir = New-RmSandbox
        $r = Invoke-TestGnu rm 'missing' -WorkingDirectory $dir
        $r.ErrorText | Should -BeExactly "rm: cannot remove 'missing': No such file or directory"
        $r.ExitCode | Should -Be 1
        $r = Invoke-TestGnu rm '-f', 'missing' -WorkingDirectory $dir
        $r.Errors.Count | Should -Be 0
        $r.ExitCode | Should -Be 0
        (Invoke-TestGnu rm '--force' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu rm '').ErrorText | Should -Match "cannot remove '': No such file or directory"
    }

    It 'needs an operand without -f' {
        (Invoke-TestGnu rm).ErrorText | Should -Match 'missing operand'
    }

    It 'refuses directories without -r or -d' {
        $dir = New-RmSandbox
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'sub')
        (Invoke-TestGnu rm 'sub' -WorkingDirectory $dir).ErrorText | Should -BeExactly "rm: cannot remove 'sub': Is a directory"
        Test-Path -LiteralPath (Join-Path $dir 'sub') | Should -BeTrue
    }

    It 'removes empty directories with -d / --dir' {
        $dir = New-RmSandbox
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'empty'), (Join-Path $dir 'empty2'), (Join-Path $dir 'full')
        $null = New-TestFile -Path (Join-Path $dir 'full/x') -Content 'x'
        (Invoke-TestGnu rm '-d', 'empty' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu rm '--dir', 'empty2' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu rm '-d', 'full' -WorkingDirectory $dir).ErrorText | Should -Match "cannot remove 'full': Directory not empty"
        @(Get-ChildItem -LiteralPath $dir).Name | Should -Be @('full')
    }

    It 'removes trees with -r, -R and --recursive' {
        foreach ($option in @('-r', '-R', '--recursive')) {
            $dir = New-RmSandbox
            $null = New-TestFile -Path (Join-Path $dir 'tree/a/b/c.txt') -Content 'x'
            $null = New-TestFile -Path (Join-Path $dir 'tree/d.txt') -Content 'x'
            (Invoke-TestGnu rm $option, 'tree' -WorkingDirectory $dir).ExitCode | Should -Be 0
            Test-Path -LiteralPath (Join-Path $dir 'tree') | Should -BeFalse
        }
    }

    It 'explains what it does with -v / --verbose' {
        $dir = New-RmSandbox
        $null = New-TestFile -Path (Join-Path $dir 'tree/sub/x.txt') -Content 'x'
        $null = New-TestFile -Path (Join-Path $dir 'tree/a.txt') -Content 'x'
        $r = Invoke-TestGnu rm '-rv', 'tree' -WorkingDirectory $dir
        $r.Output | Should -Be @("removed 'tree/a.txt'", "removed 'tree/sub/x.txt'", "removed directory 'tree/sub'", "removed directory 'tree'")
        $null = New-TestFile -Path (Join-Path $dir 'f') -Content 'x'
        (Invoke-TestGnu rm '--verbose', 'f' -WorkingDirectory $dir).Output | Should -Be @("removed 'f'")
    }

    It 'removes read-only and hidden files' {
        $dir = New-RmSandbox
        $file = New-TestFile -Path (Join-Path $dir 'ro.txt') -Content 'x'
        (Get-Item -LiteralPath $file).IsReadOnly = $true
        $hidden = New-TestFile -Path (Join-Path $dir 'tree/.hidden') -Content 'x'
        if (Test-IsWindowsPlatform) { (Get-Item -LiteralPath $hidden -Force).Attributes = 'Hidden, ReadOnly' }
        (Invoke-TestGnu rm $file).ExitCode | Should -Be 0
        (Invoke-TestGnu rm '-r', (Join-Path $dir 'tree')).ExitCode | Should -Be 0
        @(Get-ChildItem -LiteralPath $dir -Force).Count | Should -Be 0
    }

    It 'removes links themselves and never their targets' {
        $dir = New-RmSandbox
        $target = Join-Path $dir 'precious'
        $null = New-TestFile -Path (Join-Path $target 'data.txt') -Content 'keep me'
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'tree')
        if (-not (New-TestDirectoryLink -Path (Join-Path $dir 'tree/link') -Target $target)) { Set-ItResult -Skipped -Because 'directory links cannot be created here' }
        if (-not (New-TestDirectoryLink -Path (Join-Path $dir 'toplink') -Target $target)) { Set-ItResult -Skipped -Because 'directory links cannot be created here' }

        (Invoke-TestGnu rm '-r', 'tree' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu rm 'toplink' -WorkingDirectory $dir).ExitCode | Should -Be 0
        Test-Path -LiteralPath (Join-Path $dir 'tree') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $dir 'toplink') | Should -BeFalse
        [System.IO.File]::ReadAllText((Join-Path $target 'data.txt')) | Should -Be 'keep me'
    }

    It 'names links as symbolic links in -i prompts' {
        $dir = New-RmSandbox
        $target = Join-Path $dir 'target'
        $null = New-Item -ItemType Directory -Path $target
        if (-not (New-TestDirectoryLink -Path (Join-Path $dir 'link') -Target $target)) { Set-ItResult -Skipped -Because 'directory links cannot be created here' }
        $r = Use-TestConsoleInput -Text "n`n" -Script { Invoke-TestGnu rm '-i', 'link' -WorkingDirectory $dir }
        $r.ConsoleError | Should -Match "rm: remove symbolic link 'link'\? "
        Test-Path -LiteralPath (Join-Path $dir 'link') | Should -BeTrue
    }

    It 'refuses . and .. with -r or -d' {
        $dir = New-RmSandbox
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'sub')
        $r = Invoke-TestGnu rm '-r', '.' -WorkingDirectory (Join-Path $dir 'sub')
        $r.ErrorText | Should -BeExactly "rm: refusing to remove '.' or '..' directory: skipping '.'"
        (Invoke-TestGnu rm '-d', '..' -WorkingDirectory (Join-Path $dir 'sub')).ErrorText | Should -Match "skipping '\.\.'"
        (Invoke-TestGnu rm '-rf', 'sub/..' -WorkingDirectory $dir).ErrorText | Should -Match "skipping 'sub/\.\.'"
        Test-Path -LiteralPath (Join-Path $dir 'sub') | Should -BeTrue
    }

    It 'protects roots unless --no-preserve-root (roots are simulated)' {
        $dir = New-RmSandbox
        $null = New-TestFile -Path (Join-Path $dir 'fake-root/x') -Content 'x'
        $fake = Join-Path $dir 'fake-root'
        $global:PSGnuTestRoot = $fake
        try {
            $r = InModuleScope PSGnuUtils {
                Mock Test-GnuRootPath { $Path -eq $global:PSGnuTestRoot }
                Invoke-GnuRm -r $global:PSGnuTestRoot 2>&1
                Invoke-GnuRm -r '--preserve-root' $global:PSGnuTestRoot 2>&1
                Invoke-GnuRm -r '--preserve-root=all' $global:PSGnuTestRoot 2>&1
            }
            "$r" | Should -Match 'it is dangerous to operate recursively on'
            "$r" | Should -Match 'use --no-preserve-root to override this failsafe'
            Test-Path -LiteralPath $fake | Should -BeTrue
            InModuleScope PSGnuUtils {
                Mock Test-GnuRootPath { $Path -eq $global:PSGnuTestRoot }
                Invoke-GnuRm -r '--no-preserve-root' $global:PSGnuTestRoot
            }
            Test-Path -LiteralPath $fake | Should -BeFalse
        }
        finally { Remove-Variable -Name PSGnuTestRoot -Scope Global }
    }

    It 'recognizes file system roots' {
        InModuleScope PSGnuUtils {
            Test-GnuRootPath -Path ([System.IO.Path]::GetPathRoot($PWD.ProviderPath)) | Should -BeTrue
            Test-GnuRootPath -Path $PWD.ProviderPath | Should -Be ($PWD.ProviderPath -eq [System.IO.Path]::GetPathRoot($PWD.ProviderPath))
            Test-GnuRootPath -Path (Join-Path ([System.IO.Path]::GetTempPath()) 'x') | Should -BeFalse
        }
    }

    It 'prompts for every removal with -i' {
        $dir = New-RmSandbox
        'yes.txt', 'no.txt' | ForEach-Object { $null = New-TestFile -Path (Join-Path $dir $_) -Content 'x' }
        $null = New-TestFile -Path (Join-Path $dir 'empty.txt') -Content ''
        $r = Use-TestConsoleInput -Text "n`ny`ny`n" -Script { Invoke-TestGnu rm '-i', 'no.txt', 'yes.txt', 'empty.txt' -WorkingDirectory $dir }
        $r.ConsoleError | Should -Match "rm: remove regular file 'no.txt'\? "
        $r.ConsoleError | Should -Match "rm: remove regular empty file 'empty.txt'\? "
        @(Get-ChildItem -LiteralPath $dir).Name | Should -Be @('no.txt')
    }

    It 'asks before descending into and removing directories with -i' {
        $dir = New-RmSandbox
        $null = New-TestFile -Path (Join-Path $dir 'tree/f') -Content 'x'
        $r = Use-TestConsoleInput -Text "y`ny`ny`n" -Script { Invoke-TestGnu rm '-ri', 'tree' -WorkingDirectory $dir }
        $r.ConsoleError | Should -Match "descend into directory 'tree'\?"
        $r.ConsoleError | Should -Match "remove directory 'tree'\?"
        Test-Path -LiteralPath (Join-Path $dir 'tree') | Should -BeFalse

        $null = New-TestFile -Path (Join-Path $dir 'tree2/f') -Content 'x'
        $null = Use-TestConsoleInput -Text "y`nn`n" -Script { Invoke-TestGnu rm '-ri', 'tree2' -WorkingDirectory $dir }
        Test-Path -LiteralPath (Join-Path $dir 'tree2/f') | Should -BeTrue

        $null = Use-TestConsoleInput -Text "n`n" -Script { Invoke-TestGnu rm '-ri', 'tree2' -WorkingDirectory $dir }
        Test-Path -LiteralPath (Join-Path $dir 'tree2/f') | Should -BeTrue

        $null = Use-TestConsoleInput -Text "y`ny`nn`n" -Script { Invoke-TestGnu rm '-ri', 'tree2' -WorkingDirectory $dir }
        Test-Path -LiteralPath (Join-Path $dir 'tree2') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $dir 'tree2/f') | Should -BeFalse
    }

    It 'asks once for more than three files or recursion with -I' {
        $dir = New-RmSandbox
        1..4 | ForEach-Object { $null = New-TestFile -Path (Join-Path $dir "$_.txt") -Content 'x' }
        $r = Use-TestConsoleInput -Text "n`n" -Script { Invoke-TestGnu rm '-I', '1.txt', '2.txt', '3.txt', '4.txt' -WorkingDirectory $dir }
        $r.ConsoleError | Should -Match 'rm: remove 4 arguments\? '
        @(Get-ChildItem -LiteralPath $dir).Count | Should -Be 4
        $null = Use-TestConsoleInput -Text "y`n" -Script { Invoke-TestGnu rm '-I', '1.txt', '2.txt', '3.txt', '4.txt' -WorkingDirectory $dir }
        @(Get-ChildItem -LiteralPath $dir).Count | Should -Be 0

        $null = New-TestFile -Path (Join-Path $dir 'tree/f') -Content 'x'
        $r = Use-TestConsoleInput -Text "y`n" -Script { Invoke-TestGnu rm '-I', '-r', 'tree' -WorkingDirectory $dir }
        $r.ConsoleError | Should -Match 'rm: remove 1 argument recursively\? '
        Test-Path -LiteralPath (Join-Path $dir 'tree') | Should -BeFalse

        $null = New-TestFile -Path (Join-Path $dir 'one.txt') -Content 'x'
        $r = Use-TestConsoleInput -Text '' -Script { Invoke-TestGnu rm '-I', 'one.txt' -WorkingDirectory $dir }
        $r.ConsoleError | Should -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $dir 'one.txt') | Should -BeFalse
    }

    It 'chooses prompting with --interactive=WHEN, and the last of -f / -i wins' {
        $dir = New-RmSandbox
        'a', 'b', 'c', 'd', 'e' | ForEach-Object { $null = New-TestFile -Path (Join-Path $dir $_) -Content 'x' }
        (Use-TestConsoleInput -Text "n`n" -Script { Invoke-TestGnu rm '--interactive', 'a' -WorkingDirectory $dir }).ConsoleError | Should -Match "remove regular file 'a'"
        (Use-TestConsoleInput -Text "n`n" -Script { Invoke-TestGnu rm '--interactive=always', 'a' -WorkingDirectory $dir }).ConsoleError | Should -Match "remove regular file 'a'"
        $null = Use-TestConsoleInput -Text '' -Script { Invoke-TestGnu rm '--interactive=never', 'a' -WorkingDirectory $dir }
        $null = Use-TestConsoleInput -Text '' -Script { Invoke-TestGnu rm '--interactive=once', 'b' -WorkingDirectory $dir }
        $null = Use-TestConsoleInput -Text '' -Script { Invoke-TestGnu rm '-i', '-f', 'c' -WorkingDirectory $dir }
        (Use-TestConsoleInput -Text "n`n" -Script { Invoke-TestGnu rm '-f', '-i', 'd' -WorkingDirectory $dir }).ConsoleError | Should -Match "remove regular file 'd'"
        @(Get-ChildItem -LiteralPath $dir).Name | Should -Be @('d', 'e')
        (Invoke-TestGnu rm '--interactive=sometimes', 'e' -WorkingDirectory $dir).ErrorText | Should -Match "invalid argument 'sometimes' for '--interactive'"
    }

    It 'accepts --one-file-system' {
        $dir = New-RmSandbox
        $null = New-TestFile -Path (Join-Path $dir 'tree/f') -Content 'x'
        (Invoke-TestGnu rm '-r', '--one-file-system', 'tree' -WorkingDirectory $dir).ExitCode | Should -Be 0
    }

    It 'removes file system objects from the pipeline and ignores other input' {
        $dir = New-RmSandbox
        'p1.log', 'p2.log' | ForEach-Object { $null = New-TestFile -Path (Join-Path $dir $_) -Content 'x' }
        $r = Invoke-TestGnu rm -InputObject @(Get-ChildItem -LiteralPath $dir -Filter '*.log')
        $r.ExitCode | Should -Be 0
        @(Get-ChildItem -LiteralPath $dir).Count | Should -Be 0
        $null = New-TestFile -Path (Join-Path $dir 'name') -Content 'x'
        (Invoke-TestGnu rm -InputObject 'name' -WorkingDirectory $dir).ErrorText | Should -Match 'missing operand'
        Test-Path -LiteralPath (Join-Path $dir 'name') | Should -BeTrue
    }

    It 'reports files that cannot be removed' {
        $dir = New-RmSandbox
        $file = New-TestFile -Path (Join-Path $dir 'locked.txt') -Content 'x'
        $lock = Lock-TestFile -Path $file
        if ($null -eq $lock) { Set-ItResult -Skipped -Because 'this OS does not enforce exclusive file locks' }
        try {
            $r = Invoke-TestGnu rm $file
            $r.ExitCode | Should -Be 1
            $r.ErrorText | Should -Match "cannot remove '.*locked.txt'"
        }
        finally { $lock.Dispose() }
    }

    It 'keeps a directory whose children could not be removed' {
        $dir = New-RmSandbox
        $file = New-TestFile -Path (Join-Path $dir 'tree/locked.txt') -Content 'x'
        $lock = Lock-TestFile -Path $file
        if ($null -eq $lock) { Set-ItResult -Skipped -Because 'this OS does not enforce exclusive file locks' }
        try {
            $r = Invoke-TestGnu rm '-r', 'tree' -WorkingDirectory $dir
            $r.ExitCode | Should -Be 1
            Test-Path -LiteralPath (Join-Path $dir 'tree') | Should -BeTrue
        }
        finally { $lock.Dispose() }
    }
}
