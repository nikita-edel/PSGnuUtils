Register-GnuUtil @{
    Name            = 'tail'
    Category        = 'Viewing file contents'
    Synopsis        = 'Output the last part of files.'
    Usage           = @('tail [OPTION]... [FILE]...')
    Description     = @(
        'Print the last 10 lines of each FILE to standard output.',
        'With more than one FILE, precede each with a header giving the file name.',
        '',
        'With no FILE, or when FILE is -, read standard input.'
    )
    FileOperands    = $true
    NumericOption   = 'n'
    OpenErrorFormat = "cannot open '{0}' for reading: {1}"
    ReadErrorFormat = "error reading '{0}': {1}"
    Options         = @(
        @{ Short = 'f'; Key = 'follow'; Value = 'descriptor'; Help = 'output appended data as the file grows' }
        @{ Long = 'follow'; Arg = 'HOW'; OptionalArg = $true; Help = 'like -f; --follow=name follows the file name (re-opening it), --follow=descriptor (the default) the open file' }
        @{ Short = 'F'; Key = 'follow'; Value = 'name'; Sets = @{ retry = 1 }; Help = 'same as --follow=name --retry' }
        @{ Long = 'max-unchanged-stats'; Arg = 'N'; Help = 'accepted for compatibility (files are always checked by size)' }
        @{ Long = 'pid'; Arg = 'PID'; Help = 'with -f, terminate after process ID, PID dies' }
        @{ Long = 'retry'; Help = 'keep trying to open a file if it is inaccessible' }
        @{ Short = 's'; Long = 'sleep-interval'; Arg = 'N'; Help = 'with -f, sleep for approximately N seconds (default 1.0) between iterations' }
        @{ Short = 'c'; Long = 'bytes'; Key = 'count'; Arg = '[+]NUM'; Sets = @{ unit = 'bytes' }; Help = 'output the last NUM bytes; or use -c +NUM to output starting with byte NUM of each file' }
        @{ Short = 'n'; Long = 'lines'; Key = 'count'; Arg = '[+]NUM'; Sets = @{ unit = 'lines' }; Help = 'output the last NUM lines, instead of the last 10; or use -n +NUM to skip NUM-1 lines at the start' }
        @{ Short = 'q'; Long = 'quiet'; Key = 'headers'; Value = 'never'; Help = 'never output headers giving file names' }
        @{ Long = 'silent'; Key = 'headers'; Value = 'never'; Help = 'same as --quiet' }
        @{ Short = 'v'; Long = 'verbose'; Key = 'headers'; Value = 'always'; Help = 'always output headers giving file names' }
        @{ Short = 'z'; Long = 'zero-terminated'; Help = 'line delimiter is NUL, not newline' }
    )
    Notes           = @(
        'NUM may have a multiplier suffix:',
        'b 512, kB 1000, K 1024, MB 1000*1000, M 1024*1024,',
        'GB 1000*1000*1000, G 1024*1024*1024, and so on for T, P, E, Z, Y, R, Q.',
        'Binary prefixes can be used, too: KiB=K, MiB=M, and so on.',
        '',
        'With --follow (-f), tail defaults to following the file descriptor, which',
        'means that even if a tail''ed file is renamed, tail will continue to track',
        'its end.  This default behavior is not desirable when you really want to',
        'track the actual name of the file, not the file descriptor (e.g., log',
        'rotation).  Use --follow=name in that case.',
        '',
        'PowerShell note: following stops with Ctrl+C, when --pid dies, or when a later',
        'command stops the pipeline (Select-Object -First). Files are polled; an',
        'unfinished last line is printed once the file stops growing.'
    )
}

function Invoke-GnuTail {
    <#
    .SYNOPSIS
    GNU tail: output the last part of files.

    .DESCRIPTION
    Prints the last 10 lines (or -n NUM lines, or -c NUM bytes) of each FILE. -n +NUM starts
    at line NUM instead. tail -5 is short for tail -n 5.
    Enable the GNU name with: Enable-GnuAlias tail

    .EXAMPLE
    Invoke-GnuTail -n 20 app.log

    .EXAMPLE
    Get-Content data.csv | Invoke-GnuTail -n +2

    Everything except the header line.
    #>
    begin {
        $ctx = Initialize-GnuUtil -Name 'tail' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput
        if (-not $ctx.Done) { $tail = New-GnuHeadTailState -Context $ctx -AllowSuffixSign '+' }
    }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) {
            Invoke-GnuHeadTailOperand -Context $ctx -State $tail -Mode 'tail'
            if (Test-GnuOption -Context $ctx -Key 'follow') { Invoke-GnuTailFollow -Context $ctx }
        }
        Complete-GnuUtil -Context $ctx
    }
}

function Wait-GnuTailInterval {
    <#
    .SYNOPSIS
    Sleeps between polls of tail -f (mockable in tests).
    #>
    param([Parameter(Mandatory)][double]$Seconds)
    Start-Sleep -Milliseconds ([int][Math]::Max(1, $Seconds * 1000))
}

function Test-GnuProcessAlive {
    <#
    .SYNOPSIS
    $true while the process with this ID exists (tail --pid).
    #>
    param([Parameter(Mandatory)][int]$Id)
    $null -ne (Get-Process -Id $Id -ErrorAction SilentlyContinue)
}

function Read-GnuTailAppended {
    <#
    .SYNOPSIS
    Reads the bytes of a followed file between its last position and its current end.
    .OUTPUTS
    The new text, or $null if nothing changed. Sets Truncated when the file got shorter.
    #>
    param([Parameter(Mandatory)][hashtable]$File)

    $stream = $File.Stream
    $ownStream = $false
    if ($null -eq $stream) {
        try { $stream = New-Object System.IO.FileStream -ArgumentList $File.Path, 'Open', 'Read', 'ReadWrite, Delete' }
        catch { return $null }
        $ownStream = $true
    }
    try {
        $length = $stream.Length
        if ($length -lt $File.Position) {
            $File.Truncated = $true
            $File.Position = 0
        }
        if ($length -eq $File.Position) { return $null }
        $stream.Position = $File.Position
        $buffer = New-Object byte[] ($length - $File.Position)
        $read = 0
        $count = 1
        while ($read -lt $buffer.Length -and $count -gt 0) {
            $count = $stream.Read($buffer, $read, $buffer.Length - $read)
            $read += $count
        }
        $File.Position += $read
        $script:GnuUtf8.GetString($buffer, 0, $read)
    }
    finally { if ($ownStream) { $stream.Dispose() } }
}

function Invoke-GnuTailFollow {
    <#
    .SYNOPSIS
    tail -f / -F: polls the files and prints what is appended, until --pid dies or the pipeline stops.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $how = [string](Get-GnuOptionValue -Context $Context -Key 'follow')
    if ([string]::IsNullOrEmpty($how)) { $how = 'descriptor' }
    if (@('name', 'descriptor') -notcontains $how) {
        Write-GnuUsageError -Context $Context -Message "invalid argument '$how' for '--follow'`nValid arguments are:`n  - 'name'`n  - 'descriptor'"
        return
    }
    $interval = 1.0
    if (Test-GnuOption -Context $Context -Key 'sleep-interval') {
        $text = [string](Get-GnuOptionValue -Context $Context -Key 'sleep-interval')
        if ($text -notmatch '^(\d+\.?\d*|\.\d+)$') { Write-GnuError -Context $Context -Message "invalid number of seconds: '$text'"; return }
        $interval = [double]::Parse($text, [System.Globalization.CultureInfo]::InvariantCulture)
    }
    $processId = $null
    if (Test-GnuOption -Context $Context -Key 'pid') {
        $text = [string](Get-GnuOptionValue -Context $Context -Key 'pid')
        $value = 0
        if (-not [int]::TryParse($text, [ref]$value)) { Write-GnuError -Context $Context -Message "invalid PID: '$text'"; return }
        $processId = $value
    }
    $retry = Test-GnuOption -Context $Context -Key 'retry'
    $operands = @($Context.Operands)
    if ($operands.Count -eq 0) { $operands = @('-') }
    $headerMode = [string](Get-GnuOptionValue -Context $Context -Key 'headers' -Default 'auto')
    $showHeaders = $headerMode -eq 'always' -or ($headerMode -eq 'auto' -and $operands.Count -gt 1)

    $files = New-Object 'System.Collections.Generic.List[hashtable]'
    foreach ($operand in $operands) {
        if ($operand -eq '-') {
            Write-GnuWarning -Context $Context -Message 'following standard input indefinitely is ineffective'
            continue
        }
        $path = Resolve-GnuPath -Path $operand
        $file = @{ Name = $operand; Path = $path; Position = [long]0; Stream = $null; Missing = $true; Truncated = $false; Partial = '' }
        if ([System.IO.File]::Exists($path)) {
            $file.Missing = $false
            $file.Position = (New-Object System.IO.FileInfo -ArgumentList $path).Length
            if ($how -eq 'descriptor') { $file.Stream = New-Object System.IO.FileStream -ArgumentList $path, 'Open', 'Read', 'ReadWrite, Delete' }
        }
        elseif (-not $retry) { continue }
        $files.Add($file)
    }
    if ($files.Count -eq 0) {
        if (@($operands | Where-Object { $_ -ne '-' }).Count -gt 0) { Write-GnuError -Context $Context -Message 'no files remaining' }
        return
    }

    $lastShown = $files[$files.Count - 1].Name
    try {
        $finalPass = $false
        while ($true) {
            Wait-GnuTailInterval -Seconds $interval
            if ($null -ne $processId -and -not (Test-GnuProcessAlive -Id $processId)) { $finalPass = $true }
            foreach ($file in $files) {
                if ($null -eq $file.Stream) {
                    if (-not [System.IO.File]::Exists($file.Path)) {
                        if (-not $file.Missing) { Write-GnuWarning -Context $Context -Message "'$($file.Name)' has become inaccessible: No such file or directory"; $file.Missing = $true }
                        continue
                    }
                    if ($file.Missing) {
                        Write-GnuWarning -Context $Context -Message "'$($file.Name)' has appeared;  following new file"
                        $file.Missing = $false
                        $file.Position = 0
                    }
                }
                $text = Read-GnuTailAppended -File $file
                if ($file.Truncated) { Write-GnuWarning -Context $Context -Message "$($file.Name): file truncated"; $file.Truncated = $false }
                if ($null -eq $text) {
                    # The file stopped growing: print an unfinished last line now.
                    if ($file.Partial.Length -gt 0) { $file.Partial; $file.Partial = '' }
                    continue
                }
                if ($showHeaders -and $lastShown -ne $file.Name) { ''; "==> $($file.Name) <=="; $lastShown = $file.Name }
                $text = $file.Partial + $text.Replace("`r`n", "`n")
                $cut = $text.LastIndexOf("`n")
                $file.Partial = $text.Substring($cut + 1)
                if ($cut -ge 0) { ConvertTo-GnuOutputLine -Text $text.Substring(0, $cut + 1) }
            }
            if ($finalPass) {
                foreach ($file in $files) { if ($file.Partial.Length -gt 0) { $file.Partial } }
                break
            }
        }
    }
    finally {
        foreach ($file in $files) { if ($null -ne $file.Stream) { $file.Stream.Dispose() } }
    }
}
