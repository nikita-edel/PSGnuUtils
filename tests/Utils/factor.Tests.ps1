BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# Expected factorizations come from GNU coreutils factor.
Describe 'factor' {
    It 'factors numbers' {
        $r = Invoke-TestGnu factor '0', '1', '2', '4', '84', '97', '+12'
        $r.Output | Should -Be @('0:', '1:', '2: 2', '4: 2 2', '84: 2 2 3 7', '97: 97', '12: 2 2 3')
        $r.ExitCode | Should -Be 0
    }

    It 'factors large numbers' {
        (Invoke-TestGnu factor '1000000007', '18446744073709551617', '600851475143').Output |
            Should -Be @('1000000007: 1000000007', '18446744073709551617: 274177 67280421310721', '600851475143: 71 839 1471 6857')
        (Invoke-TestGnu factor '170141183460469231731687303715884105727').Output | Should -Be @('170141183460469231731687303715884105727: 170141183460469231731687303715884105727')
        (Invoke-TestGnu factor '1000000016000000063').Output | Should -Be @('1000000016000000063: 1000000007 1000000009')
    }

    It 'detects strong pseudoprimes' {
        # 3215031751 passes Miller-Rabin for the bases 2, 3, 5 and 7.
        (Invoke-TestGnu factor '3215031751').Output | Should -Be @('3215031751: 151 751 28351')
    }

    It 'prints exponents with -h / --exponents' {
        (Invoke-TestGnu factor '-h', '1024', '360').Output | Should -Be @('1024: 2^10', '360: 2^3 3^2 5')
        (Invoke-TestGnu factor '--exponents', '7').Output | Should -Be @('7: 7')
    }

    It 'reads whitespace separated numbers from the pipeline' {
        (Invoke-TestGnu factor -InputObject '12 15', '  9').Output | Should -Be @('12: 2 2 3', '15: 3 5', '9: 3 3')
    }

    It 'rejects invalid numbers' {
        $r = Invoke-TestGnu factor 'x', '-5', '6'
        $r.Errors | Should -Be @("factor: 'x' is not a valid positive integer", "factor: '-5' is not a valid positive integer")
        $r.Output | Should -Be @('6: 2 3')
        $r.ExitCode | Should -Be 1
    }

    It 'covers the corner cases of the helpers' {
        InModuleScope PSGnuUtils {
            Test-GnuProbablePrime -Value 1 | Should -BeFalse
            Test-GnuProbablePrime -Value 2 | Should -BeTrue
            Test-GnuProbablePrime -Value 4 | Should -BeFalse
            # Pollard rho with c = 1 fails for 25 and retries with c = 2.
            Find-GnuFactorPollard -Value 25 | Should -Be 5
        }
    }
}
