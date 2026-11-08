BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# Every expected result below was produced by GNU coreutils numfmt 8.32.
Describe 'numfmt' {
    It 'numfmt <Arguments>' -ForEach @(
        @{ Arguments = @('--to=si', '1000', '1500', '999', '1000000', '123456789'); Output = @('1.0K', '1.5K', '999', '1.0M', '124M'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--to=iec', '1024', '1536', '1048576', '1000'); Output = @('1.0K', '1.5K', '1.0M', '1000'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--to=iec-i', '1024', '2048000'); Output = @('1.0Ki', '2.0Mi'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--from=si', '1K', '1.5M', '2G'); Output = @('1000', '1500000', '2000000000'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--from=iec', '1K', '1.5M'); Output = @('1024', '1572864'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--from=iec-i', '1Ki', '2Mi'); Output = @('1024', '2097152'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--from=auto', '1K', '1Ki'); Output = @('1000', '1024'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--to=si', '--round=up', '1001'); Output = @('1.1K'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--to=si', '--round=down', '1999'); Output = @('1.9K'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--to=si', '--round=towards-zero', '--', '-1500'); Output = @('-1.5K'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--to=si', '--round=from-zero', '1001'); Output = @('1.1K'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--to=si', '--round=nearest', '1450', '1550'); Output = @('1.5K', '1.6K'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--suffix=B', '--to=si', '2000'); Output = @('2.0KB'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--padding=8', '42'); Output = @('      42'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--padding=-8', '42'); Output = @('42      '); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--to=si', '--format=%.3f', '1500'); Output = @('1.500K'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--format=%08.2f', '3.14159'); Output = @('00003.15'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--grouping', '1234567'); Output = @('1234567'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--from-unit=1024', '--to=si', '1'); Output = @('1.1K'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--to-unit=1000', '5000'); Output = @('5'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--invalid=warn', 'x', '5'); Output = @('x', '5'); Errors = @('numfmt: invalid number: ''x'''); ExitCode = 0 }
        @{ Arguments = @('--invalid=ignore', 'x', '5'); Output = @('x', '5'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--invalid=fail', 'x', '5'); Output = @('x', '5'); Errors = @('numfmt: invalid number: ''x'''); ExitCode = 2 }
        @{ Arguments = @('x'); Output = @(); Errors = @('numfmt: invalid number: ''x'''); ExitCode = 2 }
        @{ Arguments = @('--to=si', '1e3'); Output = @(); Errors = @('numfmt: invalid suffix in input: ''1e3'''); ExitCode = 2 }
        @{ Arguments = @('--from=si', '1Q'); Output = @(); Errors = @('numfmt: invalid suffix in input: ''1Q'''); ExitCode = 2 }
        @{ Arguments = @('--to=si', '0.5'); Output = @('0'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--to=iec', '1023'); Output = @('1023'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--to=iec', '999999'); Output = @('977K'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--to=si', '999999'); Output = @('1.0M'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--to=si', '--', '-999999'); Output = @('-1.0M'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--format=%x', '1'); Output = @(); Errors = @('numfmt: invalid format ''%x'', directive must be %[0][''][-][N][.][N]f'); ExitCode = 1 }
        @{ Arguments = @('--from=si', '1KB'); Output = @(); Errors = @('numfmt: invalid suffix in input ''1KB'': ''B'''); ExitCode = 2 }
        @{ Arguments = @('--to=si', '1'); Output = @('1'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--to=si', '10000000000000000000000000000000'); Output = @(); Errors = @('numfmt: value too large to be converted: ''10000000000000000000000000000000'''); ExitCode = 2 }
        @{ Arguments = @('--to=iec', '9.99'); Output = @('10'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--to=si', '99.95'); Output = @('100'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--from=si', '1k'); Output = @(); Errors = @('numfmt: invalid suffix in input: ''1k'''); ExitCode = 2 }
        @{ Arguments = @('--to=si', '--format=%.3f', '15', '1500000'); Output = @('15.000', '1.500M'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--format=%10f', '3.5'); Output = @('       3.5'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--format=x%fy', '5'); Output = @('x5y'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--to=iec', '--format=%.1f', '1000'); Output = @('1000.0'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--from=si', '1.5'); Output = @('1.5'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('1.5'); Output = @('1.5'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('1.25', '--format=%.1f'); Output = @('1.3'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--format=%.1f', '1.35', '1.45'); Output = @('1.4', '1.5'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--to=si', '123456789012345678901'); Output = @('124E'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('1234567890123456789'); Output = @('1234567890123456789'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--to=si', '1000000000000000000000000000'); Output = @(); Errors = @('numfmt: value too large to be converted: ''1000000000000000000000000000'''); ExitCode = 2 }
        @{ Arguments = @('--from=iec', '1Y'); Output = @(); Errors = @('numfmt: value too large to be printed: ''1.20893e+24'' (consider using --to)'); ExitCode = 2 }
        @{ Arguments = @('--to=si', '--', '-0.4'); Output = @('-0'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--to-unit=1024', '--to=iec', '1048576'); Output = @('1.0K'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--suffix=B', '1000B'); Output = @('1000B'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--from=si', '--suffix=B', '1KB'); Output = @('1000B'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--to=xyz', '1'); Output = @(); Errors = @('numfmt: invalid argument ''xyz'' for ''--to'''); ExitCode = 1 }
        @{ Arguments = @('--round=xyz', '1'); Output = @(); Errors = @('numfmt: invalid argument ''xyz'' for ''--round'''); ExitCode = 1 }
        @{ Arguments = @('--field=0', '1'); Output = @(); Errors = @('numfmt: fields are numbered from 1'); ExitCode = 1 }
        @{ Arguments = @('--padding=0', '1'); Output = @(); Errors = @('numfmt: invalid padding value ''0'''); ExitCode = 1 }
        @{ Arguments = @('--from-unit=x', '1'); Output = @(); Errors = @('numfmt: invalid unit size: ''x'''); ExitCode = 1 }
        @{ Arguments = @('--format=%f%f', '1'); Output = @(); Errors = @('numfmt: format ''%f%f'' has too many % directives'); ExitCode = 1 }
        @{ Arguments = @('--format=abc', '1'); Output = @(); Errors = @('numfmt: format ''abc'' has no % directive'); ExitCode = 1 }
        @{ Arguments = @('9999999999999999999'); Output = @('9999999999999999999'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('10000000000000000000'); Output = @(); Errors = @('numfmt: value too large to be printed: ''1e+19'' (consider using --to)'); ExitCode = 2 }
        @{ Arguments = @('123456789012345678901234567'); Output = @(); Errors = @('numfmt: value too large to be printed: ''1.23457e+26'' (consider using --to)'); ExitCode = 2 }
        @{ Arguments = @('1234567890123456789012345678'); Output = @(); Errors = @('numfmt: value too large to be converted: ''1234567890123456789012345678'''); ExitCode = 2 }
        @{ Arguments = @('1.123456789'); Output = @('1.123456789'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('0.000001'); Output = @('0.000001'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--to=si', '999999999999999999999999999'); Output = @(); Errors = @('numfmt: value too large to be printed: ''1e+27'' (cannot handle values > 999Y)'); ExitCode = 2 }
        @{ Arguments = @('--to=si', '99999999999999999999999999'); Output = @('100Y'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--from=si', '1000Y'); Output = @(); Errors = @('numfmt: value too large to be printed: ''1e+27'' (consider using --to)'); ExitCode = 2 }
        @{ Arguments = @('--from=si', '0.0001K'); Output = @('1'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--from=si', '--', '-1.5K'); Output = @('-1500'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--format=%05f', '1.5'); Output = @('001.5'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('1.'); Output = @(); Errors = @('numfmt: invalid number: ''1.'''); ExitCode = 2 }
        @{ Arguments = @('.5'); Output = @('0.5'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--', '-.5'); Output = @('-0.5'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--from=iec-i', '1K'); Output = @(); Errors = @('numfmt: missing ''i'' suffix in input: ''1K'' (e.g Ki/Mi/Gi)'); ExitCode = 2 }
        @{ Arguments = @('--from=iec', '1Ki'); Output = @(); Errors = @('numfmt: invalid suffix in input ''1Ki'': ''i'''); ExitCode = 2 }
        @{ Arguments = @('--invalid=bad', '1'); Output = @(); Errors = @('numfmt: invalid argument ''bad'' for ''--invalid'''); ExitCode = 1 }
        @{ Arguments = @('--header=x', '1'); Output = @(); Errors = @('numfmt: invalid header value ''x'''); ExitCode = 1 }
    ) {
        $r = Invoke-TestGnu numfmt $Arguments
        $r.Output | Should -Be $Output
        @($r.Errors | Select-Object -First 1 | ForEach-Object { ($_ -split "`n")[0] }) | Should -Be $Errors
        $r.ExitCode | Should -Be $ExitCode
    }

    It 'numfmt <Arguments> with input <InputLines>' -ForEach @(
        @{ Arguments = @('--field=2', '--to=si'); InputLines = @('a 1500 b', 'c 2000000 d'); Output = @('a 1.5K b', 'c    2.0M d'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--header=1', '--to=si'); InputLines = @('a 1500 b', 'c 2000000 d'); Output = @('a 1500 b'); Errors = @('numfmt: invalid number: ''c'''); ExitCode = 2 }
        @{ Arguments = @('-d,', '--field=2', '--to=si'); InputLines = @('a 1500 b', 'c 2000000 d'); Output = @('a 1500 b', 'c 2000000 d'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--to=si', '--field=1', '--invalid=warn'); InputLines = @('  1500', '1500', 'x  2000000 y', '999999', ' 999999'); Output = @('  1.5K', '1.5K', 'x  2000000 y', '1.0M', '   1.0M'); Errors = @('numfmt: invalid number: ''x'''); ExitCode = 0 }
        @{ Arguments = @('--field=2-3', '--to=si'); InputLines = @('1 2000 3000 4000'); Output = @('1 2.0K 3.0K 4000'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--field=-2', '--to=si'); InputLines = @('1 2000 3000 4000'); Output = @('1 2.0K 3000 4000'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--field=3-', '--to=si'); InputLines = @('1 2000 3000 4000'); Output = @('1 2000 3.0K 4.0K'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--field=-', '--to=si'); InputLines = @('1 2000 3000 4000'); Output = @('1 2.0K 3.0K 4.0K'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--field=1,3', '--to=si'); InputLines = @('1 2000 3000 4000'); Output = @('1 2000 3.0K 4000'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('-d', ',', '--field', '2', '--to=si'); InputLines = @('a,1000,b'); Output = @('a,1.0K,b'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--header', '--to=si', '--invalid=ignore'); InputLines = @('a 1500 b', 'c 2000000 d'); Output = @('a 1500 b', 'c 2000000 d'); Errors = @(); ExitCode = 0 }
    ) {
        $r = Invoke-TestGnu numfmt $Arguments -InputObject $InputLines
        $r.Output | Should -Be $Output
        @($r.Errors | Select-Object -First 1 | ForEach-Object { ($_ -split "`n")[0] }) | Should -Be $Errors
        $r.ExitCode | Should -Be $ExitCode
    }

    It 'handles the remaining options' {
        (Invoke-TestGnu numfmt '--format=%-10f|', '3.5').Output | Should -Be @('3.5       |')
        (Invoke-TestGnu numfmt '--format=%%%f', '5').Output | Should -Be @('%5')
        (Invoke-TestGnu numfmt '--debug', '--to=si', '2000').Output | Should -Be @('2.0K')
        (Invoke-TestGnu numfmt '-z', '--to=si' -InputObject "1000`02000").Output[0] | Should -BeLike "1.0K`02.0K*"
        (Invoke-TestGnu numfmt '--field=1-x', '1').ErrorText | Should -Match "invalid field value 'x'"
        (Invoke-TestGnu numfmt '-d', 'ab', '1').ErrorText | Should -Match 'the delimiter must be a single character'
        (Invoke-TestGnu numfmt '--format=%-08f', '--', '-1.5').Output | Should -Be @('-1.5    ')
        (Invoke-TestGnu numfmt '--format=%08f', '--', '-1.5').Output | Should -Be @('-00001.5')
        (Invoke-TestGnu numfmt -InputObject '   ').ErrorText | Should -Match "invalid number: ''"
        (Invoke-TestGnu numfmt '--zero-terminated', '--to=si' -InputObject "1000").Output[0] | Should -BeLike '1.0K*'
        (Invoke-TestGnu numfmt '--delimiter=ab', '1').ErrorText | Should -Match 'the delimiter must be a single character'
        (Invoke-TestGnu numfmt '--field=x', '1').ErrorText | Should -Match "invalid field value 'x'"
        (Invoke-TestGnu numfmt '--field=', '1').ErrorText | Should -Match 'fields are numbered from 1'
        (Invoke-TestGnu numfmt '--padding=x', '1').ErrorText | Should -Match "invalid padding value 'x'"
        (Invoke-TestGnu numfmt '--format=%.f', '1.6').Output | Should -Be @('2')
        (Invoke-TestGnu numfmt '--to=si', '--format=%-6f', '1500').Output | Should -Be @('1.5K  ')
        (Invoke-TestGnu numfmt '--format=%06f', '--', '-1.5').Output | Should -Be @('-001.5')
        (Invoke-TestGnu numfmt '--to=si', '--', '-0.4').Output | Should -Be @('-0')
        (Invoke-TestGnu numfmt '--to=iec', '0').Output | Should -Be @('0')
        (Invoke-TestGnu numfmt -InputObject '').ErrorText | Should -Match "invalid number: ''"
        (Invoke-TestGnu numfmt '--invalid=fail' -InputObject 'a', '1').ExitCode | Should -Be 2
    }
}
