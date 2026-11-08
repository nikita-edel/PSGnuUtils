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

function Format-GnuHumanSize {
    <#
    .SYNOPSIS
    A byte count like GNU's human_readable with rounding up: 999, 1.0K, 9.9K, 10K, 3.2M (Base 1000: 1.1k, 2.0M).
    #>
    param([Parameter(Mandatory)][double]$Bytes, [ValidateSet(1000, 1024)][int]$Base = 1024)

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Bytes -lt $Base) { return ([Math]::Ceiling($Bytes)).ToString('0', $invariant) }
    $units = 'KMGTPEZY'
    if ($Base -eq 1000) { $units = 'kMGTPEZY' }
    $value = $Bytes
    $unit = -1
    while ($value -ge $Base -and $unit -lt $units.Length - 1) { $value /= $Base; $unit++ }
    if ($value -lt 10) {
        $rounded = [Math]::Ceiling($value * 10) / 10
        if ($rounded -lt 10) { return $rounded.ToString('0.0', $invariant) + $units[$unit] }
        $value = $rounded
    }
    $rounded = [Math]::Ceiling($value)
    if ($rounded -ge $Base -and $unit -lt $units.Length - 1) { return '1.0' + $units[$unit + 1] }
    $rounded.ToString('0', $invariant) + $units[$unit]
}

function ConvertFrom-GnuBlockSize {
    <#
    .SYNOPSIS
    A GNU SIZE argument (1K, M, 1MB, 512, ...) as @{ Bytes; Suffix; Label }, or @{ Error } ('invalid', 'suffix', 'large').

    .DESCRIPTION
    A SIZE without digits prints its unit after every number (-BM: 123M). Label is the size as df's
    header shows it (1K, 1.5kB, 512B): like GNU, the base that divides the size more evenly wins.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [switch]$AllowZero)

    $spec = $Text
    $bare = $Text -match '^[A-Za-z]'
    if ($bare) { $spec = '1' + $Text }
    # dd's 512-byte 'b' is not a SIZE suffix.
    $value = $null
    if ($Text -cnotmatch '^\d*b$') { $value = ConvertFrom-GnuSize -Text $spec }
    if ($null -eq $value) {
        if ($Text -match '^\d') { return @{ Error = 'suffix' } }
        return @{ Error = 'invalid' }
    }
    if ($value -gt [decimal][uint64]::MaxValue) { return @{ Error = 'large' } }
    if ($value -eq 0) {
        if ($AllowZero) { return @{ Bytes = [double]0; Suffix = ''; Label = '0' } }
        return @{ Error = 'invalid' }
    }

    $unit = ''
    $suffix = ''
    $base = 1000
    if ($bare) {
        $letter = $Text.Substring(0, 1).ToUpperInvariant()
        $unit = $Text.Substring(1)
        if ($unit -cne 'B') { $base = 1024 }
        elseif ($letter -ceq 'K') { $letter = 'k' }
        $suffix = $letter + $unit
    }
    $q1000 = [decimal]$value
    $q1024 = [decimal]$value
    do {
        $by1000 = $q1000 % 1000 -eq 0
        $by1024 = $q1024 % 1024 -eq 0
        $q1000 /= 1000
        $q1024 /= 1024
    } while ($by1000 -and $by1024)
    if ($by1024 -and -not $by1000) { $base = 1024 }
    elseif ($by1000 -and -not $by1024) { $base = 1000 }

    $label = (Format-GnuHumanSize -Bytes ([double]$value) -Base $base) -replace '\.0(?=[A-Za-z]|$)', ''
    if ($unit.EndsWith('B', [System.StringComparison]::Ordinal) -or $base -eq 1000) {
        if ($base -eq 1024 -and $label -match '[A-Za-z]$') { $label += 'iB' } else { $label += 'B' }
    }
    @{ Bytes = [double]$value; Suffix = $suffix; Label = $label }
}

function Write-GnuSizeArgumentError {
    <#
    .SYNOPSIS
    GNU's message for a rejected SIZE argument, naming the option as the user wrote it.
    #>
    param([Parameter(Mandatory)][hashtable]$Context, [Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][AllowEmptyString()][string]$Text, [Parameter(Mandatory)][string]$Kind)
    $name = $Context.Spellings[$Key]
    switch ($Kind) {
        'suffix' { $message = "invalid suffix in $name argument '$Text'" }
        'large' { $message = "$name argument '$Text' too large" }
        default { $message = "invalid $name argument '$Text'" }
    }
    Write-GnuError -Context $Context -Message $message
}

function Get-GnuSizeScale {
    <#
    .SYNOPSIS
    The output scale from the 'scale' option as @{ Human; Bytes; Suffix; Label }, or nothing after reporting an error.

    .DESCRIPTION
    -h, --si, -k, -m and -B share the key 'scale', so the last one given wins, as in GNU. Human
    options store 'human:<base>'; everything else is a SIZE.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)
    $text = [string](Get-GnuOptionValue -Context $Context -Key 'scale' -Default '1K')
    if ($text.StartsWith('human:', [System.StringComparison]::Ordinal)) {
        return @{ Human = [int]$text.Substring(6); Bytes = [double]1; Suffix = ''; Label = '' }
    }
    $scale = ConvertFrom-GnuBlockSize -Text $text
    if ($scale.ContainsKey('Error')) { Write-GnuSizeArgumentError -Context $Context -Key 'scale' -Text $text -Kind $scale.Error; return }
    $scale.Human = 0
    $scale
}

function Format-GnuScaledSize {
    <#
    .SYNOPSIS
    A byte count in the scale from Get-GnuSizeScale, rounded up.
    #>
    param([Parameter(Mandatory)][double]$Bytes, [Parameter(Mandatory)][hashtable]$Scale)
    if ($Scale.Human -gt 0) { return Format-GnuHumanSize -Bytes $Bytes -Base $Scale.Human }
    ([Math]::Ceiling($Bytes / $Scale.Bytes)).ToString('0', [System.Globalization.CultureInfo]::InvariantCulture) + $Scale.Suffix
}
