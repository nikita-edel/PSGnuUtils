BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'readlink' {
    BeforeAll {
        $script:dir = Join-Path $TestDrive 'readlink'
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'real/sub') -Force
        $null = New-TestFile -Path (Join-Path $dir 'file.txt') -Content 'x'
        $script:base = InModuleScope PSGnuUtils -Parameters @{ Path = $dir } { param($Path) Resolve-GnuPhysicalPath -Path $Path }
        $script:sep = [string][System.IO.Path]::DirectorySeparatorChar
        $script:hasLink = New-TestDirectoryLink -Path (Join-Path $dir 'link') -Target (Join-Path $dir 'real')
    }

    It 'prints the target of a link' {
        if (-not $hasLink) { Set-ItResult -Skipped -Because 'links cannot be created here'; return }
        $r = Invoke-TestGnu readlink 'link' -WorkingDirectory $dir
        $r.Output | Should -Be @((Join-Path $dir 'real'))
        $r.ExitCode | Should -Be 0
    }

    It 'fails silently for files that are not links (-q / -s / --quiet / --silent are the default)' {
        foreach ($quiet in @(@(), @('-q'), @('-s'), @('--quiet'), @('--silent'))) {
            $r = Invoke-TestGnu readlink (@($quiet) + 'file.txt') -WorkingDirectory $dir
            $r.Output | Should -BeNullOrEmpty
            $r.Errors | Should -BeNullOrEmpty
            $r.ExitCode | Should -Be 1
        }
    }

    It 'reports errors with -v / --verbose' {
        (Invoke-TestGnu readlink '-v', 'file.txt' -WorkingDirectory $dir).ErrorText | Should -Match 'file.txt: Invalid argument'
        (Invoke-TestGnu readlink '--verbose', 'nope' -WorkingDirectory $dir).ErrorText | Should -Match 'nope: No such file or directory'
        (Invoke-TestGnu readlink '-v', '' -WorkingDirectory $dir).ErrorText | Should -Match ': No such file or directory'
    }

    It 'canonicalizes with -f / --canonicalize (all but the last component must exist)' {
        (Invoke-TestGnu readlink '-f', 'real/sub/../../file.txt' -WorkingDirectory $dir).Output | Should -Be @("$base$($sep)file.txt")
        (Invoke-TestGnu readlink '--canonicalize', 'real/new' -WorkingDirectory $dir).Output | Should -Be @("$base$($sep)real$($sep)new")
        (Invoke-TestGnu readlink '-f', 'no/new' -WorkingDirectory $dir).ExitCode | Should -Be 1
        (Invoke-TestGnu readlink '-f', '-v', 'file.txt/x' -WorkingDirectory $dir).ErrorText | Should -Match 'file.txt/x: Not a directory'
    }

    It 'resolves links with -f' {
        if (-not $hasLink) { Set-ItResult -Skipped -Because 'links cannot be created here'; return }
        (Invoke-TestGnu readlink '-f', 'link/sub' -WorkingDirectory $dir).Output | Should -Be @("$base$($sep)real$($sep)sub")
    }

    It 'requires every component with -e / --canonicalize-existing' {
        (Invoke-TestGnu readlink '-e', 'file.txt' -WorkingDirectory $dir).Output | Should -Be @("$base$($sep)file.txt")
        $r = Invoke-TestGnu readlink '--canonicalize-existing', '-v', 'new' -WorkingDirectory $dir
        $r.ErrorText | Should -Match 'new: No such file or directory'
        $r.ExitCode | Should -Be 1
    }

    It 'requires nothing with -m / --canonicalize-missing' {
        (Invoke-TestGnu readlink '-m', 'a/b/../c' -WorkingDirectory $dir).Output | Should -Be @("$base$($sep)a$($sep)c")
        (Invoke-TestGnu readlink '--canonicalize-missing', 'file.txt/x' -WorkingDirectory $dir).Output | Should -Be @("$base$($sep)file.txt$($sep)x")
    }

    It 'ends records with NUL with -z / --zero and accepts -n / --no-newline' {
        (Invoke-TestGnu readlink '-z', '-f', 'file.txt', 'real' -WorkingDirectory $dir).Output | Should -Be @("$base$($sep)file.txt`0$base$($sep)real`0")
        (Invoke-TestGnu readlink '--zero', '-f', 'file.txt' -WorkingDirectory $dir).Output | Should -Be @("$base$($sep)file.txt`0")
        (Invoke-TestGnu readlink '-n', '-f', 'file.txt' -WorkingDirectory $dir).Output | Should -Be @("$base$($sep)file.txt")
        (Invoke-TestGnu readlink '--no-newline', '-f', 'file.txt' -WorkingDirectory $dir).Output | Should -Be @("$base$($sep)file.txt")
    }

    It 'needs an operand' {
        $r = Invoke-TestGnu readlink
        $r.ErrorText | Should -Match 'missing operand'
        $r.ExitCode | Should -Be 1
    }
}
