# Date strings for touch -d and date -d.
#
# Supported subset of GNU's date grammar:
#   @SECONDS                 seconds since the Unix epoch (fractions allowed)
#   now, today, yesterday, tomorrow
#   ISO 8601 and other invariant-culture date/time texts: 2024-01-31, 2024-01-31 13:45, 2024-01-31T13:45:10Z, ...
#   relative items, alone or after a date: [+-]N unit [ago]  (year month fortnight week day hour minute min second sec)
#   e.g. "2 days ago", "1 hour", "2024-01-01 +3 weeks", "tomorrow 2 hours ago"

$script:GnuRelativeDatePattern = '(?i)(?<![\w:.-])(?<amount>[+-]?\s*\d+\s*)?(?<unit>years?|months?|fortnights?|weeks?|days?|hours?|minutes?|mins?|seconds?|secs?)(?<ago>\s+ago)?(?![\w])'

function ConvertFrom-GnuDateString {
    <#
    .SYNOPSIS
    Parses a GNU style date string into a local [datetime], or returns nothing if it is not understood.
    .PARAMETER Now
    The reference time for 'now' and relative items (default: the current time).
    .PARAMETER Utc
    Interpret times without a zone as UTC and return a UTC [datetime] (date -u).
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Nullable[datetime]]$Now,
        [switch]$Utc
    )

    if ($null -eq $Now) {
        $Now = [datetime]::Now
        if ($Utc) { $Now = [datetime]::UtcNow }
    }
    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $rest = $Text.Trim()

    if ($rest -match '^@(?<seconds>[+-]?\d+(\.\d+)?)$') {
        # Ticks (100 ns) from a decimal, so fractions are not rounded through a double.
        $ticks = [long][Math]::Truncate([decimal]::Parse($Matches['seconds'], $invariant) * 10000000)
        $instant = [System.DateTimeOffset]::FromUnixTimeSeconds(0).AddTicks($ticks)
        if ($Utc) { return $instant.UtcDateTime }
        return $instant.LocalDateTime
    }

    $offsets = New-Object 'System.Collections.Generic.List[object]'
    foreach ($match in [regex]::Matches($rest, $script:GnuRelativeDatePattern)) {
        $amount = 1
        if ($match.Groups['amount'].Success -and $match.Groups['amount'].Value.Trim()) { $amount = [int]($match.Groups['amount'].Value -replace '\s', '') }
        if ($match.Groups['ago'].Success) { $amount = -$amount }
        $offsets.Add(@{ Unit = $match.Groups['unit'].Value.ToLowerInvariant().TrimEnd('s'); Amount = $amount })
    }
    $rest = [regex]::Replace($rest, $script:GnuRelativeDatePattern, ' ').Trim()

    $base = $null
    switch -Regex ($rest) {
        '^(?i)(now|today|)$' { $base = $Now }
        '^(?i)yesterday$' { $base = $Now.AddDays(-1) }
        '^(?i)tomorrow$' { $base = $Now.AddDays(1) }
        default {
            $styles = [System.Globalization.DateTimeStyles]::AssumeLocal -bor [System.Globalization.DateTimeStyles]::AllowWhiteSpaces
            if ($Utc) { $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AllowWhiteSpaces }
            $parsed = [System.DateTimeOffset]::MinValue
            if (-not [System.DateTimeOffset]::TryParse($rest, $invariant, $styles, [ref]$parsed)) { return }
            $base = $parsed.LocalDateTime
            if ($Utc) { $base = $parsed.UtcDateTime }
        }
    }

    foreach ($offset in $offsets) {
        switch ($offset.Unit) {
            'year' { $base = $base.AddYears($offset.Amount) }
            'month' { $base = $base.AddMonths($offset.Amount) }
            'fortnight' { $base = $base.AddDays(14 * $offset.Amount) }
            'week' { $base = $base.AddDays(7 * $offset.Amount) }
            'day' { $base = $base.AddDays($offset.Amount) }
            'hour' { $base = $base.AddHours($offset.Amount) }
            { $_ -eq 'minute' -or $_ -eq 'min' } { $base = $base.AddMinutes($offset.Amount) }
            default { $base = $base.AddSeconds($offset.Amount) }   # second, sec
        }
    }
    $base
}

function ConvertFrom-GnuTouchStamp {
    <#
    .SYNOPSIS
    Parses a touch -t stamp [[CC]YY]MMDDhhmm[.ss] into a local [datetime], or returns nothing if invalid.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Stamp,
        [Nullable[datetime]]$Now
    )

    if ($null -eq $Now) { $Now = [datetime]::Now }
    if ($Stamp -notmatch '^(?<digits>\d{8}|\d{10}|\d{12})(\.(?<seconds>\d{2}))?$') { return }
    $digits = $Matches['digits']
    $seconds = 0
    if ($Matches.ContainsKey('seconds')) { $seconds = [int]$Matches['seconds'] }

    $year = $Now.Year
    if ($digits.Length -eq 12) {
        $year = [int]$digits.Substring(0, 4)
        $digits = $digits.Substring(4)
    }
    elseif ($digits.Length -eq 10) {
        # POSIX: 69-99 are 1969-1999, 00-68 are 2000-2068.
        $short = [int]$digits.Substring(0, 2)
        $year = 2000 + $short
        if ($short -ge 69) { $year = 1900 + $short }
        $digits = $digits.Substring(2)
    }

    try {
        New-Object System.DateTime -ArgumentList $year, ([int]$digits.Substring(0, 2)), ([int]$digits.Substring(2, 2)),
            ([int]$digits.Substring(4, 2)), ([int]$digits.Substring(6, 2)), $seconds, ([System.DateTimeKind]::Local)
    }
    catch {
        return
    }
}
