BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# Expected outputs come from GNU coreutils dircolors 8.32.
Describe 'dircolors' {
    BeforeAll {
        $script:prefix = 'rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:mi=00:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=34;42:st=37;44:ex=01;32:*.tar=01;31:'
        $script:suffix = '*.opus=00;36:*.spx=00;36:*.xspf=00;36:'
    }

    BeforeEach {
        $script:savedTerm = $env:TERM
        $script:savedShell = $env:SHELL
        $script:savedColorTerm = $env:COLORTERM
        $env:TERM = 'xterm'
        $env:COLORTERM = $null
    }

    AfterEach {
        $env:TERM = $savedTerm
        $env:SHELL = $savedShell
        $env:COLORTERM = $savedColorTerm
    }

    It 'prints Bourne shell code with -b / --sh / --bourne-shell' {
        $r = Invoke-TestGnu dircolors '-b'
        $r.Output.Count | Should -Be 2
        $r.Output[0] | Should -BeLike "LS_COLORS='$prefix*$suffix';"
        $r.Output[1] | Should -Be 'export LS_COLORS'
        (Invoke-TestGnu dircolors '--sh').Output[1] | Should -Be 'export LS_COLORS'
        (Invoke-TestGnu dircolors '--bourne-shell').Output[1] | Should -Be 'export LS_COLORS'
    }

    It 'prints C shell code with -c / --csh / --c-shell' {
        (Invoke-TestGnu dircolors '-c').Output | Should -BeLike "setenv LS_COLORS '$prefix*$suffix'"
        (Invoke-TestGnu dircolors '--csh').Output | Should -BeLike 'setenv LS_COLORS *'
        (Invoke-TestGnu dircolors '--c-shell').Output | Should -BeLike 'setenv LS_COLORS *'
    }

    It 'chooses the syntax from SHELL, or PowerShell without SHELL' {
        $env:SHELL = '/bin/tcsh'
        (Invoke-TestGnu dircolors).Output | Should -BeLike 'setenv LS_COLORS *'
        $env:SHELL = '/bin/bash'
        (Invoke-TestGnu dircolors).Output[1] | Should -Be 'export LS_COLORS'
        $env:SHELL = $null
        (Invoke-TestGnu dircolors).Output | Should -BeLike "`$env:LS_COLORS = '$prefix*'"
    }

    It 'prints no colors for terminals that are not listed' {
        $env:TERM = 'dumb'
        (Invoke-TestGnu dircolors '-c').Output | Should -Be @("setenv LS_COLORS ''")
    }

    It 'assumes a color terminal without TERM on Windows only' {
        $env:TERM = $null
        $expected = "setenv LS_COLORS ''"
        if (Test-IsWindowsPlatform) { $expected = "setenv LS_COLORS '$prefix*" }
        (Invoke-TestGnu dircolors '-c').Output | Should -BeLike $expected
    }

    It 'prints the database with -p / --print-database' {
        $r = Invoke-TestGnu dircolors '-p'
        $r.Output.Count | Should -Be 195
        $r.Output[0] | Should -Be '# Configuration file for dircolors, a utility to help you set the'
        $r.Output[-1] | Should -Be '.xspf 00;36'
        (Invoke-TestGnu dircolors '--print-database').Output.Count | Should -Be 195
    }

    It 'reads a database FILE' {
        $file = New-TestFile -Path (Join-Path $TestDrive 'colors') -Content "# mine`nTERM xterm*`nDIR 01;33 # dirs`n.log 00;31`n*README 01;37`nOPTIONS -F`nTERM dumb`nEXEC 01;32`n"
        (Invoke-TestGnu dircolors '-b', $file).Output[0] | Should -Be "LS_COLORS='di=01;33:*.log=00;31:*README=01;37:';"
        $odd = New-TestFile -Path (Join-Path $TestDrive 'odd') -Content "DIR 01;34`nBOGUS 1`nLONELY`nFILE it's`n"
        $r = Invoke-TestGnu dircolors '-c', $odd
        $r.Output | Should -Be @("setenv LS_COLORS 'di=01;34:fi=it'\''s:'")
        $r.Errors | Should -Contain "dircolors: $($odd):2: unrecognized keyword BOGUS"
        $r.Errors | Should -Contain "dircolors: $($odd):3: invalid line;  missing second token"
        $env:SHELL = $null
        (Invoke-TestGnu dircolors $odd).Output | Should -Be @("`$env:LS_COLORS = 'di=01;34:fi=it''s:'")
        (Invoke-TestGnu dircolors (Join-Path $TestDrive 'nope')).ExitCode | Should -Be 1
    }

    It 'matches COLORTERM entries' {
        $file = New-TestFile -Path (Join-Path $TestDrive 'colorterm') -Content "COLORTERM ?*`nDIR 01;35`n"
        $env:TERM = 'dumb'
        (Invoke-TestGnu dircolors '-c', $file).Output | Should -Be @("setenv LS_COLORS ''")
        $env:COLORTERM = 'truecolor'
        (Invoke-TestGnu dircolors '-c', $file).Output | Should -Be @("setenv LS_COLORS 'di=01;35:'")
    }

    It 'rejects invalid combinations' {
        (Invoke-TestGnu dircolors '-p', '-b').ErrorText | Should -Match 'mutually exclusive'
        (Invoke-TestGnu dircolors '-p', 'x').ErrorText | Should -Match 'file operands cannot be combined with --print-database'
        (Invoke-TestGnu dircolors 'a', 'b').ErrorText | Should -Match "extra operand 'b'"
    }
}
