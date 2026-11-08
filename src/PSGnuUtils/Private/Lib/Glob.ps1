# Shell patterns (fnmatch) -> .NET regular expressions: find -name / -path, later anything that matches names.

function ConvertTo-GnuGlobRegex {
    <#
    .SYNOPSIS
    The .NET regex (anchored) for a shell pattern, as GNU fnmatch reads it without flags: '*' and '?' also match '/'
    and a leading '.', a backslash quotes the next character, [...] is a bracket expression with ! or ^ for negation.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Pattern)

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('^')
    $i = 0
    while ($i -lt $Pattern.Length) {
        $char = [string]$Pattern[$i]
        if ($char -ceq '*') { [void]$builder.Append('.*'); $i++; continue }
        if ($char -ceq '?') { [void]$builder.Append('.'); $i++; continue }
        if ($char -ceq '\' -and $i + 1 -lt $Pattern.Length) {
            [void]$builder.Append([regex]::Escape([string]$Pattern[$i + 1]))
            $i += 2
            continue
        }
        if ($char -ceq '[') {
            $bracket = ConvertFrom-GnuGlobBracket -Pattern $Pattern -Index $i
            if ($null -ne $bracket) {
                [void]$builder.Append($bracket.Regex)
                $i = $bracket.Next
                continue
            }
        }
        [void]$builder.Append([regex]::Escape($char))
        $i++
    }
    [void]$builder.Append('\z')
    $builder.ToString()
}

function ConvertFrom-GnuGlobBracket {
    <#
    .SYNOPSIS
    The bracket expression starting at Pattern[Index] as @{ Regex; Next }, or $null when it is not closed (then '[' is literal).
    #>
    param([Parameter(Mandatory)][string]$Pattern, [Parameter(Mandatory)][int]$Index)

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('[')
    $i = $Index + 1
    if ($i -lt $Pattern.Length -and ($Pattern[$i] -eq '!' -or $Pattern[$i] -eq '^')) { [void]$builder.Append('^'); $i++ }
    $first = $true
    while ($i -lt $Pattern.Length) {
        $char = [string]$Pattern[$i]
        if ($char -ceq ']' -and -not $first) { return @{ Regex = $builder.Append(']').ToString(); Next = $i + 1 } }
        $first = $false
        if ($char -ceq '[' -and $i + 1 -lt $Pattern.Length -and $Pattern[$i + 1] -eq ':') {
            $close = $Pattern.IndexOf(':]', $i + 2, [System.StringComparison]::Ordinal)
            if ($close -gt 0 -and $script:GnuPosixClasses.ContainsKey($Pattern.Substring($i + 2, $close - $i - 2))) {
                [void]$builder.Append($script:GnuPosixClasses[$Pattern.Substring($i + 2, $close - $i - 2)])
                $i = $close + 2
                continue
            }
        }
        if ($char -ceq '\' -and $i + 1 -lt $Pattern.Length) { $i++; $char = [string]$Pattern[$i] }
        elseif ($char -ceq '-' -and $builder.Length -gt 1 -and $i + 1 -lt $Pattern.Length -and $Pattern[$i + 1] -ne ']') {
            [void]$builder.Append('-')
            $i++
            continue
        }
        if ('\^[]-'.Contains($char)) { [void]$builder.Append('\') }
        [void]$builder.Append($char)
        $i++
    }
    $null
}
