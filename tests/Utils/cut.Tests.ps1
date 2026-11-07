BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'cut' {
    It 'selects TAB separated fields with -f / --fields' {
        $line = "a`tb`tc"
        (Invoke-TestGnu cut '-f', '2' -InputObject $line).Output | Should -Be @('b')
        (Invoke-TestGnu cut '-f', '1,3' -InputObject $line).Output | Should -Be @("a`tc")
        (Invoke-TestGnu cut '--fields=2-' -InputObject $line).Output | Should -Be @("b`tc")
        (Invoke-TestGnu cut '-f', '-2' -InputObject $line).Output | Should -Be @("a`tb")
        (Invoke-TestGnu cut '-f', '3,1-2' -InputObject $line).Output | Should -Be @("a`tb`tc")
        (Invoke-TestGnu cut '-f', '5' -InputObject $line).Output | Should -Be @('')
    }

    It 'uses a delimiter with -d / --delimiter and --output-delimiter' {
        (Invoke-TestGnu cut '-d', ',', '-f', '2' -InputObject 'x,y,z').Output | Should -Be @('y')
        (Invoke-TestGnu cut '--delimiter=:', '-f', '1,3', '--output-delimiter=;' -InputObject 'x:y:z').Output | Should -Be @('x;z')
        (Invoke-TestGnu cut '-d', '', '-f', '2' -InputObject "a`0b").Output | Should -Be @('b')
    }

    It 'prints lines without a delimiter unless -s / --only-delimited' {
        (Invoke-TestGnu cut '-d', ',', '-f', '2' -InputObject 'plain', 'a,b').Output | Should -Be @('plain', 'b')
        (Invoke-TestGnu cut '-s', '-d', ',', '-f', '2' -InputObject 'plain', 'a,b').Output | Should -Be @('b')
        (Invoke-TestGnu cut '--only-delimited', '-f', '1' -InputObject 'plain').Output.Count | Should -Be 0
    }

    It 'inverts the selection with --complement' {
        (Invoke-TestGnu cut '--complement', '-d', ',', '-f', '2' -InputObject 'x,y,z').Output | Should -Be @('x,z')
        (Invoke-TestGnu cut '--complement', '-c', '2' -InputObject 'abc').Output | Should -Be @('ac')
    }

    It 'selects characters with -c / --characters' {
        (Invoke-TestGnu cut '-c', '2-4' -InputObject 'hello').Output | Should -Be @('ell')
        (Invoke-TestGnu cut '--characters=1,3' -InputObject 'hello').Output | Should -Be @('hl')
        (Invoke-TestGnu cut '-c', '1,3', '--output-delimiter=:' -InputObject 'hello').Output | Should -Be @('h:l')
        $text = [string][char]0xE9 + 'x'
        (Invoke-TestGnu cut '-c', '1' -InputObject $text).Output | Should -Be @([string][char]0xE9)
        $emoji = [char]::ConvertFromUtf32(0x1F600)
        (Invoke-TestGnu cut '-c', '2' -InputObject ('a' + $emoji + 'b')).Output | Should -Be @($emoji)
    }

    It 'selects UTF-8 bytes with -b / --bytes' {
        $text = [string][char]0xE9 + 'x'
        (Invoke-TestGnu cut '-b', '1-2' -InputObject $text).Output | Should -Be @([string][char]0xE9)
        (Invoke-TestGnu cut '--bytes=3' -InputObject $text).Output | Should -Be @('x')
    }

    It 'ignores -n' {
        (Invoke-TestGnu cut '-n', '-b', '1' -InputObject 'ab').Output | Should -Be @('a')
    }

    It 'splits on NUL with -z / --zero-terminated' {
        $file = New-TestFile -Path (Join-Path $TestDrive 'z.txt') -Content "a,b`0c,d`0"
        (Invoke-TestGnu cut '-z', '-d', ',', '-f', '2', $file).Output | Should -Be @("b`0d`0")
        (Invoke-TestGnu cut '--zero-terminated', '-c', '1', $file).Output | Should -Be @("a`0c`0")
    }

    It 'reads files and reports missing ones' {
        $file = New-TestFile -Path (Join-Path $TestDrive 'f.csv') -Content "1,2`n3,4`n"
        (Invoke-TestGnu cut '-d', ',', '-f', '2', $file).Output | Should -Be @('2', '4')
        (Invoke-TestGnu cut '-f', '1', (Join-Path $TestDrive 'missing')).ErrorText | Should -Match 'No such file or directory'
    }

    It 'rejects invalid usage: <Message>' -ForEach @(
        @{ Arguments = @(); Message = 'you must specify a list of bytes, characters, or fields' }
        @{ Arguments = @('-c', '1', '-d', ','); Message = 'an input delimiter may be specified only when operating on fields' }
        @{ Arguments = @('-b', '1', '-s'); Message = 'suppressing non-delimited lines makes sense only when operating on fields' }
        @{ Arguments = @('-f', '1', '-d', ',,'); Message = 'the delimiter must be a single character' }
        @{ Arguments = @('-f', '0'); Message = 'fields are numbered from 1' }
        @{ Arguments = @('-b', '0'); Message = 'bytes are numbered from 1' }
        @{ Arguments = @('-f', '3-1'); Message = 'invalid decreasing range' }
        @{ Arguments = @('-f', 'x'); Message = "invalid field value 'x'" }
        @{ Arguments = @('-c', 'y'); Message = "invalid byte/character position value 'y'" }
        @{ Arguments = @('-b', '-'); Message = 'invalid range with no endpoint: -' }
    ) {
        $r = Invoke-TestGnu cut $Arguments -InputObject 'abc'
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match ([regex]::Escape($Message))
    }

    It 'renders pipeline objects before cutting them' {
        $r = Invoke-TestGnu cut '-c', '1-5' -InputObject ([pscustomobject]@{ Key = 'value1' })
        $r.Output | Should -Contain 'value'
    }

    It 'reads the console without pipeline input' {
        (Use-TestConsoleInput -Text "a,b`n" -Script { Invoke-TestGnu cut '-d', ',', '-f', '2' }).Output | Should -Be @('b')
    }
}
