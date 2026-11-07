BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'base64' {
    BeforeAll {
        $script:file = New-TestFile -Path (Join-Path $TestDrive 'abc.txt') -Content 'abc'
    }

    It 'encodes files and pipeline input (lines end with LF)' {
        (Invoke-TestGnu base64 $file).Output | Should -Be @('YWJj')
        (Invoke-TestGnu base64 -InputObject 'hello').Output | Should -Be @('aGVsbG8K')
    }

    It 'wraps encoded lines with -w / --wrap (0 disables wrapping)' {
        (Invoke-TestGnu base64 '-w', '4' -InputObject 'hello').Output | Should -Be @('aGVs', 'bG8K')
        $long = 'x' * 100
        (Invoke-TestGnu base64 -InputObject $long).Output[0].Length | Should -Be 76
        (Invoke-TestGnu base64 '--wrap=0' -InputObject $long).Output.Count | Should -Be 1
        (Invoke-TestGnu base64 '-w', 'x' -InputObject 'a').ErrorText | Should -Match "invalid wrap size: 'x'"
    }

    It 'decodes with -d / --decode' {
        (Invoke-TestGnu base64 '-d' -InputObject 'aGVsbG8K').Output | Should -Be @('hello')
        (Invoke-TestGnu base64 '--decode' -InputObject 'aGVs', 'bG8K').Output | Should -Be @('hello')
    }

    It 'ignores garbage with -i / --ignore-garbage' {
        (Invoke-TestGnu base64 '-d', '-i' -InputObject 'aG*Vs!bG8K').Output | Should -Be @('hello')
        (Invoke-TestGnu base64 '-d', '--ignore-garbage' -InputObject 'YW%Jj').Output | Should -Be @('abc')
    }

    It 'rejects invalid input' {
        $r = Invoke-TestGnu base64 '-d' -InputObject 'a*b'
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match 'invalid input'
    }

    It 'prints nothing for empty input' {
        (Invoke-TestGnu base64 -InputObject @()).Output.Count | Should -Be 0
    }

    It 'accepts at most one file' {
        (Invoke-TestGnu base64 'a', 'b').ErrorText | Should -Match "extra operand 'b'"
        (Invoke-TestGnu base64 (Join-Path $TestDrive 'missing')).ErrorText | Should -Match 'No such file or directory'
    }
}
