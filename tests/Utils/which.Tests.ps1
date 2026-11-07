BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')

    # A fake PATH with one program in two directories (a .cmd on Windows, an executable script on Unix).
    function New-WhichFixture {
        $root = Join-Path $TestDrive ('which-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $first = Join-Path $root 'first'
        $second = Join-Path $root 'second'
        $name = 'gnutool'
        if (Test-IsWindowsPlatform) { $name = 'gnutool.cmd' }
        foreach ($directory in @($first, $second)) {
            $file = New-TestFile -Path (Join-Path $directory $name) -Content "echo hi`n"
            if (-not (Test-IsWindowsPlatform)) { & chmod +x $file }
        }
        $null = New-TestFile -Path (Join-Path $first 'plain.txt') -Content 'not a program'
        if (-not (Test-IsWindowsPlatform)) { $null = New-TestFile -Path (Join-Path $first 'noexec') -Content 'x' }
        @{ Root = $root; First = $first; Second = $second; Name = $name }
    }
}

Describe 'which' {
    BeforeEach {
        $script:savedPath = $env:PATH
        $script:fixture = New-WhichFixture
        $env:PATH = $fixture.First + [System.IO.Path]::PathSeparator + $fixture.Second
    }
    AfterEach {
        $env:PATH = $savedPath
    }

    It 'prints the first match in PATH' {
        $r = Invoke-TestGnu which 'gnutool'
        $r.Output | Should -Be @([System.IO.Path]::Combine($fixture.First, $fixture.Name))
        $r.ExitCode | Should -Be 0
    }

    It 'prints every match with -a / --all' {
        $expected = @([System.IO.Path]::Combine($fixture.First, $fixture.Name), [System.IO.Path]::Combine($fixture.Second, $fixture.Name))
        (Invoke-TestGnu which '-a', 'gnutool').Output | Should -Be $expected
        (Invoke-TestGnu which '--all', 'gnutool').Output | Should -Be $expected
    }

    It 'reports commands that are not found or not executable' {
        $r = Invoke-TestGnu which 'gnutool', 'plain', 'nothing', 'plain.txt'
        $r.Output.Count | Should -Be 1
        $r.ErrorText | Should -Match 'no plain.txt in \('
        $r.ErrorText | Should -Match 'no nothing in \('
        $r.ErrorText | Should -Match 'no plain in \('
        $r.ExitCode | Should -Be 1
        if (-not (Test-IsWindowsPlatform)) { (Invoke-TestGnu which 'noexec').ExitCode | Should -Be 1 }
    }

    It 'checks names with a directory part directly' {
        $direct = [System.IO.Path]::Combine($fixture.Second, 'gnutool')
        (Invoke-TestGnu which $direct).ExitCode | Should -Be 0
        (Invoke-TestGnu which ([System.IO.Path]::Combine($fixture.Second, 'missing'))).ExitCode | Should -Be 1
    }

    It 'skips and shows dot directories with --skip-dot / --show-dot' {
        $env:PATH = '.' + [System.IO.Path]::PathSeparator + $fixture.Second
        $local = Invoke-TestGnu which 'gnutool' -WorkingDirectory $fixture.First
        $local.Output | Should -Be @([System.IO.Path]::Combine($fixture.First, $fixture.Name))
        (Invoke-TestGnu which '--show-dot', 'gnutool' -WorkingDirectory $fixture.First).Output | Should -Be @([System.IO.Path]::Combine('.', $fixture.Name))
        (Invoke-TestGnu which '--skip-dot', 'gnutool' -WorkingDirectory $fixture.First).Output | Should -Be @([System.IO.Path]::Combine($fixture.Second, $fixture.Name))
    }

    It 'skips and shows home directories with --skip-tilde / --show-tilde' {
        $savedHome = $env:HOME
        try {
            $env:HOME = $fixture.Root
            (Invoke-TestGnu which '--skip-tilde', 'gnutool').ExitCode | Should -Be 1
            (Invoke-TestGnu which '--show-tilde', 'gnutool').Output[0] | Should -BeLike '~*gnutool*'
            Remove-Item Env:\HOME
            (Invoke-TestGnu which '--show-tilde', 'gnutool').ExitCode | Should -Be 0   # falls back to USERPROFILE
        }
        finally { $env:HOME = $savedHome }
    }

    It 'uses PATHEXT on Windows' {
        if (-not (Test-IsWindowsPlatform)) { Set-ItResult -Skipped -Because 'Windows only' }
        $savedExt = $env:PATHEXT
        try {
            $env:PATHEXT = '.EXE'
            (Invoke-TestGnu which 'gnutool').ExitCode | Should -Be 1
            Remove-Item Env:\PATHEXT
            (Invoke-TestGnu which 'gnutool').ExitCode | Should -Be 0
            (Invoke-TestGnu which 'gnutool.cmd').ExitCode | Should -Be 0
        }
        finally { $env:PATHEXT = $savedExt }
    }

    It 'needs an operand' {
        (Invoke-TestGnu which).ErrorText | Should -Match 'missing operand'
    }
}

Describe 'Test-GnuExecutable' {
    It 'checks the execute bits on Unix and trusts runtimes without mode support' {
        $file = New-TestFile -Path (Join-Path $TestDrive 'tool') -Content 'x'
        InModuleScope PSGnuUtils -Parameters @{ F = $file } {
            param($F)
            Mock Test-GnuWindows { $false }
            Mock Get-GnuUnixFileMode { 420 }      # 0644
            Test-GnuExecutable -Path $F | Should -BeFalse
            Mock Get-GnuUnixFileMode { 493 }      # 0755
            Test-GnuExecutable -Path $F | Should -BeTrue
            Mock Get-GnuUnixFileMode { }
            Test-GnuExecutable -Path $F | Should -BeTrue
            Test-GnuExecutable -Path ($F + '.missing') | Should -BeFalse
        }
    }

    It 'reads no Unix modes on Windows' {
        if (-not (Test-IsWindowsPlatform)) { Set-ItResult -Skipped -Because 'Windows only' }
        InModuleScope PSGnuUtils { Get-GnuUnixFileMode -Path $PSHOME } | Should -BeNullOrEmpty
    }


}
