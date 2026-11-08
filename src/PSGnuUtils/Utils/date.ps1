Register-GnuUtil @{
    Name        = 'date'
    Category    = 'User and system info'
    Synopsis    = 'Print or set the system date and time.'
    Usage       = @('date [OPTION]... [+FORMAT]', 'date [-u|--utc|--universal] [MMDDhhmm[[CC]YY][.ss]]')
    Description = @('Display date and time in the given FORMAT.')
    Options     = @(
        @{ Short = 'd'; Long = 'date'; Arg = 'STRING'; Help = 'display time described by STRING, not ''now''' }
        @{ Short = 'f'; Long = 'file'; Arg = 'DATEFILE'; Help = 'like --date; once for each line of DATEFILE' }
        @{ Short = 'I'; Long = 'iso-8601'; Arg = 'FMT'; OptionalArg = $true; Help = 'output date/time in ISO 8601 format.  FMT=''date'' for date only (the default), ''hours'', ''minutes'', ''seconds'', or ''ns'' for date and time to the indicated precision.  Example: 2006-08-14T02:34:56-06:00' }
        @{ Short = 'R'; Long = 'rfc-email'; Help = 'output date and time in RFC 5322 format.  Example: Mon, 14 Aug 2006 02:34:56 -0600' }
        @{ Long = 'rfc-3339'; Arg = 'FMT'; Help = 'output date/time in RFC 3339 format.  FMT=''date'', ''seconds'', or ''ns'' for date and time to the indicated precision.  Example: 2006-08-14 02:34:56-06:00' }
        @{ Short = 'r'; Long = 'reference'; Arg = 'FILE'; Help = 'display the last modification time of FILE' }
        @{ Short = 's'; Long = 'set'; Arg = 'STRING'; Help = 'set time described by STRING (not supported)' }
        @{ Short = 'u'; Long = 'utc'; Key = 'utc'; Help = 'print or set Coordinated Universal Time (UTC)' }
        @{ Long = 'universal'; Key = 'utc'; Help = 'print or set Coordinated Universal Time (UTC)' }
    )
    Notes       = @(
        'FORMAT controls the output.  Interpreted sequences are:',
        '',
        '  %%   a literal %',
        '  %a   abbreviated weekday name (e.g., Sun)',
        '  %A   full weekday name (e.g., Sunday)',
        '  %b   abbreviated month name (e.g., Jan)',
        '  %B   full month name (e.g., January)',
        '  %c   date and time (e.g., Thu Mar  3 23:05:25 2005)',
        '  %C   century; like %Y, except omit last two digits (e.g., 20)',
        '  %d   day of month (e.g., 01)',
        '  %D   date; same as %m/%d/%y',
        '  %e   day of month, space padded; same as %_d',
        '  %F   full date; like %+4Y-%m-%d',
        '  %g   last two digits of year of ISO week number (see %G)',
        '  %G   year of ISO week number (see %V); normally useful only with %V',
        '  %h   same as %b',
        '  %H   hour (00..23)',
        '  %I   hour (01..12)',
        '  %j   day of year (001..366)',
        '  %k   hour, space padded ( 0..23); same as %_H',
        '  %l   hour, space padded ( 1..12); same as %_I',
        '  %m   month (01..12)',
        '  %M   minute (00..59)',
        '  %n   a newline',
        '  %N   nanoseconds (000000000..999999999)',
        '  %p   AM or PM',
        '  %P   like %p, but lower case',
        '  %q   quarter of year (1..4)',
        '  %r   12-hour clock time (e.g., 11:11:04 PM)',
        '  %R   24-hour hour and minute; same as %H:%M',
        '  %s   seconds since the Epoch (1970-01-01 00:00 UTC)',
        '  %S   second (00..60)',
        '  %t   a tab',
        '  %T   time; same as %H:%M:%S',
        '  %u   day of week (1..7); 1 is Monday',
        '  %U   week number of year, with Sunday as first day of week (00..53)',
        '  %V   ISO week number, with Monday as first day of week (01..53)',
        '  %w   day of week (0..6); 0 is Sunday',
        '  %W   week number of year, with Monday as first day of week (00..53)',
        '  %x   date representation (e.g., 12/31/99)',
        '  %X   time representation (e.g., 23:13:48)',
        '  %y   last two digits of year (00..99)',
        '  %Y   year',
        '  %z   +hhmm numeric time zone (e.g., -0400)',
        '  %:z  +hh:mm numeric time zone (e.g., -04:00)',
        '  %::z  +hh:mm:ss numeric time zone (e.g., -04:00:00)',
        '  %:::z  numeric time zone with : to necessary precision (e.g., -04, +05:30)',
        '  %Z   alphabetic time zone abbreviation (e.g., EDT)',
        '',
        'By default, date pads numeric fields with zeroes.',
        'The following optional flags may follow ''%'':',
        '',
        '  -  (hyphen) do not pad the field',
        '  _  (underscore) pad with spaces',
        '  0  (zero) pad with zeros',
        '  ^  use upper case if possible',
        '  #  use opposite case if possible',
        '',
        'After any flags comes an optional field width, as a decimal number.',
        '',
        'PowerShell note: names are those of the C locale; setting the date (-s, MMDDhhmm)',
        'is not supported; the TZ variable is ignored (use -u for UTC); -d understands',
        'ISO 8601 and other invariant-culture dates, @SECONDS, now/today/yesterday/tomorrow',
        'and relative items such as "2 days ago" or "+3 weeks", not the full GNU grammar.',
        '%Z falls back to a numeric zone (+0530) when Windows has no abbreviation.',
        'Times have a resolution of 100 ns (%N ends in 00).'
    )
}

$script:GnuDayNames = @('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')
$script:GnuMonthNames = @('January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December')

function Invoke-GnuDate {
    <#
    .SYNOPSIS
    GNU date: print the date and time in a given format.

    .DESCRIPTION
    Prints the current time, the time of -d STRING, of every line of -f FILE, or the
    modification time of -r FILE, as +FORMAT (strftime sequences such as %Y-%m-%d), ISO 8601
    (-I), RFC 5322 (-R) or RFC 3339 (--rfc-3339). -u uses UTC.
    Enable the GNU name with: Enable-GnuAlias date

    .EXAMPLE
    Invoke-GnuDate +%F

    .EXAMPLE
    Invoke-GnuDate -u -d '@0' -Iseconds

    1970-01-01T00:00:00+00:00
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'date' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuDatePrint -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function Invoke-GnuDatePrint {
    <#
    .SYNOPSIS
    Implementation of date.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $utc = Test-GnuOption -Context $Context -Key 'utc'
    if (Test-GnuOption -Context $Context -Key 'set') { Write-GnuError -Context $Context -Message 'setting the date is not supported'; return }

    $format = $null
    $operands = @($Context.Operands)
    if ($operands.Count -gt 0) {
        if (-not $operands[0].StartsWith('+', [System.StringComparison]::Ordinal)) {
            if ($operands[0] -match '^\d{8}(\d{2}|\d{4})?(\.\d{2})?$') { Write-GnuError -Context $Context -Message 'setting the date is not supported' }
            else { Write-GnuUsageError -Context $Context -Message "invalid date '$($operands[0])'" }
            return
        }
        if ($operands.Count -gt 1) { Write-GnuUsageError -Context $Context -Message "extra operand '$($operands[1])'"; return }
        $format = $operands[0].Substring(1)
    }

    $styles = @()
    if (Test-GnuOption -Context $Context -Key 'iso-8601') {
        $iso = [string](Get-GnuOptionValue -Context $Context -Key 'iso-8601')
        if ([string]::IsNullOrEmpty($iso)) { $iso = 'date' }
        $choice = Select-GnuDateArgument -Context $Context -Value $iso -Option 'iso-8601' -Valid @('date', 'hours', 'minutes', 'seconds', 'ns')
        if ($null -eq $choice) { return }
        $styles += @{ date = '%Y-%m-%d'; hours = '%Y-%m-%dT%H%:z'; minutes = '%Y-%m-%dT%H:%M%:z'; seconds = '%Y-%m-%dT%H:%M:%S%:z'; ns = '%Y-%m-%dT%H:%M:%S,%N%:z' }[$choice]
    }
    if (Test-GnuOption -Context $Context -Key 'rfc-email') { $styles += '%a, %d %b %Y %H:%M:%S %z' }
    if (Test-GnuOption -Context $Context -Key 'rfc-3339') {
        $choice = Select-GnuDateArgument -Context $Context -Value ([string](Get-GnuOptionValue -Context $Context -Key 'rfc-3339')) -Option 'rfc-3339' -Valid @('date', 'seconds', 'ns')
        if ($null -eq $choice) { return }
        $styles += @{ date = '%Y-%m-%d'; seconds = '%Y-%m-%d %H:%M:%S%:z'; ns = '%Y-%m-%d %H:%M:%S.%N%:z' }[$choice]
    }
    if ($null -ne $format) { $styles += $format }
    if ($styles.Count -gt 1) { Write-GnuUsageError -Context $Context -Message 'multiple output formats specified'; return }
    if ($styles.Count -eq 1) { $format = $styles[0] } else { $format = '%a %b %e %H:%M:%S %Z %Y' }

    $sources = @('date', 'file', 'reference') | Where-Object { Test-GnuOption -Context $Context -Key $_ }
    if (@($sources).Count -gt 1) { Write-GnuUsageError -Context $Context -Message 'the options to specify dates for printing are mutually exclusive'; return }

    $times = New-Object 'System.Collections.Generic.List[object]'
    if (Test-GnuOption -Context $Context -Key 'date') {
        $time = ConvertTo-GnuDateTime -Context $Context -Text ([string](Get-GnuOptionValue -Context $Context -Key 'date')) -Utc:$utc
        if ($null -eq $time) { return }
        $times.Add($time)
    }
    elseif (Test-GnuOption -Context $Context -Key 'file') {
        $lines = Get-GnuInputLine -Context $Context -Operand ([string](Get-GnuOptionValue -Context $Context -Key 'file'))
        foreach ($line in @($lines)) {
            $time = ConvertTo-GnuDateTime -Context $Context -Text $line -Utc:$utc
            if ($null -ne $time) { $times.Add($time) }
        }
    }
    elseif (Test-GnuOption -Context $Context -Key 'reference') {
        $reference = [string](Get-GnuOptionValue -Context $Context -Key 'reference')
        $full = Resolve-GnuPath -Path $reference
        if ([System.IO.File]::Exists($full)) { $stamp = [System.IO.File]::GetLastWriteTimeUtc($full) }
        elseif ([System.IO.Directory]::Exists($full)) { $stamp = [System.IO.Directory]::GetLastWriteTimeUtc($full) }
        else { Write-GnuError -Context $Context -Message "$($reference): No such file or directory"; return }
        $times.Add([System.DateTimeOffset]::new([datetime]::SpecifyKind($stamp, [System.DateTimeKind]::Utc)))
    }
    else { $times.Add([System.DateTimeOffset]::Now) }

    foreach ($time in $times) {
        if ($utc) { $time = $time.ToUniversalTime() } else { $time = $time.ToLocalTime() }
        ConvertTo-GnuOutputLine -Text (Format-GnuDate -Time $time -Format $format -Utc:$utc)
    }
}

function Select-GnuDateArgument {
    <#
    .SYNOPSIS
    Resolves an argument of --iso-8601 / --rfc-3339 (unambiguous prefixes allowed), or reports it.
    #>
    param([Parameter(Mandatory)][hashtable]$Context, [Parameter(Mandatory)][AllowEmptyString()][string]$Value, [Parameter(Mandatory)][string]$Option, [Parameter(Mandatory)][string[]]$Valid)
    $found = @($Valid | Where-Object { $_.StartsWith($Value, [System.StringComparison]::Ordinal) -and $Value.Length -gt 0 })
    if ($found.Count -eq 1) { return $found[0] }
    # No two values share a prefix, so a non-matching value is always invalid (never ambiguous).
    Write-GnuUsageError -Context $Context -Message ("invalid argument '$Value' for '--$Option'`nValid arguments are:" + (($Valid | ForEach-Object { "`n  - '$_'" }) -join ''))
    $null
}

function ConvertTo-GnuDateTime {
    <#
    .SYNOPSIS
    Parses a date string to a DateTimeOffset, or reports "invalid date".
    #>
    param([Parameter(Mandatory)][hashtable]$Context, [Parameter(Mandatory)][AllowEmptyString()][string]$Text, [switch]$Utc)
    $parsed = ConvertFrom-GnuDateString -Text $Text -Utc:$Utc
    if ($null -eq $parsed) {
        Write-GnuError -Context $Context -Message "invalid date '$Text'"
        return $null
    }
    if ($Utc) { return [System.DateTimeOffset]::new([datetime]::SpecifyKind($parsed, [System.DateTimeKind]::Utc)) }
    [System.DateTimeOffset]::new([datetime]::SpecifyKind($parsed, [System.DateTimeKind]::Local))
}

function Get-GnuTimeZoneAbbreviation {
    <#
    .SYNOPSIS
    The time zone abbreviation for %Z (CET, EDT, ...), or a numeric zone like +0530 if none is known.
    #>
    param([Parameter(Mandatory)][System.DateTimeOffset]$Time, [System.TimeZoneInfo]$TimeZone = [System.TimeZoneInfo]::Local)

    $daylight = $TimeZone.IsDaylightSavingTime($Time)
    $name = $TimeZone.StandardName
    if ($daylight) { $name = $TimeZone.DaylightName }
    if ($name -cmatch '^[A-Z]{2,6}$') { return $name }
    $known = @(
        @('^(W\. Europe|Central Europe|Central European|Romance)', 'CET', 'CEST'),
        @('^(E\. Europe|FLE|GTB|Eastern European)', 'EET', 'EEST'),
        @('^(GMT Standard|British|Greenwich Mean)', 'GMT', 'BST'),
        @('^(Eastern|US Eastern)', 'EST', 'EDT'),
        @('^Central (Standard|Daylight)', 'CST', 'CDT'),
        @('^(Mountain|US Mountain)', 'MST', 'MDT'),
        @('^Pacific (Standard|Daylight)', 'PST', 'PDT'),
        @('^Alaskan', 'AKST', 'AKDT'),
        @('^Hawaiian', 'HST', 'HDT'),
        @('^Tokyo', 'JST', 'JDT'),
        @('^India', 'IST', 'IST'),
        @('^AUS Eastern', 'AEST', 'AEDT'),
        @('^(Russian|Moscow)', 'MSK', 'MSD'),
        @('^(UTC|Coordinated Universal)', 'UTC', 'UTC')
    )
    foreach ($entry in $known) {
        if ($TimeZone.StandardName -match $entry[0] -or $TimeZone.Id -match $entry[0]) {
            if ($daylight) { return $entry[2] }
            return $entry[1]
        }
    }
    $offset = Format-GnuDateZone -Offset $Time.Offset -Colons 0
    if ($offset.EndsWith('00', [System.StringComparison]::Ordinal)) { return $offset.Substring(0, 3) }
    $offset
}

function Format-GnuDateZone {
    <#
    .SYNOPSIS
    A numeric zone: +hhmm (0 colons), +hh:mm (1), +hh:mm:ss (2), or minimal +hh[:mm] (3).
    #>
    param([Parameter(Mandatory)][timespan]$Offset, [Parameter(Mandatory)][int]$Colons)
    $sign = '+'
    if ($Offset -lt [timespan]::Zero) { $sign = '-'; $Offset = $Offset.Negate() }
    $hours = ([int][Math]::Truncate($Offset.TotalHours)).ToString('00')
    $minutes = $Offset.Minutes.ToString('00')
    switch ($Colons) {
        0 { return "$sign$hours$minutes" }
        1 { return "$sign$($hours):$minutes" }
        2 { return "$sign$($hours):$($minutes):$($Offset.Seconds.ToString('00'))" }
    }
    if ($Offset.Minutes -eq 0) { return "$sign$hours" }
    "$sign$($hours):$minutes"
}

function Get-GnuIsoWeek {
    <#
    .SYNOPSIS
    @{ Year; Week } of the ISO 8601 week date.
    #>
    param([Parameter(Mandatory)][datetime]$Date)
    $weekday = (([int]$Date.DayOfWeek + 6) % 7) + 1
    $thursday = $Date.Date.AddDays(4 - $weekday)
    @{ Year = $thursday.Year; Week = [int][Math]::Floor(($thursday.DayOfYear - 1) / 7) + 1 }
}

function Format-GnuDate {
    <#
    .SYNOPSIS
    Formats a time with GNU date / strftime sequences, flags (- _ 0 ^ #) and widths.
    #>
    param(
        [Parameter(Mandatory)][System.DateTimeOffset]$Time,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Format,
        [switch]$Utc
    )

    $date = $Time.DateTime
    $builder = New-Object System.Text.StringBuilder
    $i = 0
    while ($i -lt $Format.Length) {
        $match = [regex]::Match($Format.Substring($i), '^%([-_0^#]*)(\d*)(:{0,3})([EO]?)(.)?')
        if ($Format[$i] -ne '%' -or -not $match.Groups[5].Success) {
            [void]$builder.Append($Format[$i])
            $i++
            continue
        }
        $i += $match.Length
        $flags = $match.Groups[1].Value
        $width = -1
        if ($match.Groups[2].Value.Length -gt 0) { $width = [int]$match.Groups[2].Value }
        $colons = $match.Groups[3].Value.Length
        $conversion = $match.Groups[5].Value
        if ($colons -gt 0 -and $conversion -cne 'z') {
            [void]$builder.Append($match.Value)
            continue
        }

        # Number (with default padding and width) or text.
        $number = $null
        $pad = '0'
        $size = 2
        $text = $null
        $swapLower = $false
        switch -CaseSensitive ($conversion) {
            'a' { $text = $script:GnuDayNames[[int]$date.DayOfWeek].Substring(0, 3) }
            'A' { $text = $script:GnuDayNames[[int]$date.DayOfWeek] }
            { $_ -eq 'b' -or $_ -eq 'h' } { $text = $script:GnuMonthNames[$date.Month - 1].Substring(0, 3) }
            'B' { $text = $script:GnuMonthNames[$date.Month - 1] }
            'c' { $text = Format-GnuDate -Time $Time -Format '%a %b %e %H:%M:%S %Y' -Utc:$Utc }
            'C' { $number = [Math]::Floor($date.Year / 100) }
            'd' { $number = $date.Day }
            'D' { $text = Format-GnuDate -Time $Time -Format '%m/%d/%y' -Utc:$Utc }
            'e' { $number = $date.Day; $pad = ' ' }
            'F' { $text = Format-GnuDate -Time $Time -Format '%Y-%m-%d' -Utc:$Utc }
            'g' { $number = (Get-GnuIsoWeek -Date $date).Year % 100 }
            'G' { $number = (Get-GnuIsoWeek -Date $date).Year; $size = 4 }
            'H' { $number = $date.Hour }
            'I' { $number = (($date.Hour + 11) % 12) + 1 }
            'j' { $number = $date.DayOfYear; $size = 3 }
            'k' { $number = $date.Hour; $pad = ' ' }
            'l' { $number = (($date.Hour + 11) % 12) + 1; $pad = ' ' }
            'm' { $number = $date.Month }
            'M' { $number = $date.Minute }
            'n' { $text = "`n" }
            'N' {
                $digits = (($date.Ticks % 10000000) * 100).ToString('000000000')
                if ($width -gt 0 -and $width -lt 9) { $digits = $digits.Substring(0, $width) }
                $text = $digits
                $width = -1
            }
            'p' { $text = 'AM'; if ($date.Hour -ge 12) { $text = 'PM' }; $swapLower = $true }
            'P' { $text = 'am'; if ($date.Hour -ge 12) { $text = 'pm' } }
            'q' { $number = [Math]::Floor(($date.Month - 1) / 3) + 1; $size = 1 }
            'r' { $text = Format-GnuDate -Time $Time -Format '%I:%M:%S %p' -Utc:$Utc }
            'R' { $text = Format-GnuDate -Time $Time -Format '%H:%M' -Utc:$Utc }
            's' { $number = $Time.ToUnixTimeSeconds(); $size = 1 }
            'S' { $number = $date.Second }
            't' { $text = "`t" }
            'T' { $text = Format-GnuDate -Time $Time -Format '%H:%M:%S' -Utc:$Utc }
            'u' { $number = (([int]$date.DayOfWeek + 6) % 7) + 1; $size = 1 }
            'U' { $number = [Math]::Floor(($date.DayOfYear - 1 + 7 - [int]$date.DayOfWeek) / 7) }
            'V' { $number = (Get-GnuIsoWeek -Date $date).Week }
            'w' { $number = [int]$date.DayOfWeek; $size = 1 }
            'W' { $number = [Math]::Floor(($date.DayOfYear - 1 + 7 - (([int]$date.DayOfWeek + 6) % 7)) / 7) }
            'x' { $text = Format-GnuDate -Time $Time -Format '%m/%d/%y' -Utc:$Utc }
            'X' { $text = Format-GnuDate -Time $Time -Format '%H:%M:%S' -Utc:$Utc }
            'y' { $number = $date.Year % 100 }
            'Y' { $number = $date.Year; $size = 1 }
            'z' { $text = Format-GnuDateZone -Offset $Time.Offset -Colons $colons }
            'Z' {
                if ($Utc) { $text = 'UTC' } else { $text = Get-GnuTimeZoneAbbreviation -Time $Time }
                $swapLower = $true
            }
            '%' { $text = '%' }
            default { $text = $match.Value }
        }

        if ($null -ne $number) {
            if ($flags.Contains('-')) { $pad = '' }
            elseif ($flags.Contains('_')) { $pad = ' ' }
            elseif ($flags.Contains('0')) { $pad = '0' }
            if ($width -lt 0) { $width = $size }
            $text = [string][long]$number
            if ($pad.Length -gt 0 -and $text.Length -lt $width) { $text = $text.PadLeft($width, [char]$pad) }
        }
        else {
            if ($flags.Contains('^')) { $text = $text.ToUpperInvariant() }
            elseif ($flags.Contains('#')) {
                if ($swapLower) { $text = $text.ToLowerInvariant() } else { $text = $text.ToUpperInvariant() }
            }
            if ($width -gt $text.Length -and -not $flags.Contains('-')) {
                $padChar = ' '
                if ($flags.Contains('0')) { $padChar = '0' }
                $text = $text.PadLeft($width, [char]$padChar)
            }
        }
        [void]$builder.Append($text)
    }
    $builder.ToString()
}
