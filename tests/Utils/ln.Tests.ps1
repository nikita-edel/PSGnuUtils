BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')

    function New-LnSandbox {
        $dir = Join-Path $TestDrive ('ln-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $null = New-TestFile -Path (Join-Path $dir 'a.txt') -Content 'A'
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'sub')
        $dir
    }

    # Real symbolic links need admin rights or developer mode on Windows.
    function Test-CanSymlink {
        $probe = Join-Path $TestDrive ('probe-' + [guid]::NewGuid().ToString('N'))
        try { $null = New-Item -ItemType SymbolicLink -Path $probe -Value $TestDrive -ErrorAction Stop; Remove-Item -LiteralPath $probe -Force; $true }
        catch { $false }
    }
}

Describe 'ln (hard links)' {
    It 'creates a hard link with the given name' {
        $dir = New-LnSandbox
        (Invoke-TestGnu ln 'a.txt', 'b.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        [System.IO.File]::WriteAllText((Join-Path $dir 'a.txt'), 'changed')
        [System.IO.File]::ReadAllText((Join-Path $dir 'b.txt')) | Should -Be 'changed'
    }

    It 'creates links in the current directory, in DIRECTORY and with -t / --target-directory' {
        $dir = New-LnSandbox
        (Invoke-TestGnu ln (Join-Path $dir 'a.txt') -WorkingDirectory (Join-Path $dir 'sub')).ExitCode | Should -Be 0
        Test-Path -LiteralPath (Join-Path $dir 'sub/a.txt') | Should -BeTrue
        $null = New-TestFile -Path (Join-Path $dir 'c.txt') -Content 'C'
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'd1'), (Join-Path $dir 'd2')
        (Invoke-TestGnu ln 'a.txt', 'c.txt', 'd1' -WorkingDirectory $dir).ExitCode | Should -Be 0
        @(Get-ChildItem -LiteralPath (Join-Path $dir 'd1')).Name | Should -Be @('a.txt', 'c.txt')
        (Invoke-TestGnu ln '-t', 'd2', 'a.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu ln '--target-directory=d2', 'c.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        @(Get-ChildItem -LiteralPath (Join-Path $dir 'd2')).Name | Should -Be @('a.txt', 'c.txt')
    }

    It 'refuses existing destinations unless -f / --force, asks with -i / --interactive' {
        $dir = New-LnSandbox
        $null = New-TestFile -Path (Join-Path $dir 'b.txt') -Content 'B'
        (Invoke-TestGnu ln 'a.txt', 'b.txt' -WorkingDirectory $dir).ErrorText | Should -BeExactly "ln: failed to create hard link 'b.txt' => 'a.txt': File exists"
        (Use-TestConsoleInput -Text "n`n" -Script { Invoke-TestGnu ln '-i', 'a.txt', 'b.txt' -WorkingDirectory $dir }).ConsoleError | Should -Match "ln: replace 'b.txt'\? "
        [System.IO.File]::ReadAllText((Join-Path $dir 'b.txt')) | Should -Be 'B'
        $null = Use-TestConsoleInput -Text "y`n" -Script { Invoke-TestGnu ln '--interactive', 'a.txt', 'b.txt' -WorkingDirectory $dir }
        [System.IO.File]::ReadAllText((Join-Path $dir 'b.txt')) | Should -Be 'A'
        $null = New-TestFile -Path (Join-Path $dir 'c.txt') -Content 'C'
        (Invoke-TestGnu ln '-f', 'a.txt', 'c.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu ln '--force', 'a.txt', 'c.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        [System.IO.File]::ReadAllText((Join-Path $dir 'c.txt')) | Should -Be 'A'
    }

    It 'treats the destination as a file with -T / --no-target-directory' {
        $dir = New-LnSandbox
        (Invoke-TestGnu ln '-T', 'a.txt', 'sub' -WorkingDirectory $dir).ErrorText | Should -Match 'File exists'
        (Invoke-TestGnu ln '--no-target-directory', '-f', 'a.txt', 'sub' -WorkingDirectory $dir).ErrorText | Should -Match 'sub: cannot overwrite directory'
        (Invoke-TestGnu ln '-T', 'a.txt', 'x', 'y' -WorkingDirectory $dir).ErrorText | Should -Match "extra operand 'y'"
    }

    It 'prints each link with -v / --verbose' {
        $dir = New-LnSandbox
        (Invoke-TestGnu ln '-v', 'a.txt', 'v1' -WorkingDirectory $dir).Output | Should -Be @("'v1' => 'a.txt'")
        (Invoke-TestGnu ln '--verbose', 'a.txt', 'v2' -WorkingDirectory $dir).Output | Should -Be @("'v2' => 'a.txt'")
    }

    It 'accepts -L / --logical and -P / --physical' {
        $dir = New-LnSandbox
        foreach ($option in @('-L', '--logical', '-P', '--physical')) {
            (Invoke-TestGnu ln $option, 'a.txt', ('p' + [guid]::NewGuid().ToString('N')) -WorkingDirectory $dir).ExitCode | Should -Be 0
        }
    }

    It 'reports errors' {
        $dir = New-LnSandbox
        (Invoke-TestGnu ln 'sub', 'subl' -WorkingDirectory $dir).ErrorText | Should -Match 'sub: hard link not allowed for directory'
        (Invoke-TestGnu ln 'missing', 'm' -WorkingDirectory $dir).ErrorText | Should -Match "failed to access 'missing': No such file or directory"
        (Invoke-TestGnu ln 'a.txt', 'a.txt' -WorkingDirectory $dir).ErrorText | Should -Match "'a.txt' and 'a.txt' are the same file"
        (Invoke-TestGnu ln 'a.txt', 'no/dir/x' -WorkingDirectory $dir).ErrorText | Should -Match "failed to create hard link 'no/dir/x' => 'a.txt'"
        (Invoke-TestGnu ln).ErrorText | Should -Match 'missing file operand'
        (Invoke-TestGnu ln 'a', 'b', 'c' -WorkingDirectory $dir).ErrorText | Should -Match "target 'c' is not a directory"
        (Invoke-TestGnu ln '-r', 'a.txt', 'r' -WorkingDirectory $dir).ErrorText | Should -Match 'cannot do --relative without --symbolic'
        (Invoke-TestGnu ln '-t', 'nodir', 'a.txt' -WorkingDirectory $dir).ErrorText | Should -Match "target directory 'nodir': No such file or directory"
        (Invoke-TestGnu ln '-t', 'a.txt', 'a.txt' -WorkingDirectory $dir).ErrorText | Should -Match "target directory 'a.txt': Not a directory"
        (Invoke-TestGnu ln '-t', 'sub' -WorkingDirectory $dir).ErrorText | Should -Match 'missing file operand'
        (Invoke-TestGnu ln '-t', 'sub', '-T', 'a.txt' -WorkingDirectory $dir).ErrorText | Should -Match 'cannot combine --target-directory'
    }
}

Describe 'ln -s (symbolic links)' {
    It 'stores the target as given, relative targets resolve from the link (mocked link creation)' {
        $dir = New-LnSandbox
        $global:PSGnuLinks = New-Object 'System.Collections.Generic.List[object]'
        try {
            Push-Location -LiteralPath $dir
            try {
                InModuleScope PSGnuUtils {
                    Mock New-GnuSymbolicLink { $global:PSGnuLinks.Add(@{ Path = $Path; Target = $Target; Directory = [bool]$Directory }) }
                    Invoke-GnuLn -s '../a.txt' 'sub/up' | Out-Null
                    Invoke-GnuLn --symbolic -v 'sub' 'dirlink'
                    Invoke-GnuLn -s -r 'a.txt' 'sub/rel' | Out-Null
                    Invoke-GnuLn -sr --relative 'sub' 'sub/self' | Out-Null
                } | Should -Be @("'dirlink' -> 'sub'")
            }
            finally { Pop-Location }
            $global:PSGnuLinks[0].Target | Should -Be '../a.txt'
            $global:PSGnuLinks[0].Directory | Should -BeFalse
            $global:PSGnuLinks[1].Directory | Should -BeTrue
            $global:PSGnuLinks[2].Target | Should -Be '../a.txt'
            $global:PSGnuLinks[3].Target | Should -Be '.'
        }
        finally { Remove-Variable -Name PSGnuLinks -Scope Global }
    }

    It 'creates real symbolic links or reports why it cannot' {
        $dir = New-LnSandbox
        $r = Invoke-TestGnu ln '-s', 'a.txt', 'sym' -WorkingDirectory $dir
        if (Test-CanSymlink) {
            $r.ExitCode | Should -Be 0
            [System.IO.File]::ReadAllText((Join-Path $dir 'sym')) | Should -Be 'A'
            (Invoke-TestGnu ln '-s', 'a.txt', 'sym' -WorkingDirectory $dir).ErrorText | Should -BeExactly "ln: failed to create symbolic link 'sym': File exists"
            (Invoke-TestGnu ln '-sf', 'sub', 'sym' -WorkingDirectory $dir).ExitCode | Should -Be 0
        }
        else {
            $r.ExitCode | Should -Be 1
            $r.ErrorText | Should -Match "failed to create symbolic link 'sym'"
        }
    }

    It 'replaces a link to a directory with -n / --no-dereference instead of linking inside it' {
        $dir = New-LnSandbox
        if (-not (New-TestDirectoryLink -Path (Join-Path $dir 'dlink') -Target (Join-Path $dir 'sub'))) { Set-ItResult -Skipped -Because 'directory links cannot be created here' }
        (Invoke-TestGnu ln '-n', '-f', 'a.txt', 'dlink' -WorkingDirectory $dir).ExitCode | Should -Be 0
        Test-Path -LiteralPath (Join-Path $dir 'sub/a.txt') | Should -BeFalse
        [System.IO.File]::ReadAllText((Join-Path $dir 'dlink')) | Should -Be 'A'
        $null = New-TestDirectoryLink -Path (Join-Path $dir 'dlink2') -Target (Join-Path $dir 'sub')
        (Invoke-TestGnu ln '--no-dereference', 'a.txt', 'dlink2' -WorkingDirectory $dir).ErrorText | Should -Match 'File exists'
    }
}

Describe 'Transfer helpers' {
    It 'computes relative paths' {
        InModuleScope PSGnuUtils {
            $base = [System.IO.Path]::GetTempPath()
            Get-GnuRelativePath -From (Join-Path $base 'a/b') -To (Join-Path $base 'a/c/d.txt') | Should -Be '../c/d.txt'
            Get-GnuRelativePath -From (Join-Path $base 'a') -To (Join-Path $base 'a') | Should -Be '.'
            if (Test-GnuWindows) { Get-GnuRelativePath -From 'C:\a' -To 'Z:\b' | Should -Be 'Z:\b' }
        }
    }

    It 'creates symbolic links through New-Item on runtimes without CreateSymbolicLink' {
        InModuleScope PSGnuUtils {
            Mock New-Item { }
            if ($null -eq [System.IO.File].GetMethod('CreateSymbolicLink')) {
                New-GnuSymbolicLink -Path 'x' -Target 'y'
                Should -Invoke New-Item -Times 1
            }
        }
    }
}
