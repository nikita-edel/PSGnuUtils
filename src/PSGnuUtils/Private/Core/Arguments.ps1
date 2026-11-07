# GNU getopt_long compatible argument parsing.
#
# Util functions are deliberately simple functions that read the raw $args array instead of
# using PowerShell parameter binding, because parameter binding
#   * is case-insensitive (GNU distinguishes -n and -N, -r and -R, ...),
#   * cannot split bundled short options (-rn),
#   * would capture common parameters (-v would become -Verbose, -e is ambiguous, ...).
#
# Supported syntax (same as GNU getopt_long with argument permutation):
#   -a -b -ab          bundled short flags
#   -nVALUE -n VALUE   short option with a value
#   --long --long=V    long options, unique prefixes accepted (--verb for --verbose)
#   --long V           long option with a required value
#   --                 end of options; '-' alone is an operand (stdin)
#   options and operands may be mixed unless the spec sets StopAtFirstOperand.

function ConvertTo-GnuArgumentList {
    <#
    .SYNOPSIS
    Flattens the raw $args of a util into strings.
    .DESCRIPTION
    PowerShell passes numbers as numbers (-5 arrives as [int]) and comma lists as arrays,
    so every element is flattened and converted with invariant culture.
    #>
    param([AllowNull()][AllowEmptyCollection()][object[]]$Arguments)

    foreach ($argument in $Arguments) {
        if ($null -eq $argument) { continue }
        if ($argument -is [System.Collections.IEnumerable] -and $argument -isnot [string]) {
            foreach ($element in $argument) {
                if ($null -ne $element) { [string]$element }
            }
        }
        else {
            [string]$argument
        }
    }
}

function Find-GnuLongOption {
    <#
    .SYNOPSIS
    Finds a long option by exact name or unique prefix.
    .OUTPUTS
    Hashtable with Option (definition or $null) and Error (message or $null).
    #>
    param(
        [Parameter(Mandatory)][object[]]$Definitions,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name
    )

    $withLong = @($Definitions | Where-Object { $_.Long })
    foreach ($definition in $withLong) {
        if ($definition.Long -ceq $Name) { return @{ Option = $definition; Error = $null } }
    }

    $candidates = @()
    if (-not [string]::IsNullOrEmpty($Name)) {
        $candidates = @($withLong | Where-Object { $_.Long.StartsWith($Name, [System.StringComparison]::Ordinal) })
    }
    if ($candidates.Count -eq 0) {
        return @{ Option = $null; Error = "unrecognized option '--$Name'" }
    }

    $keys = @($candidates | ForEach-Object { $_.Key } | Select-Object -Unique)
    if ($keys.Count -eq 1) { return @{ Option = $candidates[0]; Error = $null } }

    $possibilities = ($candidates | ForEach-Object { "'--$($_.Long)'" }) -join ' '
    @{ Option = $null; Error = "option '--$Name' is ambiguous; possibilities: $possibilities" }
}

function Set-GnuOptionValue {
    <#
    .SYNOPSIS
    Stores one parsed option in the options hashtable.
    .DESCRIPTION
    Options with Arg store their value (Multi options collect a list), options with a constant
    Value store that constant, and plain flags store how often they were given. Additional
    keys from Sets are stored as well.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Options,
        [Parameter(Mandatory)][hashtable]$Definition,
        [AllowNull()][object]$Value
    )

    $key = $Definition.Key
    if ($Definition.Arg) {
        if ($Definition.Multi) {
            if (-not $Options.ContainsKey($key)) { $Options[$key] = New-Object 'System.Collections.Generic.List[string]' }
            $Options[$key].Add([string]$Value)
        }
        else {
            $Options[$key] = $Value
        }
    }
    elseif ($Definition.HasValue) {
        $Options[$key] = $Definition.Value
    }
    else {
        $count = 0
        if ($Options.ContainsKey($key)) { $count = [int]$Options[$key] }
        $Options[$key] = $count + 1
    }

    foreach ($entry in $Definition.Sets.GetEnumerator()) { $Options[$entry.Key] = $entry.Value }
}

function ConvertFrom-GnuArgument {
    <#
    .SYNOPSIS
    Parses a util's arguments according to its spec.
    .OUTPUTS
    Hashtable with Options (hashtable), Operands (List[string]) and Error (message or $null).
    Parsing stops at the first error and right after --help / --version.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Spec,
        [AllowEmptyCollection()][string[]]$Arguments = @()
    )

    $result = @{
        Options  = @{}
        Operands = New-Object 'System.Collections.Generic.List[string]'
        Error    = $null
    }
    $definitions = @($Spec.Options) + @(Get-GnuStandardOption)
    $count = $Arguments.Length
    $index = 0
    $endOfOptions = $false

    while ($index -lt $count) {
        $argument = $Arguments[$index]
        $index++

        $isOperand = $endOfOptions -or $argument.Length -lt 2 -or -not $argument.StartsWith('-', [System.StringComparison]::Ordinal)
        if (-not $isOperand -and $Spec.NegativeNumberOperands -and $argument -match '^-(\d|\.\d)') { $isOperand = $true }
        if ($isOperand) {
            $result.Operands.Add($argument)
            if ($Spec.StopAtFirstOperand) { $endOfOptions = $true }
            continue
        }

        if ($argument -eq '--') {
            $endOfOptions = $true
            continue
        }

        if ($argument.StartsWith('--', [System.StringComparison]::Ordinal)) {
            $name = $argument.Substring(2)
            $value = $null
            $hasValue = $false
            $equals = $name.IndexOf('=', [System.StringComparison]::Ordinal)
            if ($equals -ge 0) {
                $value = $name.Substring($equals + 1)
                $name = $name.Substring(0, $equals)
                $hasValue = $true
            }

            $match = Find-GnuLongOption -Definitions $definitions -Name $name
            if ($match.Error) { $result.Error = $match.Error; return $result }
            $definition = $match.Option

            if ($definition.Arg) {
                if (-not $hasValue -and -not $definition.OptionalArg) {
                    if ($index -lt $count) {
                        $value = $Arguments[$index]
                        $index++
                    }
                    else {
                        $result.Error = "option '--$($definition.Long)' requires an argument"
                        return $result
                    }
                }
            }
            elseif ($hasValue) {
                $result.Error = "option '--$($definition.Long)' doesn't allow an argument"
                return $result
            }

            Set-GnuOptionValue -Options $result.Options -Definition $definition -Value $value
            if ($definition.Key -like '__*') { return $result }
            continue
        }

        # Cluster of short options, e.g. -rn, -n5, -5 (numeric shortcut).
        $position = 1
        if ($Spec.NumericOption -and $argument -match '^-(\d+)') {
            $digits = $Matches[1]
            $numeric = @($definitions | Where-Object { $_.Short -ceq $Spec.NumericOption })[0]
            Set-GnuOptionValue -Options $result.Options -Definition $numeric -Value $digits
            $position = 1 + $digits.Length
        }

        while ($position -lt $argument.Length) {
            $letter = [string]$argument[$position]
            $position++

            $definition = $null
            foreach ($candidate in $definitions) {
                if ($candidate.Short -and $candidate.Short -ceq $letter) { $definition = $candidate; break }
            }
            if ($null -eq $definition) {
                $result.Error = "invalid option -- '$letter'"
                return $result
            }

            $value = $null
            if ($definition.Arg) {
                if ($position -lt $argument.Length) {
                    $value = $argument.Substring($position)
                    $position = $argument.Length
                }
                elseif (-not $definition.OptionalArg) {
                    if ($index -lt $count) {
                        $value = $Arguments[$index]
                        $index++
                    }
                    else {
                        $result.Error = "option requires an argument -- '$letter'"
                        return $result
                    }
                }
            }
            Set-GnuOptionValue -Options $result.Options -Definition $definition -Value $value
        }
    }

    $result
}
