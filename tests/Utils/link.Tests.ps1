BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'link' {
    It 'creates a hard link that shares the content' {
        $source = New-TestFile -Path (Join-Path $TestDrive 'source.txt') -Content 'shared'
        $target = Join-Path $TestDrive 'target.txt'
        $r = Invoke-TestGnu link $source, $target
        $r.ExitCode | Should -Be 0
        [System.IO.File]::ReadAllText($target) | Should -Be 'shared'
        [System.IO.File]::WriteAllText($source, 'changed')
        [System.IO.File]::ReadAllText($target) | Should -Be 'changed'
    }

    It 'refuses an existing target' {
        $source = New-TestFile -Path (Join-Path $TestDrive 'a.txt') -Content 'a'
        $existing = New-TestFile -Path (Join-Path $TestDrive 'b.txt') -Content 'b'
        $r = Invoke-TestGnu link $source, $existing
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match 'File exists'
    }

    It 'refuses missing sources and directories' {
        (Invoke-TestGnu link (Join-Path $TestDrive 'nope'), (Join-Path $TestDrive 'x')).ErrorText | Should -Match 'No such file or directory'
        (Invoke-TestGnu link $TestDrive, (Join-Path $TestDrive 'y')).ErrorText | Should -Match 'Operation not permitted'
    }

    It 'checks the operand count' {
        (Invoke-TestGnu link).ErrorText | Should -Match 'missing operand'
        (Invoke-TestGnu link 'a').ErrorText | Should -Match "missing operand after 'a'"
        (Invoke-TestGnu link 'a', 'b', 'c').ErrorText | Should -Match "extra operand 'c'"
    }
}
