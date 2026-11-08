Register-GnuUtil @{
    Name         = 'split'
    Category     = 'Text processing'
    Synopsis     = 'Split a file into pieces.'
    Usage        = @('split [OPTION]... [FILE [PREFIX]]')
    Description  = @(
        'Output pieces of FILE to PREFIXaa, PREFIXab, ...;',
        'default size is 1000 lines, and default PREFIX is ''x''.',
        '',
        'With no FILE, or when FILE is -, read standard input.'
    )
    Options      = @(
        @{ Short = 'a'; Long = 'suffix-length'; Arg = 'N'; Help = 'generate suffixes of length N (default 2)' }
        @{ Long = 'additional-suffix'; Arg = 'SUFFIX'; Help = 'append an additional SUFFIX to file names' }
        @{ Short = 'b'; Long = 'bytes'; Arg = 'SIZE'; Help = 'put SIZE bytes per output file' }
        @{ Short = 'C'; Long = 'line-bytes'; Arg = 'SIZE'; Help = 'put at most SIZE bytes of records per output file' }
        @{ Short = 'd'; Key = 'numeric'; Value = '0'; Help = 'use numeric suffixes starting at 0, not alphabetic' }
        @{ Long = 'numeric-suffixes'; Key = 'numeric'; Arg = 'FROM'; OptionalArg = $true; Help = 'same as -d, but allow setting the start value' }
        @{ Short = 'x'; Key = 'hex'; Value = '0'; Help = 'use hex suffixes starting at 0, not alphabetic' }
        @{ Long = 'hex-suffixes'; Key = 'hex'; Arg = 'FROM'; OptionalArg = $true; Help = 'same as -x, but allow setting the start value' }
        @{ Short = 'e'; Long = 'elide-empty-files'; Help = 'do not generate empty output files with ''-n''' }
        @{ Long = 'filter'; Arg = 'COMMAND'; Help = 'write to shell COMMAND; file name is $FILE (not supported)' }
        @{ Short = 'l'; Long = 'lines'; Arg = 'NUMBER'; Help = 'put NUMBER lines/records per output file' }
        @{ Short = 'n'; Long = 'number'; Arg = 'CHUNKS'; Help = 'generate CHUNKS output files; see explanation below' }
        @{ Short = 't'; Long = 'separator'; Arg = 'SEP'; Help = 'use SEP instead of newline as the record separator; ''\0'' (zero) specifies the NUL character' }
        @{ Short = 'u'; Long = 'unbuffered'; Help = 'immediately copy input to output with ''-n r/...''' }
        @{ Long = 'verbose'; Help = 'print a diagnostic just before each output file is opened' }
    )
    Notes        = @(
        'The SIZE argument is an integer and optional unit (example: 10K is 10*1024).',
        'Units are K,M,G,T,P,E,Z,Y (powers of 1024) or KB,MB,... (powers of 1000).',
        'Binary prefixes can be used, too: KiB=K, MiB=M, and so on.',
        '',
        'CHUNKS may be:',
        '  N       split into N files based on size of input',
        '  K/N     output Kth of N to stdout',
        '  l/N     split into N files without splitting lines/records',
        '  l/K/N   output Kth of N to stdout without splitting lines/records',
        '  r/N     like ''l'' but use round robin distribution',
        '  r/K/N   likewise but only output Kth of N to stdout',
        '',
        'PowerShell note: --filter is not supported; -u has no effect. Output to stdout',
        '(K/N) is written as text lines. --hex-suffixes=FROM accepts hex digits a-f',
        '(GNU 8.32 produces names with punctuation for them).'
    )
}

function Invoke-GnuSplit {
    <#
    .SYNOPSIS
    GNU split: split a file into pieces.

    .DESCRIPTION
    Writes FILE (or the pipeline) to PREFIXaa, PREFIXab, ... with 1000 lines each, or -l lines,
    -b bytes, -C bytes of whole lines, or -n chunks (N, K/N, l/N, l/K/N, r/N, r/K/N). Suffixes
    are alphabetic, numeric (-d) or hex (-x), and grow automatically when needed.
    Enable the GNU name with: Enable-GnuAlias split

    .EXAMPLE
    Invoke-GnuSplit -b 100M -d backup.tar backup.tar.part
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'split' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuSplitFile -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function New-GnuSplitNamer {
    <#
    .SYNOPSIS
    The state of GNU split's file name generator (prefix, suffix alphabet, indexes, automatic widening).
    #>
    param(
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)][string]$Alphabet,
        [Parameter(Mandatory)][int]$Length,
        [AllowEmptyString()][string]$Additional = '',
        [AllowEmptyString()][string]$Start = '',
        [switch]$Auto
    )
    $indexes = New-Object int[] $Length
    for ($i = 0; $i -lt $Start.Length; $i++) { $indexes[$Length - $Start.Length + $i] = $Alphabet.IndexOf($Start[$i]) }
    @{ Prefix = $Prefix; Alphabet = $Alphabet; Indexes = $indexes; Additional = $Additional; Auto = [bool]$Auto; First = $true }
}

function Get-GnuSplitName {
    <#
    .SYNOPSIS
    The next output file name, or $null when the suffixes are exhausted.
    #>
    param([Parameter(Mandatory)][hashtable]$Namer)

    if (-not $Namer.First) {
        $base = $Namer.Alphabet.Length
        $i = $Namer.Indexes.Length - 1
        while ($true) {
            if ($i -lt 0) { return $null }
            $Namer.Indexes[$i]++
            if ($Namer.Auto -and $i -eq 0 -and $Namer.Indexes[0] -eq $base - 1) {
                # Widen like GNU: the first suffix character joins the prefix, the suffix gets one longer.
                $Namer.Prefix += $Namer.Alphabet[$base - 1]
                $Namer.Indexes = New-Object int[] ($Namer.Indexes.Length + 1)
                break
            }
            if ($Namer.Indexes[$i] -lt $base) { break }
            $Namer.Indexes[$i] = 0
            $i--
        }
    }
    $Namer.First = $false
    $Namer.Prefix + (-join @($Namer.Indexes | ForEach-Object { $Namer.Alphabet[$_] })) + $Namer.Additional
}

function Write-GnuSplitFile {
    <#
    .SYNOPSIS
    Creates the next output file with the given bytes. Returns $false if the names are exhausted or writing failed.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)

    $name = Get-GnuSplitName -Namer $State.Namer
    if ($null -eq $name) { Write-GnuError -Context $State.Context -Message 'output file suffixes exhausted'; return $false }
    $path = Resolve-GnuPath -Path $name
    if ($null -ne $State.InputPath -and (Test-GnuSamePath -Left $path -Right $State.InputPath)) {
        Write-GnuError -Context $State.Context -Message "'$name' would overwrite input; aborting"
        return $false
    }
    # GNU prints this on standard output.
    if ($State.Verbose) { $State.Messages.Add("creating file '$name'") }
    try { [System.IO.File]::WriteAllBytes($path, $Bytes) }
    catch { Write-GnuError -Context $State.Context -Message "$($name): $(Get-GnuErrorReason -Exception $_.Exception)"; return $false }
    $true
}

function Get-GnuSplitRecord {
    <#
    .SYNOPSIS
    The [start, end) byte ranges of the records (lines) of Data, each including its separator.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Data, [Parameter(Mandatory)][byte]$Separator)
    $records = New-Object 'System.Collections.Generic.List[long[]]'
    $start = 0
    for ($i = 0; $i -lt $Data.Length; $i++) {
        if ($Data[$i] -eq $Separator) { $records.Add([long[]]@($start, ($i + 1))); $start = $i + 1 }
    }
    if ($start -lt $Data.Length) { $records.Add([long[]]@($start, $Data.Length)) }
    , $records
}

function Get-GnuSplitSlice {
    <#
    .SYNOPSIS
    Bytes [Start, End) of Data.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Data, [Parameter(Mandatory)][long]$Start, [Parameter(Mandatory)][long]$End)
    $slice = New-Object byte[] ([Math]::Max(0, $End - $Start))
    if ($slice.Length -gt 0) { [array]::Copy($Data, $Start, $slice, 0, $slice.Length) }
    , $slice
}

function Invoke-GnuSplitFile {
    <#
    .SYNOPSIS
    Implementation of split.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $operands = @($Context.Operands)
    if ($operands.Count -gt 2) { Write-GnuUsageError -Context $Context -Message "extra operand '$($operands[2])'"; return }
    if (Test-GnuOption -Context $Context -Key 'filter') { Write-GnuError -Context $Context -Message '--filter is not supported'; return }
    $inputName = '-'
    if ($operands.Count -ge 1) { $inputName = $operands[0] }
    $prefix = 'x'
    if ($operands.Count -eq 2) { $prefix = $operands[1] }

    $modes = @('lines', 'bytes', 'line-bytes', 'number') | Where-Object { Test-GnuOption -Context $Context -Key $_ }
    if (@($modes).Count -gt 1) { Write-GnuUsageError -Context $Context -Message 'cannot split in more than one way'; return }
    $mode = 'lines'
    if (@($modes).Count -eq 1) { $mode = @($modes)[0] }

    $separator = [byte]10
    if (Test-GnuOption -Context $Context -Key 'separator') {
        $text = [string](Get-GnuOptionValue -Context $Context -Key 'separator')
        if ($text -eq '\0') { $separator = [byte]0 }
        elseif ($text.Length -eq 0) { Write-GnuError -Context $Context -Message 'empty record separator'; return }
        elseif ($text.Length -gt 1) { Write-GnuError -Context $Context -Message "multi-character separator '$text'"; return }
        else { $separator = [byte][char]$text }
    }

    $count = [long]1000
    $chunk = $null
    if ($mode -eq 'number') {
        $text = [string](Get-GnuOptionValue -Context $Context -Key 'number')
        $match = [regex]::Match($text, '^(?:([lr])/)?(?:(\d+)/)?(\d+)$')
        if (-not $match.Success) { Write-GnuError -Context $Context -Message "invalid number of chunks: '$text'"; return }
        if ([long]$match.Groups[3].Value -eq 0) { Write-GnuError -Context $Context -Message "invalid number of chunks: '$($match.Groups[3].Value)': Numerical result out of range"; return }
        $chunk = @{ Kind = $match.Groups[1].Value; Count = [long]$match.Groups[3].Value; Only = 0 }
        if ($match.Groups[2].Success) {
            $chunk.Only = [long]$match.Groups[2].Value
            if ($chunk.Only -eq 0 -or $chunk.Only -gt $chunk.Count) { Write-GnuError -Context $Context -Message "invalid chunk number: '$($match.Groups[2].Value)': Numerical result out of range"; return }
        }
    }
    elseif (Test-GnuOption -Context $Context -Key $mode) {
        $text = [string](Get-GnuOptionValue -Context $Context -Key $mode)
        $value = ConvertFrom-GnuSize -Text $text
        $what = @{ lines = 'lines'; bytes = 'bytes'; 'line-bytes' = 'bytes' }[$mode]
        if ($null -eq $value) { Write-GnuError -Context $Context -Message "invalid number of $($what): '$text'"; return }
        if ($value -eq 0) { Write-GnuError -Context $Context -Message "invalid number of $($what): '$text': Numerical result out of range"; return }
        $count = ConvertTo-GnuInt64 -Value $value
    }

    $alphabet = 'abcdefghijklmnopqrstuvwxyz'
    $start = ''
    foreach ($entry in @(@('numeric', '0123456789'), @('hex', '0123456789abcdef'))) {
        if (-not (Test-GnuOption -Context $Context -Key $entry[0])) { continue }
        $alphabet = $entry[1]
        $start = [string](Get-GnuOptionValue -Context $Context -Key $entry[0])
        if ([string]::IsNullOrEmpty($start)) { $start = '0' }
        $pattern = '^[0-9]+$'
        if ($entry[0] -eq 'hex') { $pattern = '^[0-9a-fA-F]+$' }
        if ($start -notmatch $pattern) { Write-GnuError -Context $Context -Message "invalid number: '$start'"; return }
        $start = $start.ToLowerInvariant().TrimStart('0')
    }
    $lengthGiven = Test-GnuOption -Context $Context -Key 'suffix-length'
    $length = 2
    if ($lengthGiven) {
        $text = [string](Get-GnuOptionValue -Context $Context -Key 'suffix-length')
        if ($text -notmatch '^\d+$' -or [int]$text -eq 0) { Write-GnuError -Context $Context -Message "invalid suffix length: '$text'"; return }
        $length = [int]$text
    }
    $needed = [Math]::Max(1, $start.Length)
    if ($null -ne $chunk) {
        $files = [long]$chunk.Count - 1
        if ($start.Length -gt 0) { $files += [System.Convert]::ToInt64($start, $alphabet.Length) }
        $needed = 1
        while ($files -ge [Math]::Pow($alphabet.Length, $needed)) { $needed++ }
        if (-not $lengthGiven) { $length = [Math]::Max($length, $needed) }
    }
    if ($length -lt $needed) { Write-GnuError -Context $Context -Message "the suffix length needs to be at least $needed"; return }
    $additional = [string](Get-GnuOptionValue -Context $Context -Key 'additional-suffix' -Default '')
    if ($additional.Contains('/') -or $additional.Contains('\')) { Write-GnuError -Context $Context -Message "invalid suffix '$additional', contains directory separator"; return }

    $data = Get-GnuInputBytes -Context $Context -Operand $inputName
    if ($null -eq $data) { return }
    $inputPath = $null
    if ($inputName -ne '-') { $inputPath = Resolve-GnuPath -Path $inputName }
    $state = @{
        Context  = $Context
        Namer    = (New-GnuSplitNamer -Prefix $prefix -Alphabet $alphabet -Length $length -Additional $additional -Start $start -Auto:(-not $lengthGiven -and $null -eq $chunk -and [string]::IsNullOrEmpty($start)))
        Verbose  = Test-GnuOption -Context $Context -Key 'verbose'
        Messages = New-Object 'System.Collections.Generic.List[string]'
        InputPath = $inputPath
    }
    $elide = Test-GnuOption -Context $Context -Key 'elide-empty-files'
    [byte[]]$data = $data
    try { Invoke-GnuSplitWrite -State $state -Data $data -Chunk $chunk -Mode $mode -Count $count -Separator $separator -Elide:$elide }
    finally { $state.Messages }
}

function Invoke-GnuSplitWrite {
    <#
    .SYNOPSIS
    Writes the output files of split (or the selected chunk to standard output).
    #>
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Data,
        [AllowNull()][hashtable]$Chunk,
        [Parameter(Mandatory)][string]$Mode,
        [Parameter(Mandatory)][long]$Count,
        [Parameter(Mandatory)][byte]$Separator,
        [switch]$Elide
    )
    $state = $State
    $data = $Data
    $chunk = $Chunk
    $mode = $Mode
    $count = $Count
    $separator = $Separator
    $elide = [bool]$Elide

    if ($null -ne $chunk) {
        $total = [long]$data.Length
        $pieces = New-Object 'System.Collections.Generic.List[object]'
        if ($chunk.Kind -eq 'r') {
            $lists = @(for ($k = 0; $k -lt $chunk.Count; $k++) { , (New-Object 'System.Collections.Generic.List[byte]') })
            $index = 0
            foreach ($record in (Get-GnuSplitRecord -Data $data -Separator $separator)) {
                $lists[$index % $chunk.Count].AddRange([byte[]](Get-GnuSplitSlice -Data $data -Start $record[0] -End $record[1]))
                $index++
            }
            foreach ($list in $lists) { $pieces.Add($list.ToArray()) }
        }
        else {
            $records = $null
            if ($chunk.Kind -eq 'l') { $records = Get-GnuSplitRecord -Data $data -Separator $separator }
            $next = 0
            for ($k = 1; $k -le $chunk.Count; $k++) {
                # GNU: chunks of size/N bytes, the last one takes the rest.
                $size = [long][Math]::Floor($total / $chunk.Count)
                $from = ($k - 1) * $size
                $to = $k * $size
                if ($k -eq $chunk.Count) { $to = $total }
                if ($null -ne $records) {
                    # A record belongs to the chunk that contains its first byte.
                    $begin = $null
                    $end = $null
                    while ($next -lt $records.Count -and $records[$next][0] -lt $to) {
                        if ($null -eq $begin) { $begin = $records[$next][0] }
                        $end = $records[$next][1]
                        $next++
                    }
                    if ($null -eq $begin) { $pieces.Add([byte[]]@()) } else { $pieces.Add((Get-GnuSplitSlice -Data $data -Start $begin -End $end)) }
                }
                else { $pieces.Add((Get-GnuSplitSlice -Data $data -Start $from -End $to)) }
            }
        }
        if ($chunk.Only -gt 0) {
            ConvertTo-GnuOutputLine -Text $script:GnuUtf8.GetString([byte[]]$pieces[$chunk.Only - 1])
            return
        }
        foreach ($piece in $pieces) {
            if ($elide -and $piece.Length -eq 0) { continue }
            if (-not (Write-GnuSplitFile -State $state -Bytes $piece)) { return }
        }
        return
    }

    switch ($mode) {
        'bytes' {
            for ($offset = [long]0; $offset -lt $data.Length; $offset += $count) {
                if (-not (Write-GnuSplitFile -State $state -Bytes (Get-GnuSplitSlice -Data $data -Start $offset -End ([Math]::Min($data.Length, $offset + $count))))) { return }
            }
        }
        'line-bytes' {
            $begin = [long]0
            $end = [long]0
            foreach ($record in (Get-GnuSplitRecord -Data $data -Separator $separator)) {
                if ($record[1] - $begin -le $count) { $end = $record[1]; continue }
                if ($end -gt $begin) {
                    if (-not (Write-GnuSplitFile -State $state -Bytes (Get-GnuSplitSlice -Data $data -Start $begin -End $end))) { return }
                    $begin = $end
                }
                # A record longer than SIZE is split into SIZE pieces.
                while ($record[1] - $begin -gt $count) {
                    if (-not (Write-GnuSplitFile -State $state -Bytes (Get-GnuSplitSlice -Data $data -Start $begin -End ($begin + $count)))) { return }
                    $begin += $count
                }
                $end = $record[1]
            }
            if ($end -gt $begin) { $null = Write-GnuSplitFile -State $state -Bytes (Get-GnuSplitSlice -Data $data -Start $begin -End $end) }
        }
        default {
            $records = Get-GnuSplitRecord -Data $data -Separator $separator
            for ($i = 0; $i -lt $records.Count; $i += $count) {
                $last = [Math]::Min($records.Count, $i + $count) - 1
                if (-not (Write-GnuSplitFile -State $state -Bytes (Get-GnuSplitSlice -Data $data -Start $records[$i][0] -End $records[$last][1]))) { return }
            }
        }
    }
}
