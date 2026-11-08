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
    param([AllowNull()][AllowEmptyCollection()][object[]]$Arguments, [hashtable]$Spec)

    $previous = $null
    foreach ($argument in $Arguments) {
        if ($null -eq $argument) { continue }
        # An unquoted {} (find -exec, xargs -I) arrives as a script block whose text is empty.
        if ($argument -is [scriptblock]) { $argument = '{' + $argument.ToString() + '}' }
        if ($argument -is [System.Collections.IEnumerable] -and $argument -isnot [string]) {
            $items = @(foreach ($element in $argument) { if ($null -ne $element) { [string]$element } })
            # An unquoted 'cut -f 1,3' or '--output=a,b' arrives as an array: rejoin it when GNU reads it
            # as one option value; anything else (cat $files) stays separate operands.
            $join = $items.Count -gt 1 -and ($items[0] -match '^-[^-]|^--.+=' -or (Test-GnuOptionNeedsValue -Spec $Spec -Token $previous))
            if ($join) { $previous = $items -join ','; $previous }
            else { foreach ($item in $items) { $previous = $item; $item } }
        }
        else {
            $previous = [string]$argument
            $previous
        }
    }
}

function Test-GnuOptionNeedsValue {
    <#
    .SYNOPSIS
    $true if Token is an option (-f, -nf, --field) whose required value is the next argument.
    #>
    param([hashtable]$Spec, [AllowNull()][string]$Token)

    if ($null -eq $Spec -or $Spec.RawArguments -or [string]::IsNullOrEmpty($Token) -or $Token.Length -lt 2 -or $Token[0] -ne '-' -or $Token -eq '--') { return $false }
    $definitions = @($Spec.Options)
    if ($Token.StartsWith('--', [System.StringComparison]::Ordinal)) {
        if ($Token.Contains('=')) { return $false }
        $found = Find-GnuLongOption -Definitions $definitions -Name $Token.Substring(2)
        return $null -ne $found.Option -and [bool]$found.Option.Arg -and -not $found.Option.OptionalArg
    }
    for ($i = 1; $i -lt $Token.Length; $i++) {
        $definition = $definitions | Where-Object { $_.Short -ceq [string]$Token[$i] } | Select-Object -First 1
        if ($null -eq $definition) { return $false }
        if ($definition.Arg) { return $i -eq $Token.Length - 1 -and -not $definition.OptionalArg }
    }
    $false
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
            $Options[$key].Add($Definition.Prefix + [string]$Value)
        }
        else {
            $Options[$key] = $Value
        }
    }
    elseif ($Definition.HasValue -and $Definition.Multi) {
        # Flags that add a constant to a list, in command-line order (od -a -x share one format list).
        if (-not $Options.ContainsKey($key)) { $Options[$key] = New-Object 'System.Collections.Generic.List[string]' }
        $Options[$key].Add([string]$Definition.Value)
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseLiteralInitializerForHashtable', '', Justification = 'Option keys must be case-sensitive (-p vs -P).')]
    param(
        [Parameter(Mandatory)][hashtable]$Spec,
        [AllowEmptyCollection()][string[]]$Arguments = @()
    )

    # Ordinal (case-sensitive) keys: option keys such as 'p' and 'P' must not collide.
    $result = @{
        Options  = New-Object System.Collections.Hashtable -ArgumentList ([System.StringComparer]::Ordinal)
        Operands = New-Object 'System.Collections.Generic.List[string]'
        Error    = $null
        # How each option was last written (-B or --block-size): GNU quotes that form in some messages.
        Spellings = New-Object System.Collections.Hashtable -ArgumentList ([System.StringComparer]::Ordinal)
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
            $result.Spellings[$definition.Key] = "--$($definition.Long)"
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
            $result.Spellings[$definition.Key] = "-$letter"
        }
    }

    $result
}
