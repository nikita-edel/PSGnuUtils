Register-GnuUtil @{
    Name         = 'dd'
    Category     = 'File and directory operations'
    Synopsis     = 'Convert and copy a file.'
    Usage        = @('dd [OPERAND]...', 'dd OPTION')
    Description  = @(
        'Copy a file, converting and formatting according to the operands.',
        '',
        '  bs=BYTES        read and write up to BYTES bytes at a time (default: 512); overrides ibs and obs',
        '  conv=CONVS      convert the file as per the comma separated symbol list',
        '  count=N         copy only N input blocks',
        '  ibs=BYTES       read up to BYTES bytes at a time (default: 512)',
        '  if=FILE         read from FILE instead of stdin',
        '  iflag=FLAGS     read as per the comma separated symbol list',
        '  obs=BYTES       write BYTES bytes at a time (default: 512)',
        '  of=FILE         write to FILE instead of stdout',
        '  oflag=FLAGS     write as per the comma separated symbol list',
        '  seek=N          skip N obs-sized blocks at start of output',
        '  skip=N          skip N ibs-sized blocks at start of input',
        '  status=LEVEL    The LEVEL of information to print to stderr; ''none'' suppresses everything but error messages, ''noxfer'' suppresses the final transfer statistics, ''progress'' shows periodic transfer statistics'
    )
    RawArguments = $true
    OpenErrorFormat = "failed to open '{0}': {1}"
    Notes        = @(
        'N and BYTES may be followed by the following multiplicative suffixes:',
        'c =1, w =2, b =512, kB =1000, K =1024, MB =1000*1000, M =1024*1024, xM =M,',
        'GB =1000*1000*1000, G =1024*1024*1024, and so on for T, P, E, Z, Y.',
        'Binary prefixes can be used, too: KiB=K, MiB=M, and so on.',
        '',
        'Each CONV symbol may be:',
        '  lcase     change upper case to lower case',
        '  ucase     change lower case to upper case',
        '  swab      swap every pair of input bytes',
        '  sync      pad every input block with NULs to ibs-size',
        '  excl      fail if the output file already exists',
        '  nocreat   do not create the output file',
        '  notrunc   do not truncate the output file',
        '  noerror   continue after read errors',
        '  fdatasync  physically write output file data before finishing',
        '  fsync     likewise, but also write metadata',
        '',
        'Each FLAG symbol may be:',
        '  append     append mode (makes sense only for output; conv=notrunc suggested)',
        '  count_bytes  treat ''count=N'' as a byte count (iflag only)',
        '  skip_bytes  treat ''skip=N'' as a byte count (iflag only)',
        '  seek_bytes  treat ''seek=N'' as a byte count (oflag only)',
        '  fullblock  accumulate full blocks of input (iflag only)',
        '',
        'PowerShell note: only regular files, the pipeline and the console (no devices such as',
        '\\.\PhysicalDrive0: one mistake there destroys a disk). The statistics go to the',
        'information stream (6). Output to the pipeline is decoded as UTF-8 text lines; use',
        'of=FILE for binary data. ascii, ebcdic, block, unblock, sparse and direct I/O flags are',
        'not supported. oflag=seek_bytes keeps the first SEEK bytes (GNU 8.32 truncates them).',
        'The whole input is held in memory, so files of 2 GB or more cannot be read.'
    )
}

function Invoke-GnuDd {
    <#
    .SYNOPSIS
    GNU dd: copy a file block by block, with conversions.

    .DESCRIPTION
    Copies if=FILE (or the pipeline) to of=FILE (or the pipeline) in blocks of bs / ibs /
    obs bytes, skipping skip= input blocks and seek= output blocks, copying count= blocks,
    and applying conv= conversions (ucase, lcase, swab, sync, notrunc, ...). The statistics
    ("N+M records in") are written to the information stream.
    Enable the GNU name with: Enable-GnuUtil dd

    .EXAMPLE
    Invoke-GnuDd if=image.iso of=part.bin bs=1M skip=10 count=5
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'dd' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuDdCopy -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function ConvertFrom-GnuDdNumber {
    <#
    .SYNOPSIS
    A dd number: digits with suffixes c w b kB K MB M ... and products (2x512), $null if invalid, -1 if too large.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $product = [decimal]1
    try {
        foreach ($part in $Text.Split('x')) {
            # GNU reads a suffix without digits as one of that unit (bs=M).
            $spec = $part
            if ($part -match '^[A-Za-z]') { $spec = '1' + $part }
            if ($spec -cmatch '^(\d+)([cw])$') { $value = [decimal]$Matches[1] * @{ c = 1; w = 2 }[$Matches[2]] }
            else { $value = ConvertFrom-GnuSize -Text $spec }
            if ($null -eq $value) { return $null }
            $product *= $value
        }
    }
    catch { return [long]-1 }
    if ($product -gt [long]::MaxValue) { return [long]-1 }
    [long]$product
}

function Write-GnuDdStatus {
    <#
    .SYNOPSIS
    The transfer statistics, to the information stream.
    #>
    param([Parameter(Mandatory)][hashtable]$Stats, [Parameter(Mandatory)][string]$Level, [Parameter(Mandatory)][double]$Seconds)
    if ($Level -eq 'none') { return }
    Write-Information -MessageData "$($Stats.FullIn)+$($Stats.PartialIn) records in" -InformationAction Continue
    Write-Information -MessageData "$($Stats.FullOut)+$($Stats.PartialOut) records out" -InformationAction Continue
    if ($Level -eq 'noxfer') { return }
    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $bytes = $Stats.Bytes
    $text = "$bytes bytes"
    if ($bytes -eq 1) { $text = '1 byte' }
    if ($bytes -ge 1000) {
        $si = (Format-GnuHumanSize -Bytes $bytes -Base 1000) -replace '([kMGTPEZY])$', ' $1B'
        $iec = (Format-GnuHumanSize -Bytes $bytes -Base 1024) -replace '([KMGTPEZY])$', ' $1iB'
        $text += " ($si, $iec)"
    }
    # GNU prints the rate with three significant digits: 125 kB/s, 27.0 MB/s, 3.89 GB/s.
    $rate = 'Infinity B'
    if ($Seconds -gt 0) {
        $value = $bytes / $Seconds
        $unit = 0
        while ($value -ge 1000 -and $unit -lt 8) { $value /= 1000; $unit++ }
        $digits = '0.00'
        if ($value -ge 100) { $digits = '0' } elseif ($value -ge 10) { $digits = '0.0' }
        $rate = $value.ToString($digits, $invariant) + ' ' + ('', 'k', 'M', 'G', 'T', 'P', 'E', 'Z', 'Y')[$unit] + 'B'
    }
    Write-Information -MessageData "$text copied, $($Seconds.ToString('0.######', $invariant)) s, $rate/s" -InformationAction Continue
}

function Invoke-GnuDdCopy {
    <#
    .SYNOPSIS
    Implementation of dd.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $settings = @{ if = $null; of = $null; ibs = [long]512; obs = [long]512; count = [long]-1; skip = [long]0; seek = [long]0; conv = @(); iflag = @(); oflag = @(); status = 'default' }
    $bsGiven = $false
    foreach ($operand in @($Context.Operands)) {
        $at = $operand.IndexOf('=')
        if ($at -le 0) { Write-GnuUsageError -Context $Context -Message "unrecognized operand '$operand'"; return }
        $key = $operand.Substring(0, $at)
        $value = $operand.Substring($at + 1)
        switch -CaseSensitive ($key) {
            { $_ -eq 'if' -or $_ -eq 'of' } { $settings[$key] = $value }
            { 'bs', 'ibs', 'obs', 'count', 'skip', 'seek', 'iseek', 'oseek' -ccontains $_ } {
                $number = ConvertFrom-GnuDdNumber -Text $value
                if ($null -eq $number -or ($number -eq 0 -and 'bs', 'ibs', 'obs' -ccontains $key)) { Write-GnuError -Context $Context -Message "invalid number: '$value'"; return }
                if ($number -eq -1) { Write-GnuError -Context $Context -Message "invalid number: '$value': Value too large for defined data type"; return }
                switch ($key) {
                    'bs' { $settings.ibs = $number; $settings.obs = $number; $bsGiven = $true }
                    'iseek' { $settings.skip = $number }
                    'oseek' { $settings.seek = $number }
                    default { $settings[$key] = $number }
                }
            }
            { 'conv', 'iflag', 'oflag' -ccontains $_ } {
                $valid = @{ conv = @('lcase', 'ucase', 'swab', 'sync', 'excl', 'nocreat', 'notrunc', 'noerror', 'fdatasync', 'fsync'); iflag = @('count_bytes', 'skip_bytes', 'fullblock'); oflag = @('append', 'seek_bytes') }[$key]
                foreach ($symbol in $value.Split(',')) {
                    $what = @{ conv = 'conversion'; iflag = 'input flag'; oflag = 'output flag' }[$key]
                    if ($valid -cnotcontains $symbol) { Write-GnuUsageError -Context $Context -Message "invalid $($what): '$symbol'"; return }
                }
                $settings[$key] = $value.Split(',')
            }
            'status' {
                if (@('none', 'noxfer', 'progress') -cnotcontains $value) { Write-GnuUsageError -Context $Context -Message "invalid status level: '$value'"; return }
                $settings.status = $value
            }
            default { Write-GnuUsageError -Context $Context -Message "unrecognized operand '$operand'"; return }
        }
    }
    if ($settings.conv -contains 'lcase' -and $settings.conv -contains 'ucase') { Write-GnuError -Context $Context -Message 'cannot combine lcase and ucase'; return }
    if ($settings.conv -contains 'excl' -and $settings.conv -contains 'nocreat') { Write-GnuError -Context $Context -Message 'cannot combine excl and nocreat'; return }

    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $inputName = '-'
    if ($null -ne $settings.if) { $inputName = $settings.if }
    if (-not [string]::IsNullOrEmpty($settings.if) -and [System.IO.Directory]::Exists((Resolve-GnuPath -Path $settings.if))) {
        # GNU opens a directory, fails on the first read, and still creates the output and reports 0+0 records.
        Write-GnuError -Context $Context -Message "error reading '$($settings.if)': Is a directory"
        $data = New-Object byte[] 0
    }
    else {
        $data = Get-GnuInputBytes -Context $Context -Operand $inputName
        if ($null -eq $data) { return }
    }
    [byte[]]$data = $data

    $offset = $settings.skip * $settings.ibs
    if ($settings.iflag -contains 'skip_bytes') { $offset = $settings.skip }
    if ($offset -gt $data.Length) {
        Write-GnuWarning -Context $Context -Message "$($inputName): cannot skip to specified offset"
        $offset = $data.Length
    }
    $limit = [long]::MaxValue
    if ($settings.count -ge 0) {
        if ($settings.iflag -contains 'count_bytes') { $limit = $settings.count } else { $limit = $settings.count * $settings.ibs }
    }
    $stats = @{ FullIn = 0; PartialIn = 0; FullOut = 0; PartialOut = 0; Bytes = [long]0 }
    $copied = New-Object 'System.Collections.Generic.List[byte]'
    $position = $offset
    $consumed = [long]0
    while ($position -lt $data.Length -and $consumed -lt $limit -and ($settings.count -lt 0 -or ($settings.iflag -contains 'count_bytes') -or $stats.FullIn + $stats.PartialIn -lt $settings.count)) {
        $take = [Math]::Min([long]$settings.ibs, [long]($data.Length - $position))
        if ($settings.iflag -contains 'count_bytes') { $take = [Math]::Min($take, $limit - $consumed) }
        $block = New-Object byte[] $take
        [array]::Copy($data, $position, $block, 0, $take)
        $position += $take
        $consumed += $take
        if ($take -eq $settings.ibs) { $stats.FullIn++ } else { $stats.PartialIn++ }
        if ($settings.conv -contains 'sync' -and $take -lt $settings.ibs) {
            $padded = New-Object byte[] $settings.ibs
            [array]::Copy($block, $padded, $take)
            $block = $padded
        }
        if ($settings.conv -contains 'ucase' -or $settings.conv -contains 'lcase') {
            for ($k = 0; $k -lt $block.Length; $k++) {
                $b = $block[$k]
                if ($settings.conv -contains 'ucase' -and $b -ge 97 -and $b -le 122) { $block[$k] = $b - 32 }
                if ($settings.conv -contains 'lcase' -and $b -ge 65 -and $b -le 90) { $block[$k] = $b + 32 }
            }
        }
        if ($bsGiven) {
            if ($block.Length -eq $settings.obs) { $stats.FullOut++ } else { $stats.PartialOut++ }
        }
        $copied.AddRange($block)
    }
    $bytes = $copied.ToArray()
    # Pairs span block boundaries: GNU holds the last byte of an odd block for the next one.
    if ($settings.conv -contains 'swab') {
        for ($k = 0; $k + 1 -lt $bytes.Length; $k += 2) { $swap = $bytes[$k]; $bytes[$k] = $bytes[$k + 1]; $bytes[$k + 1] = $swap }
    }
    $stats.Bytes = $bytes.Length
    if (-not $bsGiven) {
        $stats.FullOut = [long][Math]::Floor($bytes.Length / $settings.obs)
        if ($bytes.Length % $settings.obs -ne 0) { $stats.PartialOut = 1 }
    }

    if ($null -eq $settings.of) {
        if ($bytes.Length -gt 0) { ConvertTo-GnuOutputLine -Text $script:GnuUtf8.GetString($bytes) }
    }
    else {
        if ([string]::IsNullOrEmpty($settings.of)) { Write-GnuError -Context $Context -Message "failed to open '': No such file or directory"; return }
        $path = Resolve-GnuPath -Path $settings.of
        if ([System.IO.Directory]::Exists($path)) { Write-GnuError -Context $Context -Message "failed to open '$($settings.of)': Is a directory"; return }
        $exists = [System.IO.File]::Exists($path)
        if ($settings.conv -contains 'excl' -and $exists) { Write-GnuError -Context $Context -Message "failed to open '$($settings.of)': File exists"; return }
        if ($settings.conv -contains 'nocreat' -and -not $exists) { Write-GnuError -Context $Context -Message "failed to open '$($settings.of)': No such file or directory"; return }
        $seek = $settings.seek * $settings.obs
        if ($settings.oflag -contains 'seek_bytes') { $seek = $settings.seek }
        try {
            $stream = New-Object System.IO.FileStream -ArgumentList $path, 'OpenOrCreate', 'Write', 'Read'
            try {
                if ($settings.oflag -contains 'append') { $seek = $stream.Length }
                elseif ($settings.conv -notcontains 'notrunc') { $stream.SetLength([Math]::Min($stream.Length, $seek)) }
                $stream.Position = $seek
                $stream.Write($bytes, 0, $bytes.Length)
                if ($settings.conv -contains 'fsync' -or $settings.conv -contains 'fdatasync') { $stream.Flush($true) }
            }
            finally { $stream.Dispose() }
        }
        catch {
            Write-GnuError -Context $Context -Message "failed to open '$($settings.of)': $(Get-GnuErrorReason -Exception $_.Exception)"
            return
        }
    }
    Write-GnuDdStatus -Stats $stats -Level $settings.status -Seconds $clock.Elapsed.TotalSeconds
}
