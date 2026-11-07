BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'base32' {
    BeforeAll {
        $script:file = New-TestFile -Path (Join-Path $TestDrive 'abc.txt') -Content 'abc'
    }

    It 'encodes files and pipeline input (lines end with LF)' {
        (Invoke-TestGnu base32 $file).Output | Should -Be @('MFRGG===')
        (Invoke-TestGnu base32 -InputObject 'hello').Output | Should -Be @('NBSWY3DPBI======')
    }

    It 'wraps encoded lines with -w / --wrap (0 disables wrapping)' {
        (Invoke-TestGnu base32 '-w', '8' -InputObject 'hello').Output | Should -Be @('NBSWY3DP', 'BI======')
        (Invoke-TestGnu base32 '--wrap=0' -InputObject ('x' * 100)).Output.Count | Should -Be 1
    }

    It 'decodes with -d / --decode' {
        (Invoke-TestGnu base32 '-d' -InputObject 'NBSWY3DPBI======').Output | Should -Be @('hello')
        (Invoke-TestGnu base32 '--decode' -InputObject 'NBSWY3DP', 'BI======').Output | Should -Be @('hello')
    }

    It 'ignores garbage with -i / --ignore-garbage' {
        (Invoke-TestGnu base32 '-d', '-i' -InputObject 'MFR*GG===').Output | Should -Be @('abc')
        (Invoke-TestGnu base32 '-d', '--ignore-garbage' -InputObject 'MF-RGG===').Output | Should -Be @('abc')
    }

    It 'rejects invalid input' {
        $r = Invoke-TestGnu base32 '-d' -InputObject 'MFRG'
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match 'invalid input'
    }
}
