Register-GnuUtil @{
    Name         = 'df'
    Category     = 'File info and disk usage'
    Synopsis     = 'Report file system disk space usage.'
    Usage        = @('df [OPTION]... [FILE]...')
    Description  = @(
        'Show information about the file system on which each FILE resides,',
        'or all file systems by default.'
    )
    FileOperands = $true
    Options      = @(
        @{ Short = 'a'; Long = 'all'; Help = 'include pseudo, duplicate, inaccessible file systems' }
        @{ Short = 'B'; Long = 'block-size'; Key = 'scale'; Arg = 'SIZE'; Help = 'scale sizes by SIZE before printing them; e.g., ''-BM'' prints sizes in units of 1,048,576 bytes; see SIZE format below' }
        @{ Short = 'h'; Long = 'human-readable'; Key = 'scale'; Value = 'human:1024'; Help = 'print sizes in powers of 1024 (e.g., 1023M)' }
        @{ Short = 'H'; Long = 'si'; Key = 'scale'; Value = 'human:1000'; Help = 'print sizes in powers of 1000 (e.g., 1.1G)' }
        @{ Short = 'i'; Long = 'inodes'; Help = 'list inode information instead of block usage' }
        @{ Short = 'k'; Key = 'scale'; Value = '1K'; Help = 'like --block-size=1K' }
        @{ Short = 'l'; Long = 'local'; Help = 'limit listing to local file systems' }
        @{ Short = 'm'; Key = 'scale'; Value = '1M'; Help = 'like --block-size=1M (undocumented in GNU, accepted for compatibility)' }
        @{ Long = 'no-sync'; Key = 'sync'; Value = 'no'; Help = 'do not invoke sync before getting usage info (default)' }
        @{ Long = 'output'; Arg = 'FIELD_LIST'; OptionalArg = $true; Help = 'use the output format defined by FIELD_LIST, or print all fields if FIELD_LIST is omitted.' }
        @{ Short = 'P'; Long = 'portability'; Help = 'use the POSIX output format' }
        @{ Long = 'sync'; Key = 'sync'; Value = 'yes'; Help = 'invoke sync before getting usage info' }
        @{ Long = 'total'; Help = 'elide all entries insignificant to available space, and produce a grand total' }
        @{ Short = 't'; Long = 'type'; Arg = 'TYPE'; Multi = $true; Help = 'limit listing to file systems of type TYPE' }
        @{ Short = 'T'; Long = 'print-type'; Help = 'print file system type' }
        @{ Short = 'x'; Long = 'exclude-type'; Arg = 'TYPE'; Multi = $true; Help = 'limit listing to file systems not of type TYPE' }
    )
    Notes        = @(
        'Display values are in units of the first available SIZE from --block-size,',
        'and the DF_BLOCK_SIZE, BLOCK_SIZE and BLOCKSIZE environment variables.',
        'Otherwise, units default to 1024 bytes (or 512 if POSIXLY_CORRECT is set).',
        '',
        'FIELD_LIST is a comma-separated list of columns to be included.  Valid',
        'field names are: ''source'', ''fstype'', ''itotal'', ''iused'', ''iavail'', ''ipcent'',',
        '''size'', ''used'', ''avail'', ''pcent'', ''file'' and ''target'' (see info page).',
        '',
        'PowerShell note: file systems come from .NET DriveInfo (Windows drive letters are the',
        'source and the mount point); inode counts are not available (-); the environment',
        'variables are ignored; --sync has no effect; SIZE does not take the '' grouping prefix.'
    )
}

# name = @(header, minimum width, right aligned)
$script:GnuDfFields = [ordered]@{
    source = @('Filesystem', 14, $false); fstype = @('Type', 4, $false); itotal = @('Inodes', 5, $true); iused = @('IUsed', 5, $true)
    iavail = @('IFree', 5, $true); ipcent = @('IUse%', 4, $true); size = @('Size', 5, $true); used = @('Used', 5, $true)
    avail = @('Avail', 5, $true); pcent = @('Use%', 4, $true); file = @('File', 0, $false); target = @('Mounted on', 0, $false)
}

function Invoke-GnuDf {
    <#
    .SYNOPSIS
    GNU df: report file system disk space usage.

    .DESCRIPTION
    Lists the size, used and available space of every file system (or the ones holding
    FILE), in 1K blocks, -B units, or human readable with -h / -H. -T adds the type, -i
    shows inodes, --output selects columns, --total adds a sum, -t / -x / -l filter.
    Enable the GNU name with: Enable-GnuAlias df

    .EXAMPLE
    Invoke-GnuDf -h
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'df' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) { Invoke-GnuDfReport -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function Get-GnuDfFileSystem {
    <#
    .SYNOPSIS
    The file systems: @{ Source; Type; Total; Free; Available; Target; Local } (bytes), mockable in tests.
    #>
    param([string]$MountsPath = '/proc/mounts')
    $sources = @{}
    if (-not (Test-GnuWindows) -and [System.IO.File]::Exists($MountsPath)) {
        foreach ($line in [System.IO.File]::ReadAllLines($MountsPath)) {
            $parts = $line.Split(' ')
            if ($parts.Count -ge 2 -and -not $sources.ContainsKey($parts[1])) { $sources[$parts[1]] = $parts[0] }
        }
    }
    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        $entry = @{ Source = $drive.Name.TrimEnd('\'); Type = '-'; Total = [double]0; Free = [double]0; Available = [double]0; Target = $drive.Name; Local = $drive.DriveType -ne [System.IO.DriveType]::Network; Ready = $drive.IsReady }
        if ($sources.ContainsKey($drive.Name)) { $entry.Source = $sources[$drive.Name] }
        if ($drive.IsReady) {
            $entry.Type = ([string]$drive.DriveFormat).ToLowerInvariant()
            $entry.Total = [double]$drive.TotalSize
            $entry.Free = [double]$drive.TotalFreeSpace
            $entry.Available = [double]$drive.AvailableFreeSpace
        }
        $entry
    }
}

function Invoke-GnuDfReport {
    <#
    .SYNOPSIS
    Implementation of df.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $scale = Get-GnuSizeScale -Context $Context
    if ($null -eq $scale) { return }
    $portable = Test-GnuOption -Context $Context -Key 'portability'
    $inodes = Test-GnuOption -Context $Context -Key 'inodes'

    $fields = @('source', 'size', 'used', 'avail', 'pcent', 'target')
    if ($inodes) { $fields = @('source', 'itotal', 'iused', 'iavail', 'ipcent', 'target') }
    if (Test-GnuOption -Context $Context -Key 'print-type') { $fields = @($fields[0], 'fstype') + $fields[1..($fields.Count - 1)] }
    $custom = Test-GnuOption -Context $Context -Key 'output'
    if ($custom) {
        foreach ($conflict in @(@('portability', '-P'), @('inodes', '-i'), @('print-type', '-T'))) {
            if (Test-GnuOption -Context $Context -Key $conflict[0]) { Write-GnuUsageError -Context $Context -Message "options $($conflict[1]) and --output are mutually exclusive"; return }
        }
        $list =[string](Get-GnuOptionValue -Context $Context -Key 'output')
        if ([string]::IsNullOrEmpty($list)) { $fields = @($script:GnuDfFields.Keys) }
        else {
            $fields = @($list.Split(','))
            foreach ($field in $fields) {
                if (-not $script:GnuDfFields.Contains($field)) { Write-GnuUsageError -Context $Context -Message "option --output: field '$field' unknown"; return }
            }
        }
    }

    $include = @(Get-GnuOptionValue -Context $Context -Key 'type' -Default @())
    $exclude = @(Get-GnuOptionValue -Context $Context -Key 'exclude-type' -Default @())
    $contradictions = @($include | Where-Object { $exclude -ccontains $_ })
    foreach ($type in $contradictions) { Write-GnuError -Context $Context -Message "file system type '$type' both selected and excluded" }
    if ($contradictions.Count -gt 0) { return }

    $all = @(Get-GnuDfFileSystem)
    $rows = New-Object 'System.Collections.Generic.List[hashtable]'
    $operands = @($Context.Operands)
    if ($operands.Count -gt 0) {
        foreach ($operand in $operands) {
            $path = Resolve-GnuPath -Path $operand
            if (-not (Test-Path -LiteralPath $path)) { Write-GnuError -Context $Context -Message "$($operand): No such file or directory"; continue }
            $full = [System.IO.Path]::GetFullPath($path)
            $best = $null
            foreach ($fs in $all) {
                if ($full.StartsWith($fs.Target, [System.StringComparison]::OrdinalIgnoreCase) -and ($null -eq $best -or $fs.Target.Length -gt $best.Target.Length)) { $best = $fs }
            }
            if ($null -ne $best) { $copy = $best.Clone(); $copy.File = $operand; $rows.Add($copy) }
        }
    }
    else {
        foreach ($fs in $all) {
            if (-not (Test-GnuOption -Context $Context -Key 'all') -and (-not $fs.Ready -or $fs.Total -eq 0)) { continue }
            $copy = $fs.Clone(); $copy.File = '-'; $rows.Add($copy)
        }
    }
    $local = Test-GnuOption -Context $Context -Key 'local'
    $selected = @($rows | Where-Object { ($include.Count -eq 0 -or $include -ccontains $_.Type) -and $exclude -cnotcontains $_.Type -and (-not $local -or $_.Local) })
    if ($selected.Count -eq 0) {
        if ($operands.Count -eq 0 -or $rows.Count -gt 0) { Write-GnuError -Context $Context -Message 'no file systems processed' }
        return
    }
    if (Test-GnuOption -Context $Context -Key 'total') {
        $sum = @{ Source = 'total'; Type = '-'; Target = '-'; File = '-'; Total = [double]0; Free = [double]0; Available = [double]0 }
        foreach ($row in $selected) { $sum.Total += $row.Total; $sum.Free += $row.Free; $sum.Available += $row.Available }
        $selected += $sum
    }

    # Header texts depend on the size mode, as in GNU.
    $headers = @{}
    foreach ($field in $fields) { $headers[$field] = $script:GnuDfFields[$field][0] }
    if ($scale.Human -eq 0) {
        $headers['size'] = "$($scale.Label)-blocks"
        if (-not $custom) { $headers['avail'] = 'Available' }
        if ($portable -and -not $custom) {
            $headers['size'] = "$($scale.Bytes.ToString('0', [System.Globalization.CultureInfo]::InvariantCulture))-blocks"
            $headers['pcent'] = 'Capacity'
        }
    }

    $table = New-Object 'System.Collections.Generic.List[string[]]'
    $table.Add([string[]]@(foreach ($field in $fields) { $headers[$field] }))
    foreach ($row in $selected) {
        $used = $row.Total - $row.Free
        $cells = foreach ($field in $fields) {
            switch ($field) {
                'source' { $row.Source }
                'fstype' { $row.Type }
                { $_ -eq 'size' -or $_ -eq 'used' -or $_ -eq 'avail' } {
                    $bytes = @{ size = $row.Total; used = $used; avail = $row.Available }[$field]
                    Format-GnuScaledSize -Bytes $bytes -Scale $scale
                }
                'pcent' {
                    if ($used + $row.Available -le 0) { '-' } else { [string][Math]::Ceiling($used * 100 / ($used + $row.Available)) + '%' }
                }
                'file' { $row.File }
                'target' { $row.Target }
                default { '-' }
            }
        }
        $table.Add([string[]]@($cells))
    }

    $widths = @(for ($c = 0; $c -lt $fields.Count; $c++) {
            $width = $script:GnuDfFields[$fields[$c]][1]
            foreach ($cells in $table) { $width = [Math]::Max($width, $cells[$c].Length) }
            $width
        })
    foreach ($cells in $table) {
        $parts = for ($c = 0; $c -lt $fields.Count; $c++) {
            $text = $cells[$c]
            if ($c -eq $fields.Count - 1 -and -not $script:GnuDfFields[$fields[$c]][2]) { $text }
            elseif ($script:GnuDfFields[$fields[$c]][2]) { $text.PadLeft($widths[$c]) }
            else { $text.PadRight($widths[$c]) }
        }
        ($parts -join ' ').TrimEnd()
    }
}
