BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# Every expected output below was produced by GNU coreutils od 8.32 for the same files.
Describe 'od' {
    BeforeAll {
        $script:dir = Join-Path $TestDrive 'od'
        $null = New-Item -ItemType Directory -Path $dir -Force
        $null = New-TestFile -Path (Join-Path $dir 'f') -Bytes ([byte[]](@([System.Text.Encoding]::ASCII.GetBytes("Hello, World!`n")) + @(0, 1, 255, 127) + @([System.Text.Encoding]::ASCII.GetBytes('abcdefghijklmnop'))))
        $null = New-TestFile -Path (Join-Path $dir 'a') -Content ('a' * 58)
        $null = New-TestFile -Path (Join-Path $dir 'fl') -Bytes ([byte[]](0, 0, 192, 127, 0, 0, 128, 127, 0, 0, 128, 255, 0, 0, 0, 128))
    }

    It 'prints <Arguments> like GNU' -ForEach @(
        @{ Arguments = @('f'); Expected = @('0000000 062510 066154 026157 053440 071157 062154 005041 000400', '0000020 077777 061141 062143 063145 064147 065151 066153 067155', '0000040 070157', '0000042') }
        @{ Arguments = @('-c', 'f'); Expected = @('0000000   H   e   l   l   o   ,       W   o   r   l   d   !  \n  \0 001', '0000020 377 177   a   b   c   d   e   f   g   h   i   j   k   l   m   n', '0000040   o   p', '0000042') }
        @{ Arguments = @('-A', 'x', '-t', 'x1z', 'f'); Expected = @('000000 48 65 6c 6c 6f 2c 20 57 6f 72 6c 64 21 0a 00 01  >Hello, World!...<', '000010 ff 7f 61 62 63 64 65 66 67 68 69 6a 6b 6c 6d 6e  >..abcdefghijklmn<', '000020 6f 70                                            >op<', '000022') }
        @{ Arguments = @('-t', 'd2', '-N', '8', 'f'); Expected = @('0000000  25928  27756  11375  22304', '0000010') }
        @{ Arguments = @('-j', '3', '-N', '4', '-c', 'f'); Expected = @('0000003   l   o   ,    ', '0000007') }
        @{ Arguments = @('-A', 'd', '-t', 'u1', '-w8', 'f'); Expected = @('0000000  72 101 108 108 111  44  32  87', '0000008 111 114 108 100  33  10   0   1', '0000016 255 127  97  98  99 100 101 102', '0000024 103 104 105 106 107 108 109 110', '0000032 111 112', '0000034') }
        @{ Arguments = @('-x', 'f'); Expected = @('0000000 6548 6c6c 2c6f 5720 726f 646c 0a21 0100', '0000020 7fff 6261 6463 6665 6867 6a69 6c6b 6e6d', '0000040 706f', '0000042') }
        @{ Arguments = @('-o', '-N', '4', 'f'); Expected = @('0000000 062510 066154', '0000004') }
        @{ Arguments = @('-d', '-N', '4', 'f'); Expected = @('0000000 25928 27756', '0000004') }
        @{ Arguments = @('-A', 'n', '-t', 'f4', '-N', '8', 'f'); Expected = @('   1.1431391e+27    1.761127e+14') }
        @{ Arguments = @('-t', 'a', '-N', '16', 'f'); Expected = @('0000000   H   e   l   l   o   ,  sp   W   o   r   l   d   !  nl nul soh', '0000020') }
        @{ Arguments = @('-c', 'a'); Expected = @('0000000   a   a   a   a   a   a   a   a   a   a   a   a   a   a   a   a', '*', '0000060   a   a   a   a   a   a   a   a   a   a', '0000072') }
        @{ Arguments = @('-v', '-c', 'a'); Expected = @('0000000   a   a   a   a   a   a   a   a   a   a   a   a   a   a   a   a', '0000020   a   a   a   a   a   a   a   a   a   a   a   a   a   a   a   a', '0000040   a   a   a   a   a   a   a   a   a   a   a   a   a   a   a   a', '0000060   a   a   a   a   a   a   a   a   a   a', '0000072') }
        @{ Arguments = @('-t', 'x4', 'f'); Expected = @('0000000 6c6c6548 57202c6f 646c726f 01000a21', '0000020 62617fff 66656463 6a696867 6e6d6c6b', '0000040 0000706f', '0000042') }
        @{ Arguments = @('-t', 'o8', '-N', '16', 'f'); Expected = @('0000000 0534401306755433062510 0004000242054433071157', '0000020') }
        @{ Arguments = @('--endian=big', '-t', 'x2', '-N', '4', 'f'); Expected = @('0000000 4865 6c6c', '0000004') }
        @{ Arguments = @('-t', 'f8', '-N', '16', 'f'); Expected = @('0000000   4.861994245760871e+111    7.30915479882693e-304', '0000020') }
        @{ Arguments = @('-A', 'n', '-t', 'f4', '-t', 'x1', '-N', '8', 'f'); Expected = @('   1.1431391e+27    1.761127e+14', '  48  65  6c  6c  6f  2c  20  57') }
        @{ Arguments = @('-t', 'x2', '-t', 'c', '-N', '8', 'f'); Expected = @('0000000    6548    6c6c    2c6f    5720', '          H   e   l   l   o   ,       W', '0000010') }
        @{ Arguments = @('-t', 'd1', '-t', 'o2', '-N', '4', 'f'); Expected = @('0000000   72  101  108  108', '           062510    066154', '0000004') }
        @{ Arguments = @('-t', 'u8', '-t', 'x8', '-N', '8', 'f'); Expected = @('0000000  6278066737626506568', '            57202c6f6c6c6548', '0000010') }
        @{ Arguments = @('-t', 'x1z', '-t', 'c', '-N', '6', 'f'); Expected = @('0000000  48  65  6c  6c  6f  2c                                          >Hello,<', '          H   e   l   l   o   ,', '0000006') }
        @{ Arguments = @('-w4', '-t', 'x1', '-N', '10', 'f'); Expected = @('0000000 48 65 6c 6c', '0000004 6f 2c 20 57', '0000010 6f 72', '0000012') }
        @{ Arguments = @('-t', 'd4', '-N', '8', 'f'); Expected = @('0000000  1819043144  1461726319', '0000010') }
        @{ Arguments = @('-t', 'uC', '-N', '3', 'f'); Expected = @('0000000  72 101 108', '0000003') }
        @{ Arguments = @('-t', 'dS', '-N', '4', 'f'); Expected = @('0000000  25928  27756', '0000004') }
        @{ Arguments = @('-t', 'xL', '-N', '8', 'f'); Expected = @('0000000 57202c6f6c6c6548', '0000010') }
        @{ Arguments = @('-t', 'fF', '-N', '4', 'f'); Expected = @('0000000   1.1431391e+27', '0000004') }
        @{ Arguments = @('-t', 'x2c', '-N', '4', 'f'); Expected = @('0000000    6548    6c6c', '          H   e   l   l', '0000004') }
        @{ Arguments = @('-t', 'f4', 'fl'); Expected = @('0000000             nan             inf            -inf              -0', '0000020') }
        @{ Arguments = @('-b', '-N', '4', 'f'); Expected = @('0000000 110 145 154 154', '0000004') }
        @{ Arguments = @('-a', '-x', '-N', '4', 'f'); Expected = @('0000000   H   e   l   l', '           6548    6c6c', '0000004') }
        @{ Arguments = @('-i', '-N', '8', 'f'); Expected = @('0000000  1819043144  1461726319', '0000010') }
        @{ Arguments = @('-l', '-N', '8', 'f'); Expected = @('0000000  6278066737626506568', '0000010') }
        @{ Arguments = @('-s', '-N', '4', 'f'); Expected = @('0000000  25928  27756', '0000004') }
        @{ Arguments = @('-f', '-N', '8', 'f'); Expected = @('0000000   1.1431391e+27    1.761127e+14', '0000010') }
        @{ Arguments = @('-w', '-t', 'x1', 'f'); Expected = @('0000000 48 65 6c 6c 6f 2c 20 57 6f 72 6c 64 21 0a 00 01 ff 7f 61 62 63 64 65 66 67 68 69 6a 6b 6c 6d 6e', '0000040 6f 70', '0000042') }
        @{ Arguments = @('-j', '0x2', '-N', '3', '-c', 'f'); Expected = @('0000002   l   l   o', '0000005') }
    ) {
        $r = Invoke-TestGnu od $Arguments -WorkingDirectory $dir
        $r.Errors | Should -BeNullOrEmpty
        $r.Output | Should -Be $Expected
    }

    It 'reads pipeline input and concatenates files' {
        (Invoke-TestGnu od '-c' -InputObject 'hi').Output | Should -Be @('0000000   h   i  \n', '0000003')
        (Invoke-TestGnu od '-t', 'a', '-j', '16', '-N', '2', 'f' -WorkingDirectory $dir).Output | Should -Be @('0000020 del del', '0000022')
        (Invoke-TestGnu od '-t', 'd1', '-t', 'd2', '-j', '16', '-N', '2', 'f' -WorkingDirectory $dir).Output | Should -Be @('0000020   -1  127', '            32767', '0000022')
        $r = Invoke-TestGnu od '-N', '2', 'f', 'nosuch' -WorkingDirectory $dir
        $r.Output | Should -Be @('0000000 062510', '0000002')
        $r.ExitCode | Should -Be 0
        (Invoke-TestGnu od '-A', 'n', '-t', 'x1', 'a', 'f', '-N', '60' -WorkingDirectory $dir).Output[-1] | Should -Be ' 61 61 61 61 61 61 61 61 61 61 48 65'
        (Invoke-TestGnu od '--address-radix=d', '--format=u1', '--read-bytes=2', '--skip-bytes=1', 'f' -WorkingDirectory $dir).Output | Should -Be @('0000001 101 108', '0000003')
        (Invoke-TestGnu od '--width=8', '--output-duplicates', '-c', '-N', '16', 'a' -WorkingDirectory $dir).Output.Count | Should -Be 3
        (Invoke-TestGnu od '-t', 'x1', '-N', '0x2', '-j', '010', 'f' -WorkingDirectory $dir).Output | Should -Be @('0000010 6f 72', '0000012')
        (Invoke-TestGnu od '-t', 'c', '-N', '1K', 'f' -WorkingDirectory $dir).Output[-1] | Should -Be '0000042'
    }

    It 'reports errors like GNU' {
        (Invoke-TestGnu od '-t', 'q', 'f' -WorkingDirectory $dir).ErrorText | Should -Be "od: invalid character 'q' in type string 'q'"
        (Invoke-TestGnu od '-t', 'd3', 'f' -WorkingDirectory $dir).ErrorText | Should -Be "od: invalid type string 'd3';`
this system doesn't provide a 3-byte integral type"
        (Invoke-TestGnu od '-t', 'f2', 'f' -WorkingDirectory $dir).ErrorText | Should -Match "doesn't provide a 2-byte floating point type"
        (Invoke-TestGnu od '-A', 'q', 'f' -WorkingDirectory $dir).ErrorText | Should -Be "od: invalid output address radix 'q'; it must be one character from [doxn]"
        (Invoke-TestGnu od '-j', '100', 'f' -WorkingDirectory $dir).ErrorText | Should -Be 'od: cannot skip past end of combined input'
        (Invoke-TestGnu od '-N', 'x', 'f' -WorkingDirectory $dir).ErrorText | Should -Match "invalid read bytes argument 'x'"
        (Invoke-TestGnu od '-wx', 'f' -WorkingDirectory $dir).ErrorText | Should -Match "invalid -w argument 'x'"
        (Invoke-TestGnu od '-w3', '-t', 'x2', 'f' -WorkingDirectory $dir).WarningText | Should -Match 'invalid width 3; using 2 instead'
        (Invoke-TestGnu od '--endian=middle', 'f' -WorkingDirectory $dir).ErrorText | Should -Match "invalid argument 'middle' for '--endian'"
        (Invoke-TestGnu od 'nosuch' -WorkingDirectory $dir).ExitCode | Should -Be 1
    }

    It 'prints shortest floats like ftoastr' {
        InModuleScope PSGnuUtils {
            Format-GnuOdFloat -Value 0.1 -Size 8 | Should -Be '0.1'
            Format-GnuOdFloat -Value ([double][float]0.1) -Size 4 | Should -Be '0.1'
            Format-GnuOdFloat -Value 0 -Size 8 | Should -Be '0'
            Format-GnuOdFloat -Value 5e-324 -Size 8 | Should -Be '5e-324'
            Format-GnuOdFloat -Value (0.1 + 0.2) -Size 8 | Should -Be '0.30000000000000004'
            Format-GnuOdFloat -Value 123456 -Size 8 | Should -Be '123456'
            Format-GnuOdFloat -Value 100 -Size 8 | Should -Be '100'
            Format-GnuOdFloat -Value -12.5 -Size 8 | Should -Be '-12.5'
            Format-GnuOdFloat -Value 1e-5 -Size 8 | Should -Be '1e-05'
            Format-GnuOdFloat -Value 0.0001234 -Size 8 | Should -Be '0.0001234'
        }
    }
}
