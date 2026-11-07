BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'nl' {
    It 'numbers non-empty lines by default' {
        (Invoke-TestGnu nl -InputObject 'a', '', 'b').Output | Should -Be @("     1`ta", '       ', "     2`tb")
    }

    It 'selects body lines with -b / --body-numbering' {
        (Invoke-TestGnu nl '-ba' -InputObject 'a', '', 'b').Output | Should -Be @("     1`ta", "     2`t", "     3`tb")
        (Invoke-TestGnu nl '--body-numbering=n' -InputObject 'a').Output | Should -Be @('       a')
        (Invoke-TestGnu nl '-b', 'p^x' -InputObject 'xa', 'ya', 'xb').Output | Should -Be @("     1`txa", '       ya', "     2`txb")
    }

    It 'formats numbers with -n / --number-format and -w / --number-width' {
        (Invoke-TestGnu nl '-n', 'ln' -InputObject 'a').Output | Should -Be @("1     `ta")
        (Invoke-TestGnu nl '--number-format=rz' -InputObject 'a').Output | Should -Be @("000001`ta")
        (Invoke-TestGnu nl '-n', 'rn', '-w', '3' -InputObject 'a').Output | Should -Be @("  1`ta")
        (Invoke-TestGnu nl '--number-width=2', '-n', 'rz', '-v', '-3' -InputObject 'a').Output | Should -Be @("-3`ta")
    }

    It 'changes separator, start and increment with -s, -v and -i (and long forms)' {
        (Invoke-TestGnu nl '-s', ': ', '-v', '10', '-i', '5' -InputObject 'a', 'b').Output | Should -Be @('    10: a', '    15: b')
        (Invoke-TestGnu nl '--number-separator=|', '--starting-line-number=0', '--line-increment=2' -InputObject 'a', 'b').Output | Should -Be @('     0|a', '     2|b')
    }

    It 'counts groups of empty lines as one with -l / --join-blank-lines' {
        (Invoke-TestGnu nl '-ba', '-l', '2' -InputObject '', '', '', 'x').Output | Should -Be @('       ', "     1`t", '       ', "     2`tx")
        (Invoke-TestGnu nl '-ba', '--join-blank-lines=3' -InputObject '', '', '').Output | Should -Be @('       ', '       ', "     1`t")
    }

    It 'handles header, body and footer sections with -h / --header-numbering and -f / --footer-numbering' {
        $lines = '\:\:\:', 'head', '\:\:', 'body', '\:', 'foot'
        (Invoke-TestGnu nl '-ha', '-fa' -InputObject $lines).Output | Should -Be @('', "     1`thead", '', "     2`tbody", '', "     3`tfoot")
        (Invoke-TestGnu nl '--header-numbering=n', '--footer-numbering=t' -InputObject $lines).Output | Should -Be @('', '       head', '', "     1`tbody", '', "     2`tfoot")
    }

    It 'restarts numbering at each header unless -p / --no-renumber' {
        $pages = '\:\:\:', 'x', '\:\:\:', 'y'
        (Invoke-TestGnu nl '-ha' -InputObject $pages).Output | Should -Be @('', "     1`tx", '', "     1`ty")
        (Invoke-TestGnu nl '-ha', '-p' -InputObject $pages).Output | Should -Be @('', "     1`tx", '', "     2`ty")
        (Invoke-TestGnu nl '-ha', '--no-renumber' -InputObject $pages).Output[3] | Should -Be "     2`ty"
    }

    It 'uses custom section delimiters with -d / --section-delimiter' {
        (Invoke-TestGnu nl '-d', 'X', '-ha' -InputObject 'X:X:X:', 'h').Output | Should -Be @('', "     1`th")
        (Invoke-TestGnu nl '--section-delimiter=@#' -InputObject '@#@#', 'b').Output | Should -Be @('', "     1`tb")
        (Invoke-TestGnu nl '-d', '' -InputObject '\:\:').Output | Should -Be @("     1`t\:\:")
    }

    It 'numbers continuously across files' {
        $a = New-TestFile -Path (Join-Path $TestDrive 'a.txt') -Content "a`n"
        $b = New-TestFile -Path (Join-Path $TestDrive 'b.txt') -Content "b`n"
        (Invoke-TestGnu nl $a, $b).Output | Should -Be @("     1`ta", "     2`tb")
    }

    It 'rejects invalid arguments' -ForEach @(
        @{ Arguments = @('-b', 'z'); Message = "invalid body numbering style: 'z'" }
        @{ Arguments = @('-h', 'q'); Message = "invalid header numbering style: 'q'" }
        @{ Arguments = @('-f', 'q'); Message = "invalid footer numbering style: 'q'" }
        @{ Arguments = @('-n', 'xx'); Message = "invalid line numbering format: 'xx'" }
        @{ Arguments = @('-w', '0'); Message = "invalid line number field width: '0'" }
        @{ Arguments = @('-i', 'x'); Message = "invalid line number increment: 'x'" }
        @{ Arguments = @('-l', '0'); Message = "invalid line number of blank lines: '0'" }
        @{ Arguments = @('-v', 'x'); Message = "invalid starting line number: 'x'" }
    ) {
        $r = Invoke-TestGnu nl $Arguments -InputObject 'a'
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match ([regex]::Escape($Message))
    }
}
