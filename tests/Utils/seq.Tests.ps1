BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'seq' {
    It 'prints <Arguments> as <Expected>' -ForEach @(
        @{ Arguments = @('3'); Expected = @('1', '2', '3') }
        @{ Arguments = @('2', '4'); Expected = @('2', '3', '4') }
        @{ Arguments = @('1', '2', '7'); Expected = @('1', '3', '5', '7') }
        @{ Arguments = @('5', '-1', '3'); Expected = @('5', '4', '3') }
        @{ Arguments = @('-3', '-1'); Expected = @('-3', '-2', '-1') }
        @{ Arguments = @('0', '0.25', '1'); Expected = @('0.00', '0.25', '0.50', '0.75', '1.00') }
        @{ Arguments = @('1', '0.1', '1.3'); Expected = @('1.0', '1.1', '1.2', '1.3') }
        @{ Arguments = @('1e1', '12'); Expected = @('10', '11', '12') }
    ) {
        (Invoke-TestGnu seq $Arguments).Output | Should -Be $Expected
    }

    It 'prints nothing for an empty range' {
        $r = Invoke-TestGnu seq '5', '1'
        $r.Output.Count | Should -Be 0
        $r.ExitCode | Should -Be 0
    }

    It 'pads with zeros with -w / --equal-width' {
        (Invoke-TestGnu seq '-w', '8', '10').Output | Should -Be @('08', '09', '10')
        (Invoke-TestGnu seq '--equal-width', '-1', '1').Output | Should -Be @('-1', '00', '01')
    }

    It 'joins with a separator with -s / --separator' {
        (Invoke-TestGnu seq '-s', ',', '3').Output | Should -Be @('1,2,3')
        (Invoke-TestGnu seq '--separator= ', '2').Output | Should -Be @('1 2')
        (Invoke-TestGnu seq '-s', "`n", '2').Output | Should -Be @('1', '2')
    }

    It 'formats with -f / --format' {
        (Invoke-TestGnu seq '-f', '%.2f', '1', '2').Output | Should -Be @('1.00', '2.00')
        (Invoke-TestGnu seq '--format=x%gy', '1').Output | Should -Be @('x1y')
        (Invoke-TestGnu seq '-f', '%e', '1').Output | Should -Be @('1.000000e+00')
        (Invoke-TestGnu seq '-f', '100%% %03g', '2').Output | Should -Be @('100% 002')
        (Invoke-TestGnu seq '-f', '%g', '0.1', '0.1', '0.3').Output | Should -Be @('0.1', '0.2', '0.3')
    }

    It 'rejects invalid formats' {
        (Invoke-TestGnu seq '-f', '%d', '1').ErrorText | Should -Match "format '%d' has unknown %d directive"
        (Invoke-TestGnu seq '-f', 'abc', '1').ErrorText | Should -Match "format 'abc' has no % directive"
        (Invoke-TestGnu seq '-f', '%f%f', '1').ErrorText | Should -Match 'too many % directives'
        (Invoke-TestGnu seq '-f', '%f', '-w', '1').ErrorText | Should -Match 'format string may not be specified when printing equal width strings'
    }

    It 'rejects invalid numbers, zero increments and wrong operand counts' {
        (Invoke-TestGnu seq 'x').ErrorText | Should -Match "invalid floating point argument: 'x'"
        (Invoke-TestGnu seq '1', '0', '2').ErrorText | Should -Match "invalid Zero increment value: '0'"
        (Invoke-TestGnu seq).ErrorText | Should -Match 'missing operand'
        $r = Invoke-TestGnu seq '1', '2', '3', '4'
        $r.ErrorText | Should -Match "extra operand '4'"
        $r.ExitCode | Should -Be 1
    }
}
