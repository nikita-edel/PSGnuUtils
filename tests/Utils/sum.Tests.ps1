BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# Expected values come from GNU coreutils sum.
Describe 'sum' {
    BeforeAll {
        $script:dir = Join-Path $TestDrive 'sum'
        $null = New-TestFile -Path (Join-Path $dir 'abc') -Content 'abc'
        $null = New-TestFile -Path (Join-Path $dir 'hello') -Content "hello`n"
        $null = New-TestFile -Path (Join-Path $dir 'big') -Content ('x' * 2000)
    }

    It 'prints the BSD checksum and 1K blocks, without the name for one file' {
        (Invoke-TestGnu sum 'abc' -WorkingDirectory $dir).Output | Should -Be @('16556     1')
        (Invoke-TestGnu sum 'big' -WorkingDirectory $dir).Output | Should -Be @('65279     2')
        (Invoke-TestGnu sum '-r', 'abc' -WorkingDirectory $dir).Output | Should -Be @('16556     1')
    }

    It 'prints names for several files' {
        (Invoke-TestGnu sum 'abc', 'hello' -WorkingDirectory $dir).Output | Should -Be @('16556     1 abc', '36979     1 hello')
    }

    It 'uses the System V algorithm with -s / --sysv (names for any file)' {
        (Invoke-TestGnu sum '-s', 'abc', 'hello', 'big' -WorkingDirectory $dir).Output | Should -Be @('294 1 abc', '542 1 hello', '43395 4 big')
        (Invoke-TestGnu sum '--sysv', 'abc' -WorkingDirectory $dir).Output | Should -Be @('294 1 abc')
    }

    It 'reads pipeline input without a name' {
        (Invoke-TestGnu sum -InputObject 'hello').Output | Should -Be @('36979     1')
        (Invoke-TestGnu sum '-s' -InputObject 'hello').Output | Should -Be @('542 1')
    }

    It 'reports missing files' {
        $r = Invoke-TestGnu sum 'nope', 'abc' -WorkingDirectory $dir
        $r.ErrorText | Should -Match 'nope: No such file or directory'
        $r.Output | Should -Be @('16556     1 abc')
        $r.ExitCode | Should -Be 1
    }
}
