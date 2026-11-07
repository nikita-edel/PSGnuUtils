BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# Expected CRC values come from GNU coreutils cksum.
Describe 'cksum' {
    BeforeAll {
        $script:dir = Join-Path $TestDrive 'cksum'
        $null = New-TestFile -Path (Join-Path $dir 'abc') -Content 'abc'
        $null = New-TestFile -Path (Join-Path $dir 'empty') -Content ''
        $null = New-TestFile -Path (Join-Path $dir 'big') -Content ('x' * 2000)
        $script:abc256 = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
    }

    It 'prints "CRC SIZE NAME" for every file' {
        $r = Invoke-TestGnu cksum 'abc', 'empty', 'big' -WorkingDirectory $dir
        $r.Output | Should -Be @('1219131554 3 abc', '4294967295 0 empty', '3989065734 2000 big')
        $r.ExitCode | Should -Be 0
    }

    It 'reads pipeline input without a name' {
        (Invoke-TestGnu cksum -InputObject 'hello').Output | Should -Be @('3015617425 6')
    }

    It 'selects the BSD and System V sums with -a' {
        (Invoke-TestGnu cksum '-a', 'bsd', 'abc' -WorkingDirectory $dir).Output | Should -Be @('16556     1 abc')
        (Invoke-TestGnu cksum '--algorithm=sysv', 'abc' -WorkingDirectory $dir).Output | Should -Be @('294 1 abc')
        (Invoke-TestGnu cksum '-a', 'crc', 'abc' -WorkingDirectory $dir).Output | Should -Be @('1219131554 3 abc')
    }

    It 'prints digests in BSD tag format (--tag), or untagged with --untagged' {
        (Invoke-TestGnu cksum '-a', 'sha256', 'abc' -WorkingDirectory $dir).Output | Should -Be @("SHA256 (abc) = $abc256")
        (Invoke-TestGnu cksum '-a', 'sha256', '--tag', 'abc' -WorkingDirectory $dir).Output | Should -Be @("SHA256 (abc) = $abc256")
        (Invoke-TestGnu cksum '-a', 'sha256', '--untagged', 'abc' -WorkingDirectory $dir).Output | Should -Be @("$abc256  abc")
        (Invoke-TestGnu cksum '-a', 'sha224', 'abc' -WorkingDirectory $dir).Output | Should -Be @('SHA224 (abc) = 23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7')
        (Invoke-TestGnu cksum '-a', 'md5' -InputObject 'hello').Output | Should -Be @('MD5 (-) = b1946ac92492d2347c6235b4d2611184')
    }

    It 'ends digest lines with NUL with -z / --zero' {
        (Invoke-TestGnu cksum '-a', 'sha256', '-z', 'abc' -WorkingDirectory $dir).Output | Should -Be @("SHA256 (abc) = $abc256`0")
        (Invoke-TestGnu cksum '-a', 'sha256', '--zero', 'abc' -WorkingDirectory $dir).Output | Should -Be @("SHA256 (abc) = $abc256`0")
    }

    It 'skips unreadable files' {
        $r = Invoke-TestGnu cksum '-a', 'sha256', 'nope', 'abc' -WorkingDirectory $dir
        $r.Output | Should -Be @("SHA256 (abc) = $abc256")
        $r.ExitCode | Should -Be 1
        $r = Invoke-TestGnu cksum 'nope' -WorkingDirectory $dir
        $r.ErrorText | Should -Match 'nope: No such file or directory'
        $r.ExitCode | Should -Be 1
    }

    It 'verifies digests with -c / --check and the check options' {
        $null = New-TestFile -Path (Join-Path $dir 'list') -Content "SHA256 (abc) = $abc256`nSHA256 (gone) = $abc256`n"
        $null = New-TestFile -Path (Join-Path $dir 'good') -Content "SHA256 (abc) = $abc256`nbroken line`n"
        (Invoke-TestGnu cksum '-a', 'sha256', '-c', 'good' -WorkingDirectory $dir).Output | Should -Be @('abc: OK')
        (Invoke-TestGnu cksum '-a', 'sha256', '--check', '--quiet', 'good' -WorkingDirectory $dir).Output | Should -BeNullOrEmpty
        $r = Invoke-TestGnu cksum '-a', 'sha256', '-c', '--status', 'list' -WorkingDirectory $dir
        $r.Output | Should -BeNullOrEmpty
        $r.ExitCode | Should -Be 1
        $r = Invoke-TestGnu cksum '-a', 'sha256', '-c', '--ignore-missing', 'list' -WorkingDirectory $dir
        $r.Output | Should -Be @('abc: OK')
        $r.ExitCode | Should -Be 0
        (Invoke-TestGnu cksum '-a', 'sha256', '-c', '-w', 'good' -WorkingDirectory $dir).WarningText | Should -Match 'improperly formatted'
        (Invoke-TestGnu cksum '-a', 'sha256', '-c', '--warn', '--strict', 'good' -WorkingDirectory $dir).ExitCode | Should -Be 1
    }

    It 'rejects --check with the CRC and sum algorithms' {
        $r = Invoke-TestGnu cksum '-c', 'abc' -WorkingDirectory $dir
        $r.ErrorText | Should -Match '--check is not supported'
        $r.ExitCode | Should -Be 1
    }

    It 'rejects unknown algorithms' {
        $r = Invoke-TestGnu cksum '-a', 'blake2b', 'abc' -WorkingDirectory $dir
        $r.ErrorText | Should -Match "invalid argument 'blake2b' for '--algorithm'"
        $r.ExitCode | Should -Be 1
    }
}
