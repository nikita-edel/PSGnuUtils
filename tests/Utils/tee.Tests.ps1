BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'tee' {
    It 'copies input to the output and to every file (UTF-8, LF)' {
        $r = Invoke-TestGnu tee 'one.txt', 'two.txt' -InputObject 'a', 'b' -WorkingDirectory $TestDrive
        $r.Output | Should -Be @('a', 'b')
        [System.IO.File]::ReadAllText((Join-Path $TestDrive 'one.txt')) | Should -BeExactly "a`nb`n"
        [System.IO.File]::ReadAllText((Join-Path $TestDrive 'two.txt')) | Should -BeExactly "a`nb`n"
    }

    It 'overwrites by default and appends with -a / --append' {
        $null = Invoke-TestGnu tee 'log.txt' -InputObject 'first' -WorkingDirectory $TestDrive
        $null = Invoke-TestGnu tee 'log.txt' -InputObject 'second' -WorkingDirectory $TestDrive
        [System.IO.File]::ReadAllText((Join-Path $TestDrive 'log.txt')) | Should -BeExactly "second`n"
        $null = Invoke-TestGnu tee '-a', 'log.txt' -InputObject 'third' -WorkingDirectory $TestDrive
        $null = Invoke-TestGnu tee '--append', 'log.txt' -InputObject 'fourth' -WorkingDirectory $TestDrive
        [System.IO.File]::ReadAllText((Join-Path $TestDrive 'log.txt')) | Should -BeExactly "second`nthird`nfourth`n"
    }

    It 'creates files even without input' {
        $null = Invoke-TestGnu tee 'empty.txt' -InputObject @() -WorkingDirectory $TestDrive
        (Get-Item -LiteralPath (Join-Path $TestDrive 'empty.txt')).Length | Should -Be 0
    }

    It 'writes formatted objects like the console shows them' {
        $r = Invoke-TestGnu tee 'objects.txt' -InputObject ([pscustomobject]@{ Key = 'k1' }) -WorkingDirectory $TestDrive
        $r.Text | Should -Match 'k1'
        [System.IO.File]::ReadAllText((Join-Path $TestDrive 'objects.txt')) | Should -Match 'k1'
    }

    It 'accepts -i / --ignore-interrupts, -p and --output-error' {
        foreach ($option in @('-i', '--ignore-interrupts', '-p', '--output-error', '--output-error=warn')) {
            $r = Invoke-TestGnu tee $option -InputObject 'x'
            $r.ExitCode | Should -Be 0
            $r.Output | Should -Be @('x')
        }
    }

    It 'reports files that cannot be opened and still copies to the others' {
        $r = Invoke-TestGnu tee 'no/such/dir/file.txt', 'ok.txt' -InputObject 'data' -WorkingDirectory $TestDrive
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match 'no/such/dir/file.txt: No such file or directory'
        $r.Output | Should -Be @('data')
        [System.IO.File]::ReadAllText((Join-Path $TestDrive 'ok.txt')) | Should -BeExactly "data`n"
    }
}
