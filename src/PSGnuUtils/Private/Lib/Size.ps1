# GNU size arguments: 10, 3b (512-byte blocks), 1K / 1KiB (1024), 1kB / 1KB (1000), M, G, T, P, E, Z, Y, R, Q.

$script:GnuSizePowers = @{ K = 1; M = 2; G = 3; T = 4; P = 5; E = 6; Z = 7; Y = 8; R = 9; Q = 10 }

function ConvertFrom-GnuSize {
    <#
    .SYNOPSIS
    Parses an unsigned GNU size. Returns a [decimal], or nothing if the text is not a valid size.
    Values too large for [decimal] are clamped to [decimal]::MaxValue.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    if ($Text -notmatch '^(\d+)([A-Za-z]*)$') { return }
    $suffix = $Matches[2]
    $number = [decimal]0
    if (-not [decimal]::TryParse($Matches[1], [System.Globalization.NumberStyles]::None, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        return [decimal]::MaxValue
    }
    if ([string]::IsNullOrEmpty($suffix)) { return $number }
    if ($suffix -ceq 'b') { return $number * 512 }

    $letter = $suffix.Substring(0, 1).ToUpperInvariant()
    if (-not $script:GnuSizePowers.ContainsKey($letter)) { return }
    $base = 0
    switch -CaseSensitive ($suffix.Substring(1)) {
        '' { $base = 1024 }
        'iB' { $base = 1024 }
        'B' { $base = 1000 }
        default { return }
    }

    try {
        $value = $number
        for ($i = 0; $i -lt $script:GnuSizePowers[$letter]; $i++) { $value = $value * $base }
        $value
    }
    catch {
        [decimal]::MaxValue
    }
}

function ConvertTo-GnuInt64 {
    <#
    .SYNOPSIS
    Converts a [decimal] to [long], clamping to [long]::MaxValue (GNU treats huge counts as "everything").
    #>
    param([Parameter(Mandatory)][decimal]$Value)
    if ($Value -gt [long]::MaxValue) { return [long]::MaxValue }
    if ($Value -lt [long]::MinValue) { return [long]::MinValue }
    [long]$Value
}
