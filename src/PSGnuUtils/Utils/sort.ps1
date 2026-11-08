Register-GnuUtil @{
    Name         = 'sort'
    Category     = 'Text processing'
    Synopsis     = 'Sort lines of text files.'
    Usage        = @('sort [OPTION]... [FILE]...', 'sort [OPTION]... --files0-from=F')
    Description  = @('Write sorted concatenation of all FILE(s) to standard output.', '', 'With no FILE, or when FILE is -, read standard input.')
    FileOperands = $true
    UsageExitCode = 2   # GNU sort: 1 = disorder found by -c, 2 = trouble
    Options      = @(
        @{ Short = 'b'; Long = 'ignore-leading-blanks'; Help = 'ignore leading blanks' }
        @{ Short = 'd'; Long = 'dictionary-order'; Help = 'consider only blanks and alphanumeric characters' }
        @{ Short = 'f'; Long = 'ignore-case'; Help = 'fold lower case to upper case characters' }
        @{ Short = 'g'; Long = 'general-numeric-sort'; Key = 'mode'; Value = 'general'; Help = 'compare according to general numerical value' }
        @{ Short = 'i'; Long = 'ignore-nonprinting'; Help = 'consider only printable characters' }
        @{ Short = 'M'; Long = 'month-sort'; Key = 'mode'; Value = 'month'; Help = "compare (unknown) < 'JAN' < ... < 'DEC'" }
        @{ Short = 'h'; Long = 'human-numeric-sort'; Key = 'mode'; Value = 'human'; Help = 'compare human readable numbers (e.g., 2K 1G)' }
        @{ Short = 'n'; Long = 'numeric-sort'; Key = 'mode'; Value = 'numeric'; Help = 'compare according to string numerical value' }
        @{ Short = 'r'; Long = 'reverse'; Help = 'reverse the result of comparisons' }
        @{ Long = 'sort'; Arg = 'WORD'; Help = 'sort according to WORD: general-numeric -g, human-numeric -h, month -M, numeric -n, version -V' }
        @{ Short = 'V'; Long = 'version-sort'; Key = 'mode'; Value = 'version'; Help = 'natural sort of (version) numbers within text' }
        @{ Short = 'c'; Key = 'check'; Value = 'diagnose-first'; Help = 'check for sorted input; do not sort' }
        @{ Long = 'check'; Key = 'check-when'; Arg = 'WHEN'; OptionalArg = $true; Help = 'check for sorted input; WHEN is diagnose-first (default), quiet or silent' }
        @{ Short = 'C'; Key = 'check'; Value = 'quiet'; Help = 'like -c, but do not report first bad line' }
        @{ Long = 'files0-from'; Arg = 'F'; Help = 'read input from the files specified by NUL-terminated names in file F; If F is - then read names from standard input' }
        @{ Short = 'k'; Long = 'key'; Arg = 'KEYDEF'; Multi = $true; Help = 'sort via a key; KEYDEF gives location and type' }
        @{ Short = 'm'; Long = 'merge'; Help = 'merge already sorted files; do not sort (here: sorts, which gives the same result)' }
        @{ Short = 'o'; Long = 'output'; Arg = 'FILE'; Help = 'write result to FILE instead of standard output' }
        @{ Short = 's'; Long = 'stable'; Help = 'stabilize sort by disabling last-resort comparison' }
        @{ Short = 't'; Long = 'field-separator'; Arg = 'SEP'; Help = 'use SEP instead of non-blank to blank transition' }
        @{ Short = 'u'; Long = 'unique'; Help = 'with -c, check for strict ordering; without -c, output only the first of an equal run' }
        @{ Short = 'z'; Long = 'zero-terminated'; Help = 'line delimiter is NUL, not newline' }
    )
    Notes        = @(
        'KEYDEF is F[.C][OPTS][,F[.C][OPTS]] for start and stop position, where F is a',
        'field number and C a character position in the field; both are origin 1, and',
        'the stop position defaults to the line''s end.  If neither -t nor -b is in',
        'effect, characters in a field are counted from the beginning of the preceding',
        'whitespace.  OPTS is one or more single-letter ordering options [bdfgiMhnRrV],',
        'which override global ordering options for that key.  If no key is given, use',
        'the entire line as the key.',
        '',
        'PowerShell note: lines are compared ordinally (like LC_ALL=C); -R and --parallel are not supported.'
    )
}

function Invoke-GnuSort {
    <#
    .SYNOPSIS
    GNU sort: sort lines of text.

    .DESCRIPTION
    Sorts the lines of every FILE (or pipeline input) ordinally, numerically (-n), by general
    numbers (-g), human sizes (-h), versions (-V) or month names (-M), optionally by keys (-k)
    split at a separator (-t). -r reverses, -u keeps the first of equal lines, -s keeps input
    order for equal keys, -c / -C check instead of sorting, -o writes to a file.
    Enable the GNU name with: Enable-GnuAlias sort (replaces the sort -> Sort-Object alias).

    .EXAMPLE
    Get-Content sizes.txt | Invoke-GnuSort -h -r

    .EXAMPLE
    Invoke-GnuSort -t ',' -k 2,2n -k 1,1 data.csv
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'sort' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuSortLine -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

$script:GnuMonths = @{ JAN = 1; FEB = 2; MAR = 3; APR = 4; MAY = 5; JUN = 6; JUL = 7; AUG = 8; SEP = 9; OCT = 10; NOV = 11; DEC = 12 }

function ConvertFrom-GnuSortKeyDefinition {
    <#
    .SYNOPSIS
    Parses -k F[.C][OPTS][,F[.C][OPTS]]. Returns the key hashtable or a string error message.
    #>
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][hashtable]$Global)

    if ($Text -notmatch '^(?<sf>\d+)(\.(?<sc>\d+))?(?<so>[bdfgiMhnRrV]*)(,(?<ef>\d+)(\.(?<ec>\d+))?(?<eo>[bdfgiMhnRrV]*))?$') {
        return "invalid field specification '$Text'"
    }
    $startField = [int]$Matches['sf']
    if ($startField -eq 0) { return "field number is zero: invalid field specification '$Text'" }
    $startChar = 1
    if ($Matches.ContainsKey('sc')) { $startChar = [int]$Matches['sc'] }
    if ($startChar -eq 0) { return "character offset is zero: invalid field specification '$Text'" }
    $endField = 0
    $endChar = 0
    if ($Matches.ContainsKey('ef')) {
        $endField = [int]$Matches['ef']
        if ($endField -eq 0) { return "field number is zero: invalid field specification '$Text'" }
        if ($Matches.ContainsKey('ec')) { $endChar = [int]$Matches['ec'] }
    }
    $letters = $Matches['so'] + $Matches['eo']
    if ($letters.Contains('R')) { return "random sort (-R) is not supported: invalid field specification '$Text'" }

    $key = @{ StartField = $startField; StartChar = $startChar; EndField = $endField; EndChar = $endChar }
    if ($letters.Length -eq 0) {
        # GNU: a key without ordering options inherits the global ones.
        foreach ($name in @('Mode', 'Blanks', 'Dictionary', 'Fold', 'Printable', 'Reverse')) { $key[$name] = $Global[$name] }
        $key['StartBlanks'] = $Global['Blanks']
        $key['EndBlanks'] = $Global['Blanks']
        return $key
    }
    $key['Mode'] = 'string'
    $key['Blanks'] = $false   # for keys, -b is applied while extracting the key text
    if ($letters -cmatch 'n') { $key['Mode'] = 'numeric' }
    if ($letters -cmatch 'g') { $key['Mode'] = 'general' }
    if ($letters -cmatch 'h') { $key['Mode'] = 'human' }
    if ($letters -cmatch 'V') { $key['Mode'] = 'version' }
    if ($letters -cmatch 'M') { $key['Mode'] = 'month' }
    $key['Dictionary'] = $letters -cmatch 'd'
    $key['Fold'] = $letters -cmatch 'f'
    $key['Printable'] = $letters -cmatch 'i'
    $key['Reverse'] = $letters -cmatch 'r'
    $key['StartBlanks'] = $Matches['so'] -cmatch 'b'
    $key['EndBlanks'] = $Matches['eo'] -cmatch 'b'
    $key
}

function Get-GnuSortField {
    <#
    .SYNOPSIS
    Returns @{ Start; End } character positions of field N (1-based) in a line.
    .NOTES
    An empty Separator means blank-separated fields ([string] parameters turn $null into '').
    #>
    param([string]$Line, [int]$Field, [AllowNull()][string]$Separator)

    $position = 0
    for ($i = 1; $i -lt $Field; $i++) {
        if (-not [string]::IsNullOrEmpty($Separator)) {
            $next = $Line.IndexOf($Separator, $position, [System.StringComparison]::Ordinal)
            if ($next -lt 0) { return @{ Start = $Line.Length; End = $Line.Length } }
            $position = $next + 1
        }
        else {
            # Default fields: leading blanks belong to the field.
            while ($position -lt $Line.Length -and ($Line[$position] -eq ' ' -or $Line[$position] -eq "`t")) { $position++ }
            while ($position -lt $Line.Length -and $Line[$position] -ne ' ' -and $Line[$position] -ne "`t") { $position++ }
        }
    }
    $end = $Line.Length
    if (-not [string]::IsNullOrEmpty($Separator)) {
        $next = $Line.IndexOf($Separator, $position, [System.StringComparison]::Ordinal)
        if ($next -ge 0) { $end = $next }
    }
    else {
        $scan = $position
        while ($scan -lt $Line.Length -and ($Line[$scan] -eq ' ' -or $Line[$scan] -eq "`t")) { $scan++ }
        while ($scan -lt $Line.Length -and $Line[$scan] -ne ' ' -and $Line[$scan] -ne "`t") { $scan++ }
        $end = $scan
    }
    @{ Start = $position; End = $end }
}

function Get-GnuSortKeyText {
    <#
    .SYNOPSIS
    Extracts the text of one key from a line (before ordering transformations).
    #>
    param([string]$Line, [hashtable]$Key, [AllowNull()][string]$Separator)

    if ($Key.StartField -eq 0) { return $Line }   # whole line
    $field = Get-GnuSortField -Line $Line -Field $Key.StartField -Separator $Separator
    $start = $field.Start
    if ($Key.StartBlanks) { while ($start -lt $field.End -and ($Line[$start] -eq ' ' -or $Line[$start] -eq "`t")) { $start++ } }
    $start = [Math]::Min($Line.Length, $start + $Key.StartChar - 1)

    $end = $Line.Length
    if ($Key.EndField -gt 0) {
        $endField = Get-GnuSortField -Line $Line -Field $Key.EndField -Separator $Separator
        if ($Key.EndChar -eq 0) { $end = $endField.End }
        else {
            $fieldStart = $endField.Start
            if ($Key.EndBlanks) { while ($fieldStart -lt $endField.End -and ($Line[$fieldStart] -eq ' ' -or $Line[$fieldStart] -eq "`t")) { $fieldStart++ } }
            $end = [Math]::Min($Line.Length, $fieldStart + $Key.EndChar)
        }
    }
    if ($end -le $start) { return '' }
    $Line.Substring($start, $end - $start)
}

function ConvertTo-GnuSortValue {
    <#
    .SYNOPSIS
    Turns key text into the value that is compared, according to the key's mode and options.
    #>
    param([string]$Text, [hashtable]$Key)

    if ($Key.Blanks) { $Text = $Text.TrimStart(' ', "`t") }
    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    switch ($Key.Mode) {
        'numeric' {
            if ($Text -match '^\s*(-?(\d+(\.\d*)?|\.\d+))') { return [double]::Parse($Matches[1], $invariant) }
            return [double]0
        }
        'human' {
            if ($Text -match '^\s*(?<n>-?(\d+(\.\d*)?|\.\d+))(?<s>[KMGTPEZYRQk]?)') {
                $value = [double]::Parse($Matches['n'], $invariant)
                $power = 'KMGTPEZYRQ'.IndexOf([string]$Matches['s'].ToUpperInvariant(), [System.StringComparison]::Ordinal) + 1
                if ([string]::IsNullOrEmpty($Matches['s'])) { $power = 0 }
                # GNU compares the suffix first, then the number.
                return @(($power * [Math]::Sign($value)), $value)
            }
            return @(0, [double]0)
        }
        'general' {
            $value = [double]0
            if ([double]::TryParse($Text.Trim(), [System.Globalization.NumberStyles]::Float, $invariant, [ref]$value)) { return $value }
            if ($Text.Trim() -match '^(?i)[+-]?(inf|infinity)$') { if ($Text.Trim().StartsWith('-', [System.StringComparison]::Ordinal)) { return [double]::NegativeInfinity } return [double]::PositiveInfinity }
            return [double]::NaN   # GNU: non-numbers sort before all numbers
        }
        'month' {
            $word = $Text.Trim()
            if ($word.Length -ge 3 -and $script:GnuMonths.ContainsKey($word.Substring(0, 3).ToUpperInvariant())) { return $script:GnuMonths[$word.Substring(0, 3).ToUpperInvariant()] }
            return 0
        }
    }
    $builder = New-Object System.Text.StringBuilder
    foreach ($char in $Text.ToCharArray()) {
        if ($Key.Dictionary -and -not ([char]::IsLetterOrDigit($char) -or $char -eq ' ' -or $char -eq "`t")) { continue }
        if ($Key.Printable -and [char]::IsControl($char)) { continue }
        if ($Key.Fold) { $char = [char]::ToUpperInvariant($char) }
        [void]$builder.Append($char)
    }
    $builder.ToString()
}

function Compare-GnuVersion {
    <#
    .SYNOPSIS
    Natural comparison: runs of digits compare numerically, everything else ordinally.
    #>
    param([string]$Left, [string]$Right)

    $leftParts = [regex]::Matches($Left, '\d+|\D+')
    $rightParts = [regex]::Matches($Right, '\d+|\D+')
    for ($i = 0; $i -lt [Math]::Min($leftParts.Count, $rightParts.Count); $i++) {
        $a = $leftParts[$i].Value
        $b = $rightParts[$i].Value
        if ([char]::IsDigit($a[0]) -and [char]::IsDigit($b[0])) {
            $c = [System.Numerics.BigInteger]::Compare([System.Numerics.BigInteger]::Parse($a), [System.Numerics.BigInteger]::Parse($b))
        }
        else {
            $c = [string]::CompareOrdinal($a, $b)
        }
        if ($c -ne 0) { return [Math]::Sign($c) }
    }
    [Math]::Sign($leftParts.Count - $rightParts.Count)
}

function Compare-GnuSortValue {
    <#
    .SYNOPSIS
    Compares two key values of the same mode; returns -1, 0 or 1.
    #>
    param([AllowNull()][object]$Left, [AllowNull()][object]$Right, [string]$Mode)

    switch ($Mode) {
        'string' { return [Math]::Sign([string]::CompareOrdinal([string]$Left, [string]$Right)) }
        'version' { return Compare-GnuVersion -Left $Left -Right $Right }
        'human' {
            $c = $Left[0].CompareTo($Right[0])
            if ($c -ne 0) { return [Math]::Sign($c) }
            return [Math]::Sign($Left[1].CompareTo($Right[1]))
        }
    }
    # numeric, general, month: [double]::CompareTo puts NaN first, like GNU -g.
    [Math]::Sign(([double]$Left).CompareTo([double]$Right))
}

function Invoke-GnuSortLine {
    <#
    .SYNOPSIS
    Implementation of sort.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $mode = [string](Get-GnuOptionValue -Context $Context -Key 'mode' -Default 'string')
    if (Test-GnuOption -Context $Context -Key 'sort') {
        $word = [string](Get-GnuOptionValue -Context $Context -Key 'sort')
        $map = @{ 'general-numeric' = 'general'; 'human-numeric' = 'human'; 'month' = 'month'; 'numeric' = 'numeric'; 'version' = 'version' }
        if (-not $map.ContainsKey($word)) {
            Write-GnuUsageError -Context $Context -Message "invalid argument '$word' for '--sort'`nValid arguments are: 'general-numeric', 'human-numeric', 'month', 'numeric', 'version'"
            return
        }
        $mode = $map[$word]
    }
    $global = @{
        Mode       = $mode
        Blanks     = Test-GnuOption -Context $Context -Key 'ignore-leading-blanks'
        Dictionary = Test-GnuOption -Context $Context -Key 'dictionary-order'
        Fold       = Test-GnuOption -Context $Context -Key 'ignore-case'
        Printable  = Test-GnuOption -Context $Context -Key 'ignore-nonprinting'
        Reverse    = Test-GnuOption -Context $Context -Key 'reverse'
    }

    $separator = $null
    if (Test-GnuOption -Context $Context -Key 'field-separator') {
        $separator = [string](Get-GnuOptionValue -Context $Context -Key 'field-separator')
        if ($separator -eq '\0') { $separator = [string][char]0 }
        if ($separator.Length -ne 1) {
            Write-GnuUsageError -Context $Context -Message "multi-character tab '$separator'"
            return
        }
    }

    $keys = New-Object 'System.Collections.Generic.List[hashtable]'
    foreach ($text in @(Get-GnuOptionValue -Context $Context -Key 'key' -Default @())) {
        $key = ConvertFrom-GnuSortKeyDefinition -Text $text -Global $global
        if ($key -is [string]) {
            Write-GnuUsageError -Context $Context -Message $key
            return
        }
        $keys.Add($key)
    }
    if ($keys.Count -eq 0) {
        $whole = @{ StartField = 0 }
        foreach ($entry in $global.GetEnumerator()) { $whole[$entry.Key] = $entry.Value }
        $keys.Add($whole)
    }

    $check = $null
    if (Test-GnuOption -Context $Context -Key 'check') { $check = [string](Get-GnuOptionValue -Context $Context -Key 'check') }
    if (Test-GnuOption -Context $Context -Key 'check-when') {
        $when = [string](Get-GnuOptionValue -Context $Context -Key 'check-when')
        if ([string]::IsNullOrEmpty($when)) { $when = 'diagnose-first' }
        if (@('diagnose-first', 'quiet', 'silent') -notcontains $when) {
            Write-GnuUsageError -Context $Context -Message "invalid argument '$when' for '--check'`nValid arguments are: 'diagnose-first', 'quiet', 'silent'"
            return
        }
        $check = $when
    }

    # Inputs
    $zero = Test-GnuOption -Context $Context -Key 'zero-terminated'
    $operands = @($Context.Operands)
    if (Test-GnuOption -Context $Context -Key 'files0-from') {
        if ($operands.Count -gt 0) {
            Write-GnuUsageError -Context $Context -Message "extra operand '$($operands[0])'`nfile operands cannot be combined with --files0-from"
            return
        }
        $listText = Get-GnuInputText -Context $Context -Operand ([string](Get-GnuOptionValue -Context $Context -Key 'files0-from'))
        if ($null -eq $listText) { $Context.ExitCode = 2; return }
        $operands = @(Split-GnuRecord -Text $listText -Separator "`0")
    }
    if ($operands.Count -eq 0) { $operands = @('-') }
    if ($null -ne $check -and $operands.Count -gt 1) {
        Write-GnuUsageError -Context $Context -Message "extra operand '$($operands[1])' not allowed with -c"
        return
    }

    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($operand in $operands) {
        $errorsBefore = $Context.ErrorCount
        if ($zero) {
            $text = Get-GnuInputText -Context $Context -Operand $operand
            if ($null -ne $text) { foreach ($record in @(Split-GnuRecord -Text $text -Separator "`0")) { $lines.Add($record) } }
        }
        else {
            foreach ($line in @(Get-GnuInputLine -Context $Context -Operand $operand)) { $lines.Add($line) }
        }
        if ($Context.ErrorCount -gt $errorsBefore) { $Context.ExitCode = 2; return }   # GNU: sort stops when an input cannot be read
    }

    $records = New-Object 'System.Collections.Generic.List[object]'
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $values = @(foreach ($key in $keys) { , (ConvertTo-GnuSortValue -Text (Get-GnuSortKeyText -Line $lines[$i] -Key $key -Separator $separator) -Key $key) })
        $records.Add(@{ Line = $lines[$i]; Index = $i; Values = $values })
    }

    $stable = Test-GnuOption -Context $Context -Key 'stable'
    $unique = Test-GnuOption -Context $Context -Key 'unique'
    $reverseAll = $global.Reverse
    $compareKeys = {
        param($a, $b)
        for ($k = 0; $k -lt $keys.Count; $k++) {
            $c = Compare-GnuSortValue -Left $a.Values[$k] -Right $b.Values[$k] -Mode $keys[$k].Mode
            if ($keys[$k].Reverse) { $c = -$c }
            if ($c -ne 0) { return $c }
        }
        0
    }
    $compareFull = {
        param($a, $b)
        $c = & $compareKeys $a $b
        if ($c -ne 0) { return $c }
        if (-not $stable -and -not $unique) {
            # GNU's last-resort comparison: the whole line, byte by byte.
            $c = [Math]::Sign([string]::CompareOrdinal($a.Line, $b.Line))
            if ($reverseAll) { $c = -$c }
            if ($c -ne 0) { return $c }
        }
        $a.Index - $b.Index
    }

    if ($null -ne $check) {
        for ($i = 1; $i -lt $records.Count; $i++) {
            $c = & $compareFull $records[$i - 1] $records[$i]
            if ($c -gt 0 -or ($unique -and (& $compareKeys $records[$i - 1] $records[$i]) -eq 0)) {
                if ($check -eq 'diagnose-first') {
                    Write-GnuError -Context $Context -Message "$($operands[0]):$($i + 1): disorder: $($records[$i].Line)"
                }
                else {
                    $Context.ExitCode = 1
                }
                return
            }
        }
        return
    }

    $records.Sort([System.Comparison[object]]$compareFull)
    $output = New-Object 'System.Collections.Generic.List[string]'
    $previous = $null
    foreach ($record in $records) {
        if ($unique -and $null -ne $previous -and (& $compareKeys $previous $record) -eq 0) { continue }
        $output.Add($record.Line)
        $previous = $record
    }

    if (Test-GnuOption -Context $Context -Key 'output') {
        $target = [string](Get-GnuOptionValue -Context $Context -Key 'output')
        $terminator = "`n"
        if ($zero) { $terminator = "`0" }
        $content = ''
        if ($output.Count -gt 0) { $content = ($output -join $terminator) + $terminator }
        try { [System.IO.File]::WriteAllText((Resolve-GnuPath -Path $target), $content, $script:GnuUtf8) }
        catch { Write-GnuError -Context $Context -Message "open failed: $($target): $(Get-GnuErrorReason -Exception $_.Exception)" -ExitCode 2 }
        return
    }
    ConvertTo-GnuRecordOutput -Record $output.ToArray() -Zero:$zero
}
