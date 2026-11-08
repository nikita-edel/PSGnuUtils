BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'GNU argument parser' {
    BeforeAll {
        $script:parse = {
            param([hashtable]$SpecOverrides, [string[]]$Arguments)
            InModuleScope PSGnuUtils -Parameters @{ Overrides = $SpecOverrides; Arguments = $Arguments } {
                param($Overrides, $Arguments)
                $spec = @{
                    Options                = @(
                        ConvertTo-GnuOptionDefinition @{ Short = 'n'; Long = 'lines'; Arg = 'NUM' }
                        ConvertTo-GnuOptionDefinition @{ Short = 'v'; Long = 'verbose' }
                        ConvertTo-GnuOptionDefinition @{ Long = 'version-sort'; Key = 'vsort' }
                        ConvertTo-GnuOptionDefinition @{ Short = 'q'; Long = 'quiet'; Key = 'headers'; Value = 'never' }
                        ConvertTo-GnuOptionDefinition @{ Long = 'silent'; Key = 'headers'; Value = 'never' }
                        ConvertTo-GnuOptionDefinition @{ Short = 'A'; Long = 'all'; Sets = @{ extra = 'yes' } }
                        ConvertTo-GnuOptionDefinition @{ Short = 'e'; Long = 'expression'; Arg = 'X'; Multi = $true }
                        ConvertTo-GnuOptionDefinition @{ Long = 'color'; Arg = 'WHEN'; OptionalArg = $true }
                    )
                    StopAtFirstOperand     = $false
                    NumericOption          = $null
                    NegativeNumberOperands = $false
                }
                foreach ($key in $Overrides.Keys) { $spec[$key] = $Overrides[$key] }
                ConvertFrom-GnuArgument -Spec $spec -Arguments $Arguments
            }
        }
    }

    It 'parses bundled short flags' {
        $r = & $parse @{} @('-vq', 'file')
        $r.Error | Should -BeNullOrEmpty
        $r.Options['verbose'] | Should -Be 1
        $r.Options['headers'] | Should -Be 'never'
        $r.Operands | Should -Be @('file')
    }

    It 'counts repeated flags' {
        $r = & $parse @{} @('-v', '-vv')
        $r.Options['verbose'] | Should -Be 3
    }

    It 'reads short option values attached and separated' {
        (& $parse @{} @('-n5')).Options['lines'] | Should -Be '5'
        (& $parse @{} @('-n', '7')).Options['lines'] | Should -Be '7'
        (& $parse @{} @('-vn3')).Options['lines'] | Should -Be '3'
    }

    It 'reads long option values with = and as next argument' {
        (& $parse @{} @('--lines=4')).Options['lines'] | Should -Be '4'
        (& $parse @{} @('--lines', '9')).Options['lines'] | Should -Be '9'
        (& $parse @{} @('--lines=')).Options['lines'] | Should -Be ''
    }

    It 'accepts unique prefixes of long options' {
        (& $parse @{} @('--li=2')).Options['lines'] | Should -Be '2'
        (& $parse @{} @('--q')).Options['headers'] | Should -Be 'never'
    }

    It 'accepts ambiguous prefixes that map to the same key' {
        $r = & $parse @{} @('--s')
        $r.Error | Should -BeNullOrEmpty
        $r.Options['headers'] | Should -Be 'never'
    }

    It 'rejects ambiguous prefixes' {
        $r = & $parse @{} @('--ver')
        $r.Error | Should -Match "option '--ver' is ambiguous; possibilities:"
        $r.Error | Should -Match "'--verbose'"
        $r.Error | Should -Match "'--version-sort'"
    }

    It 'reports unknown options like getopt' {
        (& $parse @{} @('-x')).Error | Should -BeExactly "invalid option -- 'x'"
        (& $parse @{} @('--nope')).Error | Should -BeExactly "unrecognized option '--nope'"
    }

    It 'reports missing and unexpected arguments' {
        (& $parse @{} @('-n')).Error | Should -BeExactly "option requires an argument -- 'n'"
        (& $parse @{} @('--lines')).Error | Should -BeExactly "option '--lines' requires an argument"
        (& $parse @{} @('--verbose=1')).Error | Should -BeExactly "option '--verbose' doesn't allow an argument"
    }

    It 'is case-sensitive for short options' {
        (& $parse @{} @('-V')).Error | Should -BeExactly "invalid option -- 'V'"
    }

    It 'treats -- as end of options and - as an operand' {
        $r = & $parse @{} @('-v', '--', '-n', '-')
        $r.Options['verbose'] | Should -Be 1
        $r.Options.ContainsKey('lines') | Should -BeFalse
        $r.Operands | Should -Be @('-n', '-')
    }

    It 'permutes options after operands by default' {
        $r = & $parse @{} @('a', '-v', 'b')
        $r.Options['verbose'] | Should -Be 1
        $r.Operands | Should -Be @('a', 'b')
    }

    It 'stops at the first operand when StopAtFirstOperand is set' {
        $r = & $parse @{ StopAtFirstOperand = $true } @('a', '-v')
        $r.Options.ContainsKey('verbose') | Should -BeFalse
        $r.Operands | Should -Be @('a', '-v')
    }

    It 'supports the numeric shortcut (-5 means -n 5)' {
        $r = & $parse @{ NumericOption = 'n' } @('-5v')
        $r.Options['lines'] | Should -Be '5'
        $r.Options['verbose'] | Should -Be 1
    }

    It 'treats negative numbers as operands when configured' {
        $r = & $parse @{ NegativeNumberOperands = $true } @('-5', '-.5', '-v')
        $r.Operands | Should -Be @('-5', '-.5')
        $r.Options['verbose'] | Should -Be 1
    }

    It 'collects Multi options' {
        $r = & $parse @{} @('-e', 'a', '--expression=b')
        @($r.Options['expression']) | Should -Be @('a', 'b')
    }

    It 'stores Sets keys' {
        (& $parse @{} @('-A')).Options['extra'] | Should -Be 'yes'
    }

    It 'handles optional arguments' {
        $r = & $parse @{} @('--color', 'x')
        $r.Options.ContainsKey('color') | Should -BeTrue
        $r.Options['color'] | Should -BeNullOrEmpty
        $r.Operands | Should -Be @('x')
        (& $parse @{} @('--color=always')).Options['color'] | Should -Be 'always'
    }

    It 'stops parsing after --help' {
        $r = & $parse @{} @('--help', '--nope')
        $r.Error | Should -BeNullOrEmpty
        $r.Options.ContainsKey('__help') | Should -BeTrue
    }
}

Describe 'ConvertTo-GnuArgumentList' {
    It 'flattens arrays and converts numbers with invariant culture' {
        $result = InModuleScope PSGnuUtils { @(ConvertTo-GnuArgumentList -Arguments @('-n', -5, @('a', 'b'), 1.5, $null)) }
        $result | Should -Be @('-n', '-5', 'a', 'b', '1.5')
    }
}

Describe 'Option definitions' {
    It 'requires a short or long name' {
        { InModuleScope PSGnuUtils { ConvertTo-GnuOptionDefinition @{ Help = 'x' } } } | Should -Throw '*Short or a Long*'
    }

    It 'defaults the key to the long name, then the short name' {
        InModuleScope PSGnuUtils {
            (ConvertTo-GnuOptionDefinition @{ Short = 'a'; Long = 'all' }).Key | Should -Be 'all'
            (ConvertTo-GnuOptionDefinition @{ Short = 'a' }).Key | Should -Be 'a'
        }
    }
}

Describe 'Unquoted comma lists' {
    It 'rejoins a comma list that is an option value' {
        InModuleScope PSGnuUtils {
            $spec = Get-GnuUtilSpec -Name 'cut'
            # cut -f 1,3 file  (PowerShell passes 1,3 as an array)
            @(ConvertTo-GnuArgumentList -Arguments @('-f', @(1, 3), 'file') -Spec $spec) | Should -Be @('-f', '1,3', 'file')
            @(ConvertTo-GnuArgumentList -Arguments @('--fields', @('1', '3')) -Spec $spec) | Should -Be @('--fields', '1,3')
            @(ConvertTo-GnuArgumentList -Arguments @('-sf', @(2, 4)) -Spec $spec) | Should -Be @('-sf', '2,4')
            @(ConvertTo-GnuArgumentList -Arguments @(, @('--fields=1', '2')) -Spec $spec) | Should -Be @('--fields=1,2')
            @(ConvertTo-GnuArgumentList -Arguments @(, @('-f1', '2')) -Spec $spec) | Should -Be @('-f1,2')
        }
    }

    It 'keeps arrays of operands separate' {
        InModuleScope PSGnuUtils {
            $spec = Get-GnuUtilSpec -Name 'cut'
            @(ConvertTo-GnuArgumentList -Arguments @('-s', @('a', 'b')) -Spec $spec) | Should -Be @('-s', 'a', 'b')
            @(ConvertTo-GnuArgumentList -Arguments @(, @('a', 'b')) -Spec $spec) | Should -Be @('a', 'b')
            @(ConvertTo-GnuArgumentList -Arguments @('-f1', @('a', 'b')) -Spec $spec) | Should -Be @('-f1', 'a', 'b')
            @(ConvertTo-GnuArgumentList -Arguments @('--fields=1', @('a', 'b')) -Spec $spec) | Should -Be @('--fields=1', 'a', 'b')
            @(ConvertTo-GnuArgumentList -Arguments @('-x', @('a', 'b')) -Spec $spec) | Should -Be @('-x', 'a', 'b')
            @(ConvertTo-GnuArgumentList -Arguments @('--', @('a', 'b')) -Spec $spec) | Should -Be @('--', 'a', 'b')
            @(ConvertTo-GnuArgumentList -Arguments @('--nosuch', @('a', 'b')) -Spec $spec) | Should -Be @('--nosuch', 'a', 'b')
            @(ConvertTo-GnuArgumentList -Arguments @('-f', @('a', 'b'))) | Should -Be @('-f', 'a', 'b')
            @(ConvertTo-GnuArgumentList -Arguments @('-n', @('a', 'b')) -Spec (Get-GnuUtilSpec -Name 'echo')) | Should -Be @('-n', 'a', 'b')
            @(ConvertTo-GnuArgumentList -Arguments @('--header', @('a', 'b')) -Spec (Get-GnuUtilSpec -Name 'numfmt')) | Should -Be @('--header', 'a', 'b')
        }
    }

    It 'works end to end' {
        (Invoke-TestGnu cut '-d', ' ', '-f', @(1, 3) -InputObject 'a b c').Output | Should -Be @('a c')
    }

    It 'turns an unquoted {} back into text' {
        InModuleScope PSGnuUtils {
            @(ConvertTo-GnuArgumentList -Arguments @('-exec', {}, ';')) | Should -Be @('-exec', '{}', ';')
        }
    }
}
