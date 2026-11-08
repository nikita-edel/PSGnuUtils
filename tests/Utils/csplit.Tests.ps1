BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')

    function New-CsplitDirectory {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $null = New-Item -ItemType Directory -Path $dir
        $null = New-TestFile -Path (Join-Path $dir 'n') -Content ((1..20 | ForEach-Object { "$_`n" }) -join '')
        $null = New-TestFile -Path (Join-Path $dir 's') -Content "intro`n== A`na1`na2`n== B`nb1`n== C`nc1`nc2`n"
        $dir
    }

    function Get-CsplitFile {
        param([string]$Directory)
        @(Get-ChildItem -LiteralPath $Directory -File | Where-Object { @('n', 's') -notcontains $_.Name } | Sort-Object -Property Name |
                ForEach-Object { $_.Name + ':' + [System.IO.File]::ReadAllText($_.FullName).Replace("`n", ',') })
    }
}

# Every expected result below was produced by GNU coreutils csplit 8.32 with the same input files.
Describe 'csplit' {
    It 'csplit <Arguments>' -ForEach @(
        @{ Arguments = @('n', '5', '10'); Output = @('8', '10', '33'); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('xx00:1,2,3,4,', 'xx01:5,6,7,8,9,', 'xx02:10,11,12,13,14,15,16,17,18,19,20,') }
        @{ Arguments = @('n', '5', '5'); Output = @('8', '0', '43'); Errors = @(); Warnings = @('csplit: warning: line number ''5'' is the same as preceding line number'); ExitCode = 0; Files = @('xx00:1,2,3,4,', 'xx01:', 'xx02:5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,') }
        @{ Arguments = @('n', '25'); Output = @('51'); Errors = @('csplit: ''25'': line number out of range'); Warnings = @(); ExitCode = 1; Files = @() }
        @{ Arguments = @('-k', 'n', '5', '25'); Output = @('8', '43'); Errors = @('csplit: ''25'': line number out of range'); Warnings = @(); ExitCode = 1; Files = @('xx00:1,2,3,4,', 'xx01:5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,') }
        @{ Arguments = @('n', '/3/', '/7/'); Output = @('4', '8', '39'); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('xx00:1,2,', 'xx01:3,4,5,6,', 'xx02:7,8,9,10,11,12,13,14,15,16,17,18,19,20,') }
        @{ Arguments = @('n', '/3/+1', '/7/-1'); Output = @('6', '4', '41'); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('xx00:1,2,3,', 'xx01:4,5,', 'xx02:6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,') }
        @{ Arguments = @('n', '%5%', '/8/'); Output = @('6', '37'); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('xx00:5,6,7,', 'xx01:8,9,10,11,12,13,14,15,16,17,18,19,20,') }
        @{ Arguments = @('s', '/^==/', '{*}'); Output = @('6', '11', '8', '11'); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('xx00:intro,', 'xx01:== A,a1,a2,', 'xx02:== B,b1,', 'xx03:== C,c1,c2,') }
        @{ Arguments = @('s', '/^==/', '{1}'); Output = @('6', '11', '19'); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('xx00:intro,', 'xx01:== A,a1,a2,', 'xx02:== B,b1,== C,c1,c2,') }
        @{ Arguments = @('s', '/^==/', '{5}'); Output = @('6', '11', '8', '11'); Errors = @('csplit: ''/^==/'': match not found on repetition 3'); Warnings = @(); ExitCode = 1; Files = @() }
        @{ Arguments = @('-k', 's', '/^==/', '{5}'); Output = @('6', '11', '8', '11'); Errors = @('csplit: ''/^==/'': match not found on repetition 3'); Warnings = @(); ExitCode = 1; Files = @('xx00:intro,', 'xx01:== A,a1,a2,', 'xx02:== B,b1,', 'xx03:== C,c1,c2,') }
        @{ Arguments = @('-z', 's', '/^==/', '{*}'); Output = @('6', '11', '8', '11'); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('xx00:intro,', 'xx01:== A,a1,a2,', 'xx02:== B,b1,', 'xx03:== C,c1,c2,') }
        @{ Arguments = @('-s', 'n', '5'); Output = @(); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('xx00:1,2,3,4,', 'xx01:5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,') }
        @{ Arguments = @('-q', 'n', '5'); Output = @(); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('xx00:1,2,3,4,', 'xx01:5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,') }
        @{ Arguments = @('-f', 'pre', '-n', '3', 'n', '5'); Output = @('8', '43'); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('pre000:1,2,3,4,', 'pre001:5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,') }
        @{ Arguments = @('-b', 'part%03d.txt', 'n', '5'); Output = @('8', '43'); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('xxpart000.txt:1,2,3,4,', 'xxpart001.txt:5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,') }
        @{ Arguments = @('--suppress-matched', 's', '/^==/', '{*}'); Output = @('6', '6', '3', '6'); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('xx00:intro,', 'xx01:a1,a2,', 'xx02:b1,', 'xx03:c1,c2,') }
        @{ Arguments = @('n', '10', '5'); Output = @(); Errors = @('csplit: line number ''5'' is smaller than preceding line number, 10'); Warnings = @(); ExitCode = 1; Files = @() }
        @{ Arguments = @('n', '/nomatch/'); Output = @('51'); Errors = @('csplit: ''/nomatch/'': match not found'); Warnings = @(); ExitCode = 1; Files = @() }
        @{ Arguments = @('n', 'x'); Output = @(); Errors = @('csplit: ''x'': invalid pattern'); Warnings = @(); ExitCode = 1; Files = @() }
        @{ Arguments = @('n', '/[/'); Output = @(); Errors = @('csplit: ''/[/'': invalid regular expression: Invalid regular expression'); Warnings = @(); ExitCode = 1; Files = @() }
        @{ Arguments = @('n', '0'); Output = @(); Errors = @('csplit: 0: line number must be greater than zero'); Warnings = @(); ExitCode = 1; Files = @() }
        @{ Arguments = @('n'); Output = @(); Errors = @('csplit: missing operand after ''n'''); Warnings = @(); ExitCode = 1; Files = @() }
        @{ Arguments = @('-b', '%x', 'n', '5', '15'); Output = @('8', '25', '18'); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('xx0:1,2,3,4,', 'xx1:5,6,7,8,9,10,11,12,13,14,', 'xx2:15,16,17,18,19,20,') }
        @{ Arguments = @('--elide-empty-files', 's', '/intro/'); Output = @('36'); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('xx00:intro,== A,a1,a2,== B,b1,== C,c1,c2,') }
        @{ Arguments = @('n', '/1/', '{*}'); Output = @('0', '18', '3', '3', '3', '3', '3', '3', '3', '3', '3', '6'); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('xx00:', 'xx01:1,2,3,4,5,6,7,8,9,', 'xx02:10,', 'xx03:11,', 'xx04:12,', 'xx05:13,', 'xx06:14,', 'xx07:15,', 'xx08:16,', 'xx09:17,', 'xx10:18,', 'xx11:19,20,') }
        @{ Arguments = @('n', '3', '{2}'); Output = @('4', '6', '6', '35'); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('xx00:1,2,', 'xx01:3,4,5,', 'xx02:6,7,8,', 'xx03:9,10,11,12,13,14,15,16,17,18,19,20,') }
        @{ Arguments = @('--prefix=P', '--digits=1', '--quiet', 'n', '5'); Output = @(); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('P0:1,2,3,4,', 'P1:5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,') }
        @{ Arguments = @('--keep-files', '--silent', 'n', '30'); Output = @(); Errors = @('csplit: ''30'': line number out of range'); Warnings = @(); ExitCode = 1; Files = @('xx00:1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,') }
        @{ Arguments = @('n', '%3%'); Output = @('47'); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('xx00:3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,') }
        @{ Arguments = @('-z', 'n', '/1/', '{*}'); Output = @('18', '3', '3', '3', '3', '3', '3', '3', '3', '3', '6'); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('xx00:1,2,3,4,5,6,7,8,9,', 'xx01:10,', 'xx02:11,', 'xx03:12,', 'xx04:13,', 'xx05:14,', 'xx06:15,', 'xx07:16,', 'xx08:17,', 'xx09:18,', 'xx10:19,20,') }
        @{ Arguments = @('n', '/5/-10'); Output = @('51'); Errors = @('csplit: ''/5/-10'': line number out of range'); Warnings = @(); ExitCode = 1; Files = @() }
        @{ Arguments = @('n', '/5/+30'); Output = @('51'); Errors = @('csplit: ''/5/+30'': line number out of range'); Warnings = @(); ExitCode = 1; Files = @() }
        @{ Arguments = @('n', '/5/', '/3/'); Output = @('8', '19', '24'); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('xx00:1,2,3,4,', 'xx01:5,6,7,8,9,10,11,12,', 'xx02:13,14,15,16,17,18,19,20,') }
        @{ Arguments = @('--suppress-matched', 'n', '5', '10'); Output = @('8', '8', '30'); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('xx00:1,2,3,4,', 'xx01:6,7,8,9,', 'xx02:11,12,13,14,15,16,17,18,19,20,') }
        @{ Arguments = @('-b', '%d%d', 'n', '5'); Output = @(); Errors = @('csplit: too many % conversion specifications in suffix'); Warnings = @(); ExitCode = 1; Files = @() }
        @{ Arguments = @('-b', 'abc', 'n', '5'); Output = @(); Errors = @('csplit: missing % conversion specification in suffix'); Warnings = @(); ExitCode = 1; Files = @() }
        @{ Arguments = @('-b', '%s', 'n', '5'); Output = @(); Errors = @('csplit: invalid conversion specifier in suffix: s'); Warnings = @(); ExitCode = 1; Files = @() }
        @{ Arguments = @('-n', 'x', 'n', '5'); Output = @(); Errors = @('csplit: invalid number: ''x'''); Warnings = @(); ExitCode = 1; Files = @() }
        @{ Arguments = @('n', '{2}'); Output = @(); Errors = @('csplit: ''{2}'': invalid pattern'); Warnings = @(); ExitCode = 1; Files = @() }
        @{ Arguments = @('n', '5', '{x}'); Output = @(); Errors = @('csplit: ''{x''}: integer required between ''{'' and ''}'''); Warnings = @(); ExitCode = 1; Files = @() }
        @{ Arguments = @('n', '/a'); Output = @(); Errors = @('csplit: /a: closing delimiter ''/'' missing'); Warnings = @(); ExitCode = 1; Files = @() }
        @{ Arguments = @('n', '5', '/5/'); Output = @('8', '0', '43'); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('xx00:1,2,3,4,', 'xx01:', 'xx02:5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,') }
        @{ Arguments = @('n', '/5/', '5'); Output = @('8', '0', '43'); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('xx00:1,2,3,4,', 'xx01:', 'xx02:5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,') }
        @{ Arguments = @('n', '21'); Output = @('51'); Errors = @('csplit: ''21'': line number out of range'); Warnings = @(); ExitCode = 1; Files = @() }
        @{ Arguments = @('n', '20'); Output = @('48', '3'); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('xx00:1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,', 'xx01:20,') }
        @{ Arguments = @('n', '%5%', '{*}'); Output = @(); Errors = @(); Warnings = @(); ExitCode = 0; Files = @() }
        @{ Arguments = @('n', '3', '{20}'); Output = @('4', '6', '6', '8', '9', '9', '9'); Errors = @('csplit: ''3'': line number out of range on repetition 6'); Warnings = @(); ExitCode = 1; Files = @() }
        @{ Arguments = @('s', '%^==%', '{1}'); Output = @('19'); Errors = @(); Warnings = @(); ExitCode = 0; Files = @('xx00:== B,b1,== C,c1,c2,') }
        @{ Arguments = @('-b', '%+05d', 'n', '5'); Output = @(); Errors = @('csplit: invalid conversion specifier in suffix: +'); Warnings = @(); ExitCode = 1; Files = @() }
        @{ Arguments = @('n', '/5/x'); Output = @(); Errors = @('csplit: ''/5/x'': integer expected after delimiter'); Warnings = @(); ExitCode = 1; Files = @() }
    ) {
        $dir = New-CsplitDirectory
        $r = Invoke-TestGnu csplit $Arguments -WorkingDirectory $dir
        $r.Output | Should -Be $Output
        @($r.Errors | ForEach-Object { ($_ -split "`n")[0] }) | Should -Be $Errors
        @($r.Warnings) | Should -Be $Warnings
        $r.ExitCode | Should -Be $ExitCode
        Get-CsplitFile -Directory $dir | Should -Be $Files
    }

    It 'reads standard input' {
        $dir = New-CsplitDirectory
        (Invoke-TestGnu csplit '-', '2' -InputObject 'x', 'y' -WorkingDirectory $dir).Output | Should -Be @('2', '2')
        Get-CsplitFile -Directory $dir | Should -Be @('xx00:x,', 'xx01:y,')
        (Invoke-TestGnu csplit 'nosuch', '1' -WorkingDirectory $dir).ExitCode | Should -Be 1
        (Invoke-TestGnu csplit -WorkingDirectory $dir).ErrorText | Should -Match 'missing operand'
        $dir = New-CsplitDirectory
        (Invoke-TestGnu csplit '-b', '%.3d', 'n', '5' -WorkingDirectory $dir).Output | Should -Be @('8', '43')
        @(Get-CsplitFile -Directory $dir | ForEach-Object { ($_ -split ':')[0] }) | Should -Be @('xx000', 'xx001')
        $r = Invoke-TestGnu csplit 'n', '%nomatch%' -WorkingDirectory $dir
        $r.ErrorText | Should -Be "csplit: '%nomatch%': match not found"
        $r.ExitCode | Should -Be 1
    }
}
