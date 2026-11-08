Register-GnuUtil @{
    Name                   = 'numfmt'
    Category               = 'Text processing'
    Synopsis               = 'Convert numbers from/to human-readable strings.'
    Usage                  = @('numfmt [OPTION]... [NUMBER]...')
    Description            = @('Reformat NUMBER(s), or the numbers from standard input if none are specified.')
    NegativeNumberOperands = $true
    Options                = @(
        @{ Long = 'debug'; Help = 'print warnings about invalid input' }
        @{ Short = 'd'; Long = 'delimiter'; Arg = 'X'; Help = 'use X instead of whitespace for field delimiter' }
        @{ Long = 'field'; Arg = 'FIELDS'; Help = 'replace the numbers in these input fields (default=1) see FIELDS below' }
        @{ Long = 'format'; Arg = 'FORMAT'; Help = 'use printf style floating-point FORMAT; see FORMAT below for details' }
        @{ Long = 'from'; Arg = 'UNIT'; Help = 'auto-scale input numbers to UNITs; default is ''none''; see UNIT below' }
        @{ Long = 'from-unit'; Arg = 'N'; Help = 'specify the input unit size (instead of the default 1)' }
        @{ Long = 'grouping'; Help = 'use locale-defined grouping of digits, e.g. 1,000,000 (which means it has no effect in the C/POSIX locale)' }
        @{ Long = 'header'; Arg = 'N'; OptionalArg = $true; Help = 'print (without converting) the first N header lines; N defaults to 1 if not specified' }
        @{ Long = 'invalid'; Arg = 'MODE'; Help = 'failure mode for invalid numbers: MODE can be: abort (default), fail, warn, ignore' }
        @{ Long = 'padding'; Arg = 'N'; Help = 'pad the output to N characters; positive N will right-align; negative N will left-align; padding is ignored if the output is wider than N; the default is to automatically pad if a whitespace is found' }
        @{ Long = 'round'; Arg = 'METHOD'; Help = 'use METHOD for rounding when scaling; METHOD can be: up, down, from-zero (default), towards-zero, nearest' }
        @{ Long = 'suffix'; Arg = 'SUFFIX'; Help = 'add SUFFIX to output numbers, and accept optional SUFFIX in input numbers' }
        @{ Long = 'to'; Arg = 'UNIT'; Help = 'auto-scale output numbers to UNITs; see UNIT below' }
        @{ Long = 'to-unit'; Arg = 'N'; Help = 'the output unit size (instead of the default 1)' }
        @{ Short = 'z'; Long = 'zero-terminated'; Help = 'line delimiter is NUL, not newline' }
    )
    Notes                  = @(
        'UNIT options:',
        '  none       no auto-scaling is done; suffixes will trigger an error',
        '  auto       accept optional single/two letter suffix:',
        '               1K = 1000,',
        '               1Ki = 1024,',
        '               1M = 1000000,',
        '               1Mi = 1048576,',
        '  si         accept optional single letter suffix:',
        '               1K = 1000,',
        '               1M = 1000000,',
        '               ...',
        '  iec        accept optional single letter suffix:',
        '               1K = 1024,',
        '               1M = 1048576,',
        '               ...',
        '  iec-i      accept optional two-letter suffix:',
        '               1Ki = 1024,',
        '               1Mi = 1048576,',
        '               ...',
        '',
        'FIELDS supports cut(1) style field ranges:',
        '  N    N''th field, counted from 1',
        '  N-   from N''th field, to end of line',
        '  N-M  from N''th to M''th field (inclusive)',
        '  -M   from first to M''th field (inclusive)',
        '  -    all fields',
        'Multiple fields/ranges can be separated with commas',
        '',
        'FORMAT must be suitable for printing one floating-point argument ''%f''.',
        'Optional quote (%''f) will enable --grouping (if supported by current locale).',
        'Optional width value (%10f) will pad output. Optional zero (%010f) width',
        'will zero pad the number. Optional negative values (%-10f) will left align.',
        'Optional precision (%.1f) will override the input determined precision.',
        '',
        'Exit status is 0 if all input numbers were successfully converted.',
        'By default, numfmt will stop at the first conversion error with exit status 2.',
        'With --invalid=''fail'' a warning is printed for each conversion error',
        'and the exit status is 2.  With --invalid=''warn'' each conversion error is',
        'diagnosed, but the exit status is 0.  With --invalid=''ignore'' conversion',
        'errors are not diagnosed and the exit status is 0.',
        '',
        'PowerShell note: numbers are [decimal] (GNU uses long double), so results can differ',
        'in the last digit for some inputs. --debug is accepted and ignored.'
    )
}

$script:GnuNumfmtPowers = ' KMGTPEZY'

function Invoke-GnuNumfmt {
    <#
    .SYNOPSIS
    GNU numfmt: convert numbers from and to human-readable strings (1K, 1.5Mi, ...).

    .DESCRIPTION
    Converts the NUMBERs, or field 1 (or --field) of every input line: --from parses
    suffixes (si, iec, iec-i, auto), --to scales the output, --round, --format, --padding,
    --suffix and the unit options control the result.
    Enable the GNU name with: Enable-GnuAlias numfmt

    .EXAMPLE
    Invoke-GnuNumfmt --to=iec 1048576

    1.0M

    .EXAMPLE
    Get-ChildItem | ForEach-Object Length | Invoke-GnuNumfmt --to=si
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'numfmt' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuNumfmtConvert -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function Select-GnuNumfmtChoice {
    <#
    .SYNOPSIS
    The value of an option with a fixed list of arguments, or $null after a GNU style usage error.
    #>
    param([Parameter(Mandatory)][hashtable]$Context, [Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string[]]$Valid, [Parameter(Mandatory)][string]$Default)
    if (-not (Test-GnuOption -Context $Context -Key $Key)) { return $Default }
    $value = [string](Get-GnuOptionValue -Context $Context -Key $Key)
    if ($Valid -ccontains $value) { return $value }
    Write-GnuUsageError -Context $Context -Message ("invalid argument '$value' for '--$Key'`nValid arguments are:" + (($Valid | ForEach-Object { "`n  - '$_'" }) -join ''))
    $null
}

function Invoke-GnuNumfmtRound {
    <#
    .SYNOPSIS
    Rounds a decimal to an integer with a numfmt --round METHOD.
    #>
    param([Parameter(Mandatory)][decimal]$Value, [Parameter(Mandatory)][string]$Method)
    switch ($Method) {
        'up' { return [Math]::Ceiling($Value) }
        'down' { return [Math]::Floor($Value) }
        'towards-zero' { return [Math]::Truncate($Value) }
        'nearest' { return [Math]::Round($Value, [System.MidpointRounding]::AwayFromZero) }
    }
    if ($Value -lt 0) { return -[Math]::Ceiling(-$Value) }
    [Math]::Ceiling($Value)
}

function Format-GnuNumfmtFixed {
    <#
    .SYNOPSIS
    A decimal with exactly Digits decimals, rounding half to even like C printf (and keeping '-0').
    #>
    param([Parameter(Mandatory)][decimal]$Value, [Parameter(Mandatory)][int]$Digits)
    $rounded = [Math]::Round($Value, $Digits, [System.MidpointRounding]::ToEven)
    $text = [Math]::Abs($rounded).ToString('F' + $Digits, [System.Globalization.CultureInfo]::InvariantCulture)
    if ($Value -lt 0) { $text = '-' + $text }
    $text
}

function ConvertFrom-GnuNumfmtNumber {
    <#
    .SYNOPSIS
    Parses one input number. Returns @{ Value ([decimal]); Precision } or @{ Error }.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [Parameter(Mandatory)][hashtable]$Settings)

    $number = $Text.Trim()
    if ($Settings.Suffix.Length -gt 0 -and $number.EndsWith($Settings.Suffix, [System.StringComparison]::Ordinal)) { $number = $number.Substring(0, $number.Length - $Settings.Suffix.Length) }
    $match = [regex]::Match($number, '^(-?)(\d*)(?:\.(\d+))?(.*)$')
    if ($match.Groups[2].Value.Length -eq 0 -and -not $match.Groups[3].Success) { return @{ Error = "invalid number: '$($Text.Trim())'" } }
    if ($match.Groups[2].Value.Length -gt 27) { return @{ Error = "value too large to be converted: '$($Text.Trim())'" } }
    $integer = $match.Groups[2].Value
    if ($integer.Length -eq 0) { $integer = '0' }
    $fraction = $match.Groups[3].Value
    $value = [decimal]::Parse("$integer.$($fraction)0", [System.Globalization.CultureInfo]::InvariantCulture)
    $precision = $fraction.Length
    $rest = $match.Groups[4].Value
    if ($rest.Length -gt 0) {
        if ($rest.StartsWith('.', [System.StringComparison]::Ordinal)) { return @{ Error = "invalid number: '$($Text.Trim())'" } }
        if ($Settings.From -eq 'none') { return @{ Error = "invalid suffix in input: '$($Text.Trim())'" } }
        $power = $script:GnuNumfmtPowers.IndexOf($rest[0])
        if ($power -lt 1) { return @{ Error = "invalid suffix in input: '$($Text.Trim())'" } }
        $rest = $rest.Substring(1)
        $base = 1000
        if ($Settings.From -eq 'iec' -or $Settings.From -eq 'iec-i') { $base = 1024 }
        if ($Settings.From -eq 'iec-i' -or $Settings.From -eq 'auto') {
            if ($rest.StartsWith('i', [System.StringComparison]::Ordinal)) { $base = 1024; $rest = $rest.Substring(1) }
            elseif ($Settings.From -eq 'iec-i') { return @{ Error = "missing 'i' suffix in input: '$($Text.Trim())' (e.g Ki/Mi/Gi)" } }
        }
        if ($rest.Length -gt 0) { return @{ Error = "invalid suffix in input '$($Text.Trim())': '$rest'" } }
        for ($i = 0; $i -lt $power; $i++) { $value *= $base }
        $precision = 0
    }
    if ($match.Groups[1].Value -eq '-') { $value = -$value }
    @{ Value = $value * $Settings.FromUnit; Precision = $precision }
}

function Format-GnuNumfmtNumber {
    <#
    .SYNOPSIS
    Formats one converted number (scaling, rounding, suffixes, --format, --padding). Returns @{ Text } or @{ Error }.
    #>
    param([Parameter(Mandatory)][decimal]$Value, [Parameter(Mandatory)][int]$Precision, [Parameter(Mandatory)][hashtable]$Settings)

    $value = $Value / $Settings.ToUnit
    $userPrecision = $Settings.FormatPrecision
    if ($Settings.To -eq 'none') {
        if ([Math]::Abs($value) -ge 10000000000000000000) {
            return @{ Error = "value too large to be printed: '$(Format-GnuFloat -Value ([double]$value) -Conversion 'g')' (consider using --to)" }
        }
        $digits = $Precision
        if ($userPrecision -ge 0) { $digits = $userPrecision }
        $scale = [decimal][Math]::Pow(10, $digits)
        $text = Format-GnuNumfmtFixed -Value ((Invoke-GnuNumfmtRound -Value ($value * $scale) -Method $Settings.Round) / $scale) -Digits $digits
    }
    else {
        $base = [decimal]1000
        if ($Settings.To -ne 'si') { $base = [decimal]1024 }
        $power = 0
        $scaled = $value
        while ([Math]::Abs($scaled) -ge $base) { $scaled /= $base; $power++ }
        $adjust = 0
        if ($userPrecision -ge 0) { $adjust = [Math]::Min($power * 3, $userPrecision) }
        elseif ([Math]::Abs($scaled) -lt 10) { $adjust = 1 }
        $factor = [decimal][Math]::Pow(10, $adjust)
        $scaled = (Invoke-GnuNumfmtRound -Value ($scaled * $factor) -Method $Settings.Round) / $factor
        if ([Math]::Abs($scaled) -ge $base) { $scaled /= $base; $power++ }
        if ($power -gt 8) { return @{ Error = "value too large to be printed: '$(Format-GnuFloat -Value ([double]$value) -Conversion 'g')' (cannot handle values > 999Y)" } }
        if ($userPrecision -ge 0) { $digits = $userPrecision }
        elseif ($scaled -ne 0 -and [Math]::Abs($scaled) -lt 10 -and $power -gt 0) { $digits = 1 }
        else { $digits = 0 }
        $text = Format-GnuNumfmtFixed -Value $scaled -Digits $digits
        if ($power -gt 0) {
            $text += $script:GnuNumfmtPowers[$power]
            if ($Settings.To -eq 'iec-i') { $text += 'i' }
        }
    }
    $text += $Settings.Suffix
    if ($Settings.FormatWidth -ne 0) {
        $width = [Math]::Abs($Settings.FormatWidth)
        if ($Settings.FormatWidth -lt 0) { $text = $text.PadRight($width) }
        elseif ($Settings.FormatZero -and $text.Length -lt $width) {
            $sign = ''
            if ($text.StartsWith('-', [System.StringComparison]::Ordinal)) { $sign = '-'; $text = $text.Substring(1) }
            $text = $sign + $text.PadLeft($width - $sign.Length, '0')
        }
        else { $text = $text.PadLeft($width) }
    }
    elseif ($Settings.Padding -gt 0) { $text = $text.PadLeft($Settings.Padding) }
    elseif ($Settings.Padding -lt 0) { $text = $text.PadRight(-$Settings.Padding) }
    @{ Text = $Settings.FormatPrefix + $text + $Settings.FormatSuffix }
}

function ConvertFrom-GnuNumfmtFieldList {
    <#
    .SYNOPSIS
    Parses --field into a predicate list of @{ From; To }. Returns @{ Ranges } or @{ Error }.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    if ($Text.Length -eq 0) { return @{ Error = 'fields are numbered from 1' } }
    $ranges = New-Object 'System.Collections.Generic.List[hashtable]'
    foreach ($item in $Text.Split(',')) {
        $match = [regex]::Match($item, '^(\d*)(-?)(\d*)$')
        if (-not $match.Success -or $item.Length -eq 0) {
            $bad = @($item.Split('-') | Where-Object { $_ -notmatch '^\d*$' }) + @($item)
            return @{ Error = "invalid field value '$($bad[0])'" }
        }
        $from = 1
        $to = [int]::MaxValue
        if ($match.Groups[1].Value.Length -gt 0) { $from = [int]$match.Groups[1].Value }
        if ($match.Groups[2].Value.Length -eq 0) { $to = $from }
        elseif ($match.Groups[3].Value.Length -gt 0) { $to = [int]$match.Groups[3].Value }
        if ($from -eq 0 -or $to -eq 0) { return @{ Error = 'fields are numbered from 1' } }
        $ranges.Add(@{ From = $from; To = $to })
    }
    @{ Ranges = $ranges }
}

function Invoke-GnuNumfmtConvert {
    <#
    .SYNOPSIS
    Implementation of numfmt.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $from = Select-GnuNumfmtChoice -Context $Context -Key 'from' -Valid @('none', 'auto', 'si', 'iec', 'iec-i') -Default 'none'
    if ($null -eq $from) { return }
    $to = Select-GnuNumfmtChoice -Context $Context -Key 'to' -Valid @('none', 'si', 'iec', 'iec-i') -Default 'none'
    if ($null -eq $to) { return }
    $round = Select-GnuNumfmtChoice -Context $Context -Key 'round' -Valid @('up', 'down', 'from-zero', 'towards-zero', 'nearest') -Default 'from-zero'
    if ($null -eq $round) { return }
    $invalid = Select-GnuNumfmtChoice -Context $Context -Key 'invalid' -Valid @('abort', 'fail', 'warn', 'ignore') -Default 'abort'
    if ($null -eq $invalid) { return }

    $settings = @{
        From = $from; To = $to; Round = $round; FromUnit = [decimal]1; ToUnit = [decimal]1; Suffix = ''; Padding = 0
        FormatPrefix = ''; FormatSuffix = ''; FormatWidth = 0; FormatZero = $false; FormatPrecision = -1
    }
    foreach ($key in @('from-unit', 'to-unit')) {
        if (-not (Test-GnuOption -Context $Context -Key $key)) { continue }
        $text = [string](Get-GnuOptionValue -Context $Context -Key $key)
        $unit = ConvertFrom-GnuNumfmtNumber -Text $text -Settings @{ Suffix = ''; From = 'auto'; FromUnit = [decimal]1 }
        if ($unit.ContainsKey('Error') -or $unit.Value -le 0) { Write-GnuError -Context $Context -Message "invalid unit size: '$text'"; return }
        if ($key -eq 'from-unit') { $settings.FromUnit = $unit.Value } else { $settings.ToUnit = $unit.Value }
    }
    if (Test-GnuOption -Context $Context -Key 'suffix') { $settings.Suffix = [string](Get-GnuOptionValue -Context $Context -Key 'suffix') }
    if (Test-GnuOption -Context $Context -Key 'padding') {
        $text = [string](Get-GnuOptionValue -Context $Context -Key 'padding')
        if ($text -notmatch '^-?\d+$' -or [int]$text -eq 0) { Write-GnuError -Context $Context -Message "invalid padding value '$text'"; return }
        $settings.Padding = [int]$text
    }
    if (Test-GnuOption -Context $Context -Key 'format') {
        $text = [string](Get-GnuOptionValue -Context $Context -Key 'format')
        $directives = [regex]::Matches($text, '%%|%')
        $single = @($directives | Where-Object { $_.Value -eq '%' })
        if ($single.Count -eq 0) { Write-GnuError -Context $Context -Message "format '$text' has no % directive"; return }
        if ($single.Count -gt 1) { Write-GnuError -Context $Context -Message "format '$text' has too many % directives"; return }
        $at = $single[0].Index
        $spec = [regex]::Match($text.Substring($at), "^%(0?)('?)(-?)(\d*)(?:\.(\d*))?f")
        if (-not $spec.Success) { Write-GnuError -Context $Context -Message "invalid format '$text', directive must be %[0]['][-][N][.][N]f"; return }
        $settings.FormatPrefix = $text.Substring(0, $at).Replace('%%', '%')
        $settings.FormatSuffix = $text.Substring($at + $spec.Length)
        $settings.FormatZero = $spec.Groups[1].Value -eq '0'
        if ($spec.Groups[4].Value.Length -gt 0) {
            $settings.FormatWidth = [int]$spec.Groups[4].Value
            if ($spec.Groups[3].Value -eq '-') { $settings.FormatWidth = -$settings.FormatWidth }
        }
        if ($spec.Groups[5].Success) {
            $settings.FormatPrecision = 0
            if ($spec.Groups[5].Value.Length -gt 0) { $settings.FormatPrecision = [int]$spec.Groups[5].Value }
        }
    }
    $ranges = @(@{ From = 1; To = 1 })
    if (Test-GnuOption -Context $Context -Key 'field') {
        $parsed = ConvertFrom-GnuNumfmtFieldList -Text ([string](Get-GnuOptionValue -Context $Context -Key 'field'))
        if ($parsed.ContainsKey('Error')) { Write-GnuUsageError -Context $Context -Message $parsed.Error; return }
        $ranges = $parsed.Ranges
    }
    $delimiter = $null
    if (Test-GnuOption -Context $Context -Key 'delimiter') {
        $delimiter = [string](Get-GnuOptionValue -Context $Context -Key 'delimiter')
        if ($delimiter.Length -ne 1) { Write-GnuError -Context $Context -Message 'the delimiter must be a single character'; return }
    }
    $header = 0
    if (Test-GnuOption -Context $Context -Key 'header') {
        $text = [string](Get-GnuOptionValue -Context $Context -Key 'header')
        $header = 1
        if (-not [string]::IsNullOrEmpty($text)) {
            if ($text -notmatch '^\d+$' -or [int]$text -eq 0) { Write-GnuError -Context $Context -Message "invalid header value '$text'"; return }
            $header = [int]$text
        }
    }
    $zero = Test-GnuOption -Context $Context -Key 'zero-terminated'

    $lines = @($Context.Operands)
    if ($lines.Count -eq 0) {
        $text = Get-GnuInputText -Context $Context -Operand '-'
        if ($null -eq $text) { return }
        $separator = "`n"
        if ($zero) { $separator = "`0" } else { $text = $text.Replace("`r`n", "`n") }
        $lines = @(Split-GnuRecord -Text $text -Separator $separator)
    }
    else { $header = 0 }

    $output = New-Object 'System.Collections.Generic.List[string]'
    $failed = $false
    for ($n = 0; $n -lt $lines.Count; $n++) {
        if ($n -lt $header) { $output.Add($lines[$n]); continue }
        $fields = New-Object 'System.Collections.Generic.List[string]'
        $trailing = ''
        if ($null -eq $delimiter) {
            foreach ($match in [regex]::Matches($lines[$n], '\s*\S+')) { $fields.Add($match.Value) }
            $trailing = $lines[$n].Substring((@($fields) -join '').Length)
        }
        else { foreach ($part in $lines[$n].Split([char]$delimiter)) { $fields.Add($part) } }
        if ($fields.Count -eq 0) { $fields.Add($trailing); $trailing = '' }

        for ($f = 0; $f -lt $fields.Count; $f++) {
            $number = $f + 1
            if (@($ranges | Where-Object { $number -ge $_.From -and $number -le $_.To }).Count -eq 0) { continue }
            $field = $fields[$f]
            $parsed = ConvertFrom-GnuNumfmtNumber -Text $field -Settings $settings
            $result = $parsed
            if (-not $parsed.ContainsKey('Error')) { $result = Format-GnuNumfmtNumber -Value $parsed.Value -Precision $parsed.Precision -Settings $settings }
            if ($result.ContainsKey('Error')) {
                if ($invalid -ne 'ignore') { Write-GnuError -Context $Context -Message $result.Error -ExitCode 2 }
                if ($invalid -eq 'abort') { ConvertTo-GnuRecordOutput -Record $output.ToArray() -Zero:$zero; return }
                if ($invalid -eq 'fail') { $failed = $true }
                continue
            }
            $text = $result.Text
            # GNU pads to the input width only when the field starts with whitespace.
            if ($null -eq $delimiter -and $settings.Padding -eq 0 -and $settings.FormatWidth -eq 0 -and $field.Length -gt 0 -and [char]::IsWhiteSpace($field[0])) { $text = $text.PadLeft($field.Length) }
            $fields[$f] = $text
        }
        $joiner = ''
        if ($null -ne $delimiter) { $joiner = $delimiter }
        $output.Add(($fields -join $joiner) + $trailing)
    }
    ConvertTo-GnuRecordOutput -Record $output.ToArray() -Zero:$zero
    if ($failed) { $Context.ExitCode = 2 } elseif ($invalid -ne 'fail') { $Context.ExitCode = 0 }
}
