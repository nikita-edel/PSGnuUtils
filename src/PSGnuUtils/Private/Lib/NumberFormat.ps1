# C printf style floating point formatting (%f %e %g and uppercase variants).
# Used by seq -f; printf will reuse it.

$script:GnuInvariant = [System.Globalization.CultureInfo]::InvariantCulture

function Format-GnuExponent {
    <#
    .SYNOPSIS
    Formats a non-negative number like C's %.<Precision>e (exponent has at least two digits).
    #>
    param(
        [Parameter(Mandatory)][double]$Value,
        [Parameter(Mandatory)][int]$Precision
    )
    $text = $Value.ToString('E' + $Precision, $script:GnuInvariant)
    $parts = $text.Split('E')
    $exponent = [int]$parts[1]
    $sign = '+'
    if ($exponent -lt 0) { $sign = '-' }
    $parts[0] + 'e' + $sign + ([Math]::Abs($exponent)).ToString('00', $script:GnuInvariant)
}

function Remove-GnuTrailingZero {
    <#
    .SYNOPSIS
    Removes trailing fractional zeros (and a dangling '.') from a %g mantissa.
    #>
    param([Parameter(Mandatory)][string]$Text)
    if ($Text.IndexOf('.', [System.StringComparison]::Ordinal) -lt 0) { return $Text }
    $Text.TrimEnd('0').TrimEnd('.')
}

function Format-GnuFloat {
    <#
    .SYNOPSIS
    Formats a number like C printf: conversions f F e E g G, flags - + space 0 #, width, precision.
    #>
    param(
        [Parameter(Mandatory)][double]$Value,
        [Parameter(Mandatory)][char]$Conversion,
        [int]$Precision = -1,
        [AllowEmptyString()][string]$Flags = '',
        [int]$Width = 0
    )

    if ($Precision -lt 0) { $Precision = 6 }
    $kind = [char]::ToLowerInvariant($Conversion)
    $negative = $Value -lt 0
    $magnitude = [Math]::Abs($Value)
    $finite = -not ([double]::IsInfinity($Value) -or [double]::IsNaN($Value))

    if ([double]::IsNaN($Value)) { $body = 'nan' }
    elseif ([double]::IsInfinity($Value)) { $body = 'inf' }
    elseif ($kind -eq 'f') { $body = $magnitude.ToString('F' + $Precision, $script:GnuInvariant) }
    elseif ($kind -eq 'e') { $body = Format-GnuExponent -Value $magnitude -Precision $Precision }
    else {
        $significant = $Precision
        if ($significant -eq 0) { $significant = 1 }
        $exponent = 0
        if ($magnitude -ne 0) {
            $probe = Format-GnuExponent -Value $magnitude -Precision ($significant - 1)
            $exponent = [int]$probe.Substring($probe.IndexOf('e', [System.StringComparison]::Ordinal) + 1)
        }
        if ($exponent -lt -4 -or $exponent -ge $significant) {
            $body = Format-GnuExponent -Value $magnitude -Precision ($significant - 1)
            if (-not $Flags.Contains('#')) {
                $split = $body.IndexOf('e', [System.StringComparison]::Ordinal)
                $body = (Remove-GnuTrailingZero -Text $body.Substring(0, $split)) + $body.Substring($split)
            }
        }
        else {
            $body = $magnitude.ToString('F' + ($significant - 1 - $exponent), $script:GnuInvariant)
            if (-not $Flags.Contains('#')) { $body = Remove-GnuTrailingZero -Text $body }
        }
    }

    if ([char]::IsUpper($Conversion)) { $body = $body.ToUpperInvariant() }

    $sign = ''
    if ($negative) { $sign = '-' }
    elseif ($Flags.Contains('+')) { $sign = '+' }
    elseif ($Flags.Contains(' ')) { $sign = ' ' }

    $text = $sign + $body
    if ($text.Length -lt $Width) {
        if ($Flags.Contains('-')) { $text = $text.PadRight($Width) }
        elseif ($Flags.Contains('0') -and $finite) { $text = $sign + $body.PadLeft($Width - $sign.Length, '0') }
        else { $text = $text.PadLeft($Width) }
    }
    $text
}

function Get-GnuDecimalScale {
    <#
    .SYNOPSIS
    Number of digits after the decimal point stored in a [decimal] (1.50 -> 2).
    #>
    param([Parameter(Mandatory)][decimal]$Value)
    ([System.Decimal]::GetBits($Value)[3] -shr 16) -band 0xFF
}
