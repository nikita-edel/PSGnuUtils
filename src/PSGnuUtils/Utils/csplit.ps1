Register-GnuUtil @{
    Name         = 'csplit'
    Category     = 'Text processing'
    Synopsis     = 'Split a file into sections determined by context lines.'
    Usage        = @('csplit [OPTION]... FILE PATTERN...')
    Description  = @(
        'Output pieces of FILE separated by PATTERN(s) to files ''xx00'', ''xx01'', ...,',
        'and output byte counts of each piece to standard output.',
        '',
        'Read standard input if FILE is -'
    )
    Options      = @(
        @{ Short = 'b'; Long = 'suffix-format'; Arg = 'FORMAT'; Help = 'use sprintf FORMAT instead of %02d' }
        @{ Short = 'f'; Long = 'prefix'; Arg = 'PREFIX'; Help = 'use PREFIX instead of ''xx''' }
        @{ Short = 'k'; Long = 'keep-files'; Help = 'do not remove output files on errors' }
        @{ Long = 'suppress-matched'; Help = 'suppress the lines matching PATTERN' }
        @{ Short = 'n'; Long = 'digits'; Arg = 'DIGITS'; Help = 'use specified number of digits instead of 2' }
        @{ Short = 's'; Long = 'quiet'; Key = 'quiet'; Help = 'do not print counts of output file sizes' }
        @{ Short = 'q'; Key = 'quiet'; Help = 'do not print counts of output file sizes' }
        @{ Long = 'silent'; Key = 'quiet'; Help = 'do not print counts of output file sizes' }
        @{ Short = 'z'; Long = 'elide-empty-files'; Help = 'remove empty output files' }
    )
    Notes        = @(
        'Each PATTERN may be:',
        '  INTEGER            copy up to but not including specified line number',
        '  /REGEXP/[OFFSET]   copy up to but not including a matching line',
        '  %REGEXP%[OFFSET]   skip to, but not including a matching line',
        '  {INTEGER}          repeat the previous pattern specified number of times',
        '  {*}                repeat the previous pattern as many times as possible',
        '',
        'A line OFFSET is a required ''+'' or ''-'' followed by a positive integer.',
        '',
        'PowerShell note: REGEXP is a POSIX basic regular expression translated to .NET',
        '(like grep); quote patterns such as {*} and %...% in PowerShell.'
    )
}

function Invoke-GnuCsplit {
    <#
    .SYNOPSIS
    GNU csplit: split a file into pieces at line numbers or lines matching regular expressions.

    .DESCRIPTION
    Writes the pieces of FILE to xx00, xx01, ... (-f PREFIX, -b FORMAT, -n DIGITS) and prints
    their sizes. PATTERNs are line numbers, /REGEXP/[OFFSET] (split before the match),
    %REGEXP%[OFFSET] (skip to the match) and {N} / {*} repetitions. On errors the files are
    removed unless -k.
    Enable the GNU name with: Enable-GnuUtil csplit

    .EXAMPLE
    Invoke-GnuCsplit -f chapter book.txt '/^Chapter/' '{*}'
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'csplit' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuCsplitFile -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function ConvertFrom-GnuCsplitPattern {
    <#
    .SYNOPSIS
    Parses the PATTERN operands. Returns @{ Patterns } or @{ Error } (warnings are written directly).
    #>
    param([Parameter(Mandatory)][hashtable]$Context, [Parameter(Mandatory)][string[]]$Operands)

    $patterns = New-Object 'System.Collections.Generic.List[hashtable]'
    $lastLine = 0
    foreach ($text in $Operands) {
        if ($text -match '^\{(.*)\}$') {
            if ($patterns.Count -eq 0) { return @{ Error = "'$text': invalid pattern" } }
            $inner = $Matches[1]
            if ($inner -eq '*') { $patterns[$patterns.Count - 1].Repeat = -1; continue }
            if ($inner -notmatch '^\d+$') { return @{ Error = "'{$inner'}: integer required between '{' and '}'" } }
            $patterns[$patterns.Count - 1].Repeat = [int]$inner
            continue
        }
        if ($text.Length -gt 0 -and ($text[0] -eq '/' -or $text[0] -eq '%')) {
            $delimiter = $text[0]
            $close = $text.LastIndexOf($delimiter)
            if ($close -le 0) { return @{ Error = "$($text): closing delimiter '$delimiter' missing" } }
            $offsetText = $text.Substring($close + 1)
            $offset = 0
            if ($offsetText.Length -gt 0) {
                if ($offsetText -notmatch '^[+-]\d+$') { return @{ Error = "'$text': integer expected after delimiter" } }
                $offset = [int]$offsetText
            }
            $converted = ConvertTo-GnuDotNetRegex -Pattern $text.Substring(1, $close - 1)
            $balance = 'ok'
            if (-not $converted.ContainsKey('Error')) { $balance = Get-GnuParenthesisBalance -Regex $converted.Regex }
            if ($converted.ContainsKey('Error') -or $balance -ne 'ok') { return @{ Error = "'$text': invalid regular expression: Invalid regular expression" } }
            $patterns.Add(@{ Text = $text; Kind = 'regex'; Skip = $delimiter -eq '%'; Regex = (New-Object regex -ArgumentList $converted.Regex); Offset = $offset; Repeat = 0 })
            continue
        }
        if ($text -notmatch '^\d+$') { return @{ Error = "'$text': invalid pattern" } }
        $line = [long]$text
        if ($line -eq 0) { return @{ Error = "0: line number must be greater than zero" } }
        if ($line -lt $lastLine) { return @{ Error = "line number '$text' is smaller than preceding line number, $lastLine" } }
        if ($line -eq $lastLine) { Write-GnuWarning -Context $Context -Message "warning: line number '$text' is the same as preceding line number" }
        $lastLine = $line
        $patterns.Add(@{ Text = $text; Kind = 'line'; Line = $line; Repeat = 0 })
    }
    @{ Patterns = $patterns }
}

function Open-GnuCsplitPiece {
    <#
    .SYNOPSIS
    Starts the next output piece (a byte buffer written when it is closed).
    #>
    param([Parameter(Mandatory)][hashtable]$State)
    $State.Piece = New-Object 'System.Collections.Generic.List[byte]'
}

function Close-GnuCsplitPiece {
    <#
    .SYNOPSIS
    Writes the current piece to the next file name and prints its size (empty pieces are dropped with -z).
    #>
    param([Parameter(Mandatory)][hashtable]$State)
    if ($null -eq $State.Piece) { return }
    $bytes = $State.Piece.ToArray()
    $State.Piece = $null
    if ($State.Elide -and $bytes.Length -eq 0) { return }
    $name = $State.Prefix + $State.Suffix.Prefix + (Format-GnuPrintfInteger -Value $State.Number -Conversion $State.Suffix.Conversion -Flags $State.Suffix.Flags -Width $State.Suffix.Width -Precision $State.Suffix.Precision) + $State.Suffix.Rest
    $State.Number++
    [System.IO.File]::WriteAllBytes((Resolve-GnuPath -Path $name), [byte[]]$bytes)
    $State.Created.Add($name)
    if (-not $State.Quiet) { $State.Output.Add([string]$bytes.Length) }
}

function Add-GnuCsplitLine {
    <#
    .SYNOPSIS
    Appends input line Index (0-based) to the current piece.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][long]$Index)
    $range = $State.Records[$Index]
    for ($i = $range[0]; $i -lt $range[1]; $i++) { $State.Piece.Add($State.Data[$i]) }
}

function Stop-GnuCsplit {
    <#
    .SYNOPSIS
    A fatal pattern error: the rest of the input goes to the open piece, then the files are removed unless -k.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][string]$Message)
    Write-GnuError -Context $State.Context -Message $Message
    if ($null -ne $State.Piece) {
        for ($i = $State.First; $i -lt $State.Records.Count; $i++) { Add-GnuCsplitLine -State $State -Index $i }
        Close-GnuCsplitPiece -State $State
    }
    if (-not $State.Keep) { foreach ($name in $State.Created) { Remove-Item -LiteralPath (Resolve-GnuPath -Path $name) -Force -ErrorAction SilentlyContinue } }
    $State.Failed = $true
}

function Invoke-GnuCsplitFile {
    <#
    .SYNOPSIS
    Implementation of csplit (the GNU algorithm: lines are numbered from 1, a piece ends before the split line).
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $operands = @($Context.Operands)
    if ($operands.Count -eq 0) { Write-GnuUsageError -Context $Context -Message 'missing operand'; return }
    if ($operands.Count -eq 1) { Write-GnuUsageError -Context $Context -Message "missing operand after '$($operands[0])'"; return }

    $digits = 2
    if (Test-GnuOption -Context $Context -Key 'digits') {
        $text = [string](Get-GnuOptionValue -Context $Context -Key 'digits')
        if ($text -notmatch '^\d+$') { Write-GnuError -Context $Context -Message "invalid number: '$text'"; return }
        $digits = [int]$text
    }
    $format = "%0$($digits)d"
    if (Test-GnuOption -Context $Context -Key 'suffix-format') { $format = [string](Get-GnuOptionValue -Context $Context -Key 'suffix-format') }
    $directives = @([regex]::Matches($format, '%%|%') | Where-Object { $_.Value -eq '%' })
    if ($directives.Count -eq 0) { Write-GnuError -Context $Context -Message 'missing % conversion specification in suffix'; return }
    if ($directives.Count -gt 1) { Write-GnuError -Context $Context -Message 'too many % conversion specifications in suffix'; return }
    $at = $directives[0].Index
    $spec = [regex]::Match($format.Substring($at), "^%([-#0']*)(\d*)(?:\.(\d*))?(.)?")
    $conversion = $spec.Groups[4].Value
    if ('diuoxX'.IndexOf($conversion, [System.StringComparison]::Ordinal) -lt 0 -or $conversion.Length -eq 0) {
        Write-GnuError -Context $Context -Message "invalid conversion specifier in suffix: $conversion"
        return
    }
    $precision = -1
    if ($spec.Groups[3].Success) { $precision = 0; if ($spec.Groups[3].Value.Length -gt 0) { $precision = [int]$spec.Groups[3].Value } }
    $width = 0
    if ($spec.Groups[2].Value.Length -gt 0) { $width = [int]$spec.Groups[2].Value }
    $suffix = @{
        Prefix = $format.Substring(0, $at).Replace('%%', '%'); Rest = $format.Substring($at + $spec.Length).Replace('%%', '%')
        Conversion = $conversion.Replace('i', 'd'); Flags = $spec.Groups[1].Value; Width = $width; Precision = $precision
    }

    $parsed = ConvertFrom-GnuCsplitPattern -Context $Context -Operands @($operands | Select-Object -Skip 1)
    if ($parsed.ContainsKey('Error')) { Write-GnuError -Context $Context -Message $parsed.Error; return }
    $data = Get-GnuInputBytes -Context $Context -Operand $operands[0]
    if ($null -eq $data) { return }
    [byte[]]$data = $data

    $prefix = 'xx'
    if (Test-GnuOption -Context $Context -Key 'prefix') { $prefix = [string](Get-GnuOptionValue -Context $Context -Key 'prefix') }
    $state = @{
        Context = $Context; Data = $data; Records = (Get-GnuSplitRecord -Data $data -Separator 10); First = [long]0; Next = [long]0
        Piece = $null; Number = 0; Created = New-Object 'System.Collections.Generic.List[string]'; Output = New-Object 'System.Collections.Generic.List[string]'
        Prefix = $prefix; Suffix = $suffix; Quiet = Test-GnuOption -Context $Context -Key 'quiet'; Elide = Test-GnuOption -Context $Context -Key 'elide-empty-files'
        Keep = Test-GnuOption -Context $Context -Key 'keep-files'; Suppress = Test-GnuOption -Context $Context -Key 'suppress-matched'; Failed = $false
    }
    try { Invoke-GnuCsplitPattern -State $state -Patterns $parsed.Patterns }
    finally { $state.Output }
}

function Invoke-GnuCsplitPattern {
    <#
    .SYNOPSIS
    Applies the patterns to the input lines; the rest of the input becomes the last piece.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][System.Collections.Generic.List[hashtable]]$Patterns)

    $total = $State.Records.Count
    foreach ($pattern in $Patterns) {
        $repetition = 0
        while ($pattern.Repeat -eq -1 -or $repetition -le $pattern.Repeat) {
            $suffix = ''
            if ($repetition -gt 0) { $suffix = " on repetition $repetition" }
            if ($pattern.Kind -eq 'line') {
                # Copy up to, but not including, line LINE (LINE, 2*LINE, ... with repetitions).
                $target = $pattern.Line * ($repetition + 1)
                Open-GnuCsplitPiece -State $State
                if ($target -gt $total) { Stop-GnuCsplit -State $State -Message "'$($pattern.Text)': line number out of range$suffix"; return }
                for ($i = $State.First; $i -lt $target - 1; $i++) { Add-GnuCsplitLine -State $State -Index $i }
                Close-GnuCsplitPiece -State $State
                $State.First = [Math]::Max($State.First, $target - 1)
                $State.Next = $State.First
                if ($State.Suppress -and $State.First -lt $total) { $State.First++; $State.Next++ }
            }
            else {
                if (-not $pattern.Skip) { Open-GnuCsplitPiece -State $State }
                $match = -1
                for ($i = $State.Next; $i -lt $total; $i++) {
                    $range = $State.Records[$i]
                    $line = $script:GnuUtf8.GetString($State.Data, [int]$range[0], [int]($range[1] - $range[0])).TrimEnd("`n").TrimEnd("`r")
                    if ($pattern.Regex.IsMatch($line)) { $match = $i; break }
                }
                if ($match -lt 0) {
                    if ($pattern.Repeat -eq -1 -and $repetition -gt 0) {
                        # {*} ends at the last match: the rest goes to this piece (or is skipped with %%).
                        if (-not $pattern.Skip) {
                            for ($i = $State.First; $i -lt $total; $i++) { Add-GnuCsplitLine -State $State -Index $i }
                            Close-GnuCsplitPiece -State $State
                        }
                        $State.First = $total
                        $State.Done = $true
                        return
                    }
                    Stop-GnuCsplit -State $State -Message "'$($pattern.Text)': match not found$suffix"
                    return
                }
                $break = $match + $pattern.Offset
                if ($break -lt $State.First -or $break -gt $total) {
                    Stop-GnuCsplit -State $State -Message "'$($pattern.Text)': line number out of range$suffix"
                    return
                }
                if (-not $pattern.Skip) {
                    for ($i = $State.First; $i -lt $break; $i++) { Add-GnuCsplitLine -State $State -Index $i }
                    Close-GnuCsplitPiece -State $State
                }
                $State.First = $break
                $State.Next = $break + 1
                if ($State.Suppress -and $State.First -lt $total -and $pattern.Offset -eq 0) { $State.First++ }
            }
            $repetition++
        }
    }
    Open-GnuCsplitPiece -State $State
    for ($i = $State.First; $i -lt $total; $i++) { Add-GnuCsplitLine -State $State -Index $i }
    Close-GnuCsplitPiece -State $State
}
