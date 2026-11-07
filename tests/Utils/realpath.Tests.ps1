BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'realpath' {
    BeforeAll {
        $script:dir = Join-Path $TestDrive 'realpath'
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'real/sub') -Force
        $null = New-TestFile -Path (Join-Path $dir 'file.txt') -Content 'x'
        $script:base = InModuleScope PSGnuUtils -Parameters @{ Path = $dir } { param($Path) Resolve-GnuPhysicalPath -Path $Path }
        $script:sep = [string][System.IO.Path]::DirectorySeparatorChar
        $script:hasLink = New-TestDirectoryLink -Path (Join-Path $dir 'link') -Target (Join-Path $dir 'real')
    }

    It 'prints absolute paths without . and ..' {
        $r = Invoke-TestGnu realpath 'file.txt', 'real/sub/../.', 'new' -WorkingDirectory $dir
        $r.Output | Should -Be @("$base$($sep)file.txt", "$base$($sep)real", "$base$($sep)new")
        $r.ExitCode | Should -Be 0
    }

    It 'requires all but the last component by default' {
        $r = Invoke-TestGnu realpath 'no/new', 'file.txt' -WorkingDirectory $dir
        $r.ErrorText | Should -Match 'no/new: No such file or directory'
        $r.Output | Should -Be @("$base$($sep)file.txt")
        $r.ExitCode | Should -Be 1
        (Invoke-TestGnu realpath 'file.txt/x' -WorkingDirectory $dir).ErrorText | Should -Match 'file.txt/x: Not a directory'
        (Invoke-TestGnu realpath '' -WorkingDirectory $dir).ErrorText | Should -Match ': No such file or directory'
    }

    It 'suppresses messages with -q / --quiet' {
        foreach ($quiet in '-q', '--quiet') {
            $r = Invoke-TestGnu realpath $quiet, 'no/new' -WorkingDirectory $dir
            $r.Errors | Should -BeNullOrEmpty
            $r.ExitCode | Should -Be 1
        }
    }

    It 'requires every component with -e / --canonicalize-existing' {
        (Invoke-TestGnu realpath '-e', 'new' -WorkingDirectory $dir).ExitCode | Should -Be 1
        (Invoke-TestGnu realpath '--canonicalize-existing', 'file.txt' -WorkingDirectory $dir).Output | Should -Be @("$base$($sep)file.txt")
    }

    It 'requires nothing with -m / --canonicalize-missing' {
        (Invoke-TestGnu realpath '-m', 'a/b/../c' -WorkingDirectory $dir).Output | Should -Be @("$base$($sep)a$($sep)c")
        (Invoke-TestGnu realpath '--canonicalize-missing', 'x/y' -WorkingDirectory $dir).Output | Should -Be @("$base$($sep)x$($sep)y")
    }

    It 'resolves links unless -s / --strip / --no-symlinks; -L / -P / --logical / --physical are accepted' {
        if (-not $hasLink) { Set-ItResult -Skipped -Because 'links cannot be created here'; return }
        (Invoke-TestGnu realpath 'link/sub' -WorkingDirectory $dir).Output | Should -Be @("$base$($sep)real$($sep)sub")
        foreach ($option in '-P', '--physical', '-L', '--logical') {
            (Invoke-TestGnu realpath $option, 'link' -WorkingDirectory $dir).Output | Should -Be @("$base$($sep)real")
        }
        foreach ($option in '-s', '--strip', '--no-symlinks') {
            (Invoke-TestGnu realpath $option, (Join-Path $dir 'link/sub')).Output | Should -Be @((Join-Path $dir "link$($sep)sub"))
        }
    }

    It 'prints relative paths with --relative-to' {
        (Invoke-TestGnu realpath '--relative-to=real/sub', 'file.txt' -WorkingDirectory $dir).Output | Should -Be @("..$($sep)..$($sep)file.txt")
        (Invoke-TestGnu realpath '--relative-to', '.', 'real' -WorkingDirectory $dir).Output | Should -Be @('real')
        (Invoke-TestGnu realpath '--relative-to=.', '.' -WorkingDirectory $dir).Output | Should -Be @('.')
        $r = Invoke-TestGnu realpath '--relative-to=no/such', 'file.txt' -WorkingDirectory $dir
        $r.ErrorText | Should -Match 'no/such: No such file or directory'
        $r.ExitCode | Should -Be 1
    }

    It 'prints relative paths only below --relative-base' {
        (Invoke-TestGnu realpath '--relative-base=real', 'real/sub', 'file.txt' -WorkingDirectory $dir).Output | Should -Be @('sub', "$base$($sep)file.txt")
        (Invoke-TestGnu realpath '--relative-base=.', '--relative-to=real', 'real/sub' -WorkingDirectory $dir).Output | Should -Be @('sub')
        # --relative-to outside --relative-base: every path stays absolute.
        (Invoke-TestGnu realpath '--relative-base=real', '--relative-to=.', 'real/sub' -WorkingDirectory $dir).Output | Should -Be @("$base$($sep)real$($sep)sub")
    }

    It 'ends records with NUL with -z / --zero' {
        (Invoke-TestGnu realpath '-z', 'file.txt', 'real' -WorkingDirectory $dir).Output | Should -Be @("$base$($sep)file.txt`0$base$($sep)real`0")
        (Invoke-TestGnu realpath '--zero', 'file.txt' -WorkingDirectory $dir).Output | Should -Be @("$base$($sep)file.txt`0")
    }

    It 'needs an operand' {
        $r = Invoke-TestGnu realpath
        $r.ErrorText | Should -Match 'missing operand'
        $r.ExitCode | Should -Be 1
    }
}
