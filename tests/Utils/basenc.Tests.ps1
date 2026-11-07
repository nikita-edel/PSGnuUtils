BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# Expected encodings come from GNU coreutils basenc.
Describe 'basenc' {
    BeforeAll {
        $script:bytes = New-TestFile -Path (Join-Path $TestDrive 'bytes.bin') -Bytes ([byte[]](0xFB, 0xFF, 0x3F))
        $script:z85 = New-TestFile -Path (Join-Path $TestDrive 'z85.bin') -Bytes ([byte[]](0x86, 0x4F, 0xD2, 0x6F, 0xB5, 0x59, 0xF7, 0x5B))
    }

    It 'encodes with <Option>' -ForEach @(
        @{ Option = '--base64'; Expected = '+/8/' }
        @{ Option = '--base64url'; Expected = '-_8_' }
        @{ Option = '--base32'; Expected = '7P7T6===' }
        @{ Option = '--base32hex'; Expected = 'VFVJU===' }
        @{ Option = '--base16'; Expected = 'FBFF3F' }
        @{ Option = '--base2msbf'; Expected = '111110111111111100111111' }
        @{ Option = '--base2lsbf'; Expected = '110111111111111111111100' }
    ) {
        $r = Invoke-TestGnu basenc $Option, $bytes
        $r.Output | Should -Be @($Expected)
        $r.ExitCode | Should -Be 0
    }

    It 'encodes Z85 with --z85 (length must be a multiple of 4)' {
        (Invoke-TestGnu basenc '--z85', $z85).Output | Should -Be @('HelloWorld')
        $r = Invoke-TestGnu basenc '--z85', $bytes
        $r.ErrorText | Should -Match 'invalid input \(length must be multiple of 4 characters\)'
        $r.ExitCode | Should -Be 1
    }

    It 'decodes with -d / --decode' {
        (Invoke-TestGnu basenc '--base64', '-d' -InputObject 'aGVsbG8K').Output | Should -Be @('hello')
        (Invoke-TestGnu basenc '--base64url', '--decode' -InputObject 'aGk_').Output | Should -Be @('hi?')
        (Invoke-TestGnu basenc '--base32', '-d' -InputObject 'NBSWY3DP').Output | Should -Be @('hello')
        (Invoke-TestGnu basenc '--base32hex', '-d' -InputObject 'D1IMOR3F').Output | Should -Be @('hello')
        (Invoke-TestGnu basenc '--base16', '-d' -InputObject '68656C6C6F', '6a6b').Output | Should -Be @('hellojk')
        (Invoke-TestGnu basenc '--base2msbf', '-d' -InputObject '0110100001101001').Output | Should -Be @('hi')
        (Invoke-TestGnu basenc '--base2lsbf', '-d' -InputObject '0001011010010110').Output | Should -Be @('hi')
        (Invoke-TestGnu basenc '--z85', '-d' -InputObject 'xLwRO').Output | Should -Be @('hi!?')
    }

    It 'ignores garbage with -i / --ignore-garbage' {
        (Invoke-TestGnu basenc '--base16', '-d', '-i' -InputObject '68*69').Output | Should -Be @('hi')
        (Invoke-TestGnu basenc '--base64', '-d', '--ignore-garbage' -InputObject 'aG*k=').Output | Should -Be @('hi')
    }

    It 'wraps with -w / --wrap' {
        (Invoke-TestGnu basenc '--base16', '-w', '4' -InputObject 'hello').Output | Should -Be @('6865', '6C6C', '6F0A')
        (Invoke-TestGnu basenc '--base2msbf', '--wrap=0' -InputObject ('x' * 20)).Output.Count | Should -Be 1
        (Invoke-TestGnu basenc '--base16', '-w', 'x' -InputObject 'a').ErrorText | Should -Match "invalid wrap size: 'x'"
    }

    It 'rejects invalid input when decoding' -ForEach @(
        @{ Option = '--base64'; Text = '-_8=' }
        @{ Option = '--base64'; Text = 'abc' }
        @{ Option = '--base64url'; Text = '+/8=' }
        @{ Option = '--base32'; Text = 'NBSWY3D' }
        @{ Option = '--base32hex'; Text = 'WXYZ====' }
        @{ Option = '--base16'; Text = '616' }
        @{ Option = '--base16'; Text = 'zz' }
        @{ Option = '--base2msbf'; Text = '0110000' }
        @{ Option = '--base2lsbf'; Text = '01100002' }
        @{ Option = '--z85'; Text = 'Hell' }
        @{ Option = '--z85'; Text = 'Hell~' }
        @{ Option = '--z85'; Text = '%%%%%' }
    ) {
        $r = Invoke-TestGnu basenc $Option, '-d' -InputObject $Text
        $r.ErrorText | Should -Match 'invalid input'
        $r.ExitCode | Should -Be 1
    }

    It 'needs an encoding and at most one file' {
        $r = Invoke-TestGnu basenc -InputObject 'a'
        $r.ErrorText | Should -Match 'missing encoding type'
        $r.ExitCode | Should -Be 1
        (Invoke-TestGnu basenc '--base64', 'a', 'b').ErrorText | Should -Match "extra operand 'b'"
        (Invoke-TestGnu basenc '--base64', (Join-Path $TestDrive 'nope')).ExitCode | Should -Be 1
        (Invoke-TestGnu basenc '--base64', '-d', (Join-Path $TestDrive 'nope')).ExitCode | Should -Be 1
    }

    It 'prints nothing for empty input' {
        $empty = New-TestFile -Path (Join-Path $TestDrive 'empty.bin') -Content ''
        (Invoke-TestGnu basenc '--base16', $empty).Output | Should -BeNullOrEmpty
    }
}
