Register-GnuUtil @{
    Name          = 'ls'
    Category      = 'File and directory operations'
    Synopsis      = 'List directory contents.'
    Usage         = @('ls [OPTION]... [FILE]...')
    Description   = @(
        'List information about the FILEs (the current directory by default).',
        'Sort entries alphabetically if none of -tSU is specified.'
    )
    FileOperands  = $true
    UsageExitCode = 2
    Options       = @(
        @{ Short = 'a'; Long = 'all'; Key = 'show'; Value = 'all'; Help = 'do not ignore entries starting with .' }
        @{ Short = 'A'; Long = 'almost-all'; Key = 'show'; Value = 'almost'; Help = 'do not list implied . and ..' }
        @{ Long = 'color'; Arg = 'WHEN'; OptionalArg = $true; Help = 'color the output WHEN; more info below' }
        @{ Short = 'C'; Key = 'format'; Value = 'columns'; Help = 'list entries by columns' }
        @{ Short = 'd'; Long = 'directory'; Help = 'list directories themselves, not their contents' }
        @{ Short = 'F'; Long = 'classify'; Key = 'indicator'; Value = 'classify'; Help = 'append indicator (one of */=>@|) to entries' }
        @{ Short = 'h'; Long = 'human-readable'; Help = 'with -l, print sizes like 1K 234M 2G etc.' }
        @{ Short = 'l'; Key = 'format'; Value = 'long'; Help = 'use a long listing format' }
        @{ Short = 'p'; Key = 'indicator'; Value = 'slash'; Help = 'append / indicator to directories' }
        @{ Short = 'r'; Long = 'reverse'; Help = 'reverse order while sorting' }
        @{ Short = 'R'; Long = 'recursive'; Help = 'list subdirectories recursively' }
        @{ Short = 'S'; Key = 'sort'; Value = 'size'; Help = 'sort by file size, largest first' }
        @{ Short = 't'; Key = 'sort'; Value = 'time'; Help = 'sort by time, newest first' }
        @{ Short = 'U'; Key = 'sort'; Value = 'none'; Help = 'do not sort; list entries in directory order' }
        @{ Short = '1'; Key = 'format'; Value = 'single'; Help = 'list one file per line' }
        @{ Long = 'width'; Short = 'w'; Arg = 'COLS'; Help = 'set output width to COLS.  0 means no limit' }
    )
    Notes         = @(
        'The WHEN argument defaults to ''always'' and can also be ''auto'' or ''never''.',
        'Using color to distinguish file types is disabled both by default and with',
        '--color=never.  With --color=auto, ls emits color codes only when standard',
        'output is connected to a terminal.  The LS_COLORS environment variable can',
        'change the settings (di, ln, ex, fi and *.ext entries are used).',
        '',
        'Exit status:',
        ' 0  if OK,',
        ' 1  if minor problems (e.g., cannot access subdirectory),',
        ' 2  if serious trouble (e.g., cannot access command-line argument).',
        '',
        'PowerShell notes: columns are used when ls is the last command of the pipeline and the output',
        'is not redirected; otherwise one name per line. Names are not quoted. Entries with the Windows',
        'Hidden attribute are hidden like dot files. Names sort case-insensitively, then ordinally.',
        'In -l output, link counts are 1, directory sizes 0, and "total" counts 1K blocks of the file sizes.'
    )
}

function Invoke-GnuLs {
    <#
    .SYNOPSIS
    GNU ls: list directory contents.

    .DESCRIPTION
    Lists FILEs and the contents of directories (the current directory by default): in columns
    when writing to the console, one per line in a pipeline (-1 / -C force either), or in the
    long format (-l, with -h for human sizes). -a / -A show hidden entries, -R recurses, -t / -S
    / -U / -r change the order, -F / -p append type indicators, --color colors names.
    Enable the GNU name with: Enable-GnuAlias ls (replaces the ls -> Get-ChildItem alias on Windows).

    .EXAMPLE
    Invoke-GnuLs -lah

    .EXAMPLE
    Invoke-GnuLs -1t | Invoke-GnuHead -3

    The three most recently modified entries.
    #>
    begin {
        $ctx = Initialize-GnuUtil -Name 'ls' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput
        $toConsole = Test-GnuConsoleOutput -Invocation $MyInvocation
    }
    end {
        if (-not $ctx.Done) { Invoke-GnuList -Context $ctx -ToConsole $toConsole }
        Complete-GnuUtil -Context $ctx
    }
}

function Get-GnuLsColorTable {
    <#
    .SYNOPSIS
    Color codes by type (di, ln, ex, fi) and by extension, from LS_COLORS on top of GNU's defaults.
    #>
    $table = @{ di = '01;34'; ln = '01;36'; ex = '01;32'; fi = '' }
    foreach ($entry in ([string]$env:LS_COLORS).Split(':')) {
        if ($entry -match '^(?<name>[^=]+)=(?<code>[0-9;]*)$') { $table[$Matches['name']] = $Matches['code'] }
    }
    $table
}

function Test-GnuLsExecutable {
    <#
    .SYNOPSIS
    $true for files ls marks as executable: Unix execute bits, or a PATHEXT extension on Windows.
    #>
    param([Parameter(Mandatory)][System.IO.FileSystemInfo]$Item)
    if ($Item -isnot [System.IO.FileInfo]) { return $false }
    if (Test-GnuWindows) {
        $extensions = ([string]$env:PATHEXT).Split(';')
        if ([string]::IsNullOrEmpty([string]$env:PATHEXT)) { $extensions = @('.COM', '.EXE', '.BAT', '.CMD') }
        return $extensions -contains $Item.Extension
    }
    $mode = Get-GnuUnixFileMode -Path $Item.FullName
    $null -ne $mode -and ($mode -band 73) -ne 0
}

function Format-GnuLsName {
    <#
    .SYNOPSIS
    The displayed name of an entry: colored and with type indicator as requested.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][System.IO.FileSystemInfo]$Item,
        [Parameter(Mandatory)][hashtable]$Settings
    )

    $isLink = $null -ne (Get-GnuLinkTarget -Path $Item.FullName)
    $isDirectory = $Item -is [System.IO.DirectoryInfo]
    $suffix = ''
    if ($Settings.Indicator -eq 'classify') {
        if ($isLink) { $suffix = '@' }
        elseif ($isDirectory) { $suffix = '/' }
        elseif (Test-GnuLsExecutable -Item $Item) { $suffix = '*' }
    }
    elseif ($Settings.Indicator -eq 'slash' -and $isDirectory -and -not $isLink) { $suffix = '/' }

    $text = $Name
    if ($Settings.Color) {
        $code = $Settings.Colors['fi']
        if ($isLink) { $code = $Settings.Colors['ln'] }
        elseif ($isDirectory) { $code = $Settings.Colors['di'] }
        elseif (Test-GnuLsExecutable -Item $Item) { $code = $Settings.Colors['ex'] }
        elseif ($Settings.Colors.ContainsKey('*' + $Item.Extension)) { $code = $Settings.Colors['*' + $Item.Extension] }
        if ($code) { $text = [char]27 + "[$($code)m" + $Name + [char]27 + '[0m' }
    }
    $text + $suffix
}

function Format-GnuLsSize {
    <#
    .SYNOPSIS
    A size for -l, in bytes or (with -h) like GNU: 1.5K, 10K, 3.2M (always rounded up).
    #>
    param([long]$Size, [bool]$Human)

    if (-not $Human -or $Size -lt 1024) { return [string]$Size }
    $units = 'KMGTPEZY'
    $value = [double]$Size
    $unit = -1
    while ($value -ge 1024 -and $unit -lt $units.Length - 1) {
        $value = $value / 1024
        $unit++
    }
    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    if ($value -lt 10) {
        $rounded = [Math]::Ceiling($value * 10) / 10
        if ($rounded -lt 10) { return $rounded.ToString('0.0', $invariant) + $units[$unit] }
        $value = $rounded
    }
    $rounded = [Math]::Ceiling($value)
    if ($rounded -ge 1024 -and $unit -lt $units.Length - 1) { return '1.0' + $units[$unit + 1] }
    $rounded.ToString('0', $invariant) + $units[$unit]
}

function Get-GnuLsMode {
    <#
    .SYNOPSIS
    The permission string of -l: Unix modes where available, otherwise derived from Windows attributes.
    #>
    param([Parameter(Mandatory)][System.IO.FileSystemInfo]$Item)

    $type = '-'
    if ($null -ne (Get-GnuLinkTarget -Path $Item.FullName)) { $type = 'l' }
    elseif ($Item -is [System.IO.DirectoryInfo]) { $type = 'd' }

    $mode = Get-GnuUnixFileMode -Path $Item.FullName
    if ($null -ne $mode) {
        $bits = ''
        foreach ($shift in @(6, 3, 0)) {
            $part = ($mode -shr $shift) -band 7
            $bits += $(if ($part -band 4) { 'r' } else { '-' }) + $(if ($part -band 2) { 'w' } else { '-' }) + $(if ($part -band 1) { 'x' } else { '-' })
        }
        return $type + $bits
    }
    $write = 'w'
    if ($Item.Attributes -band [System.IO.FileAttributes]::ReadOnly) { $write = '-' }
    $execute = '-'
    if ($type -ne '-' -or (Test-GnuLsExecutable -Item $Item)) { $execute = 'x' }
    $type + "r$write$execute" + "r-$execute" + "r-$execute"
}

function Get-GnuLsOwner {
    <#
    .SYNOPSIS
    Owner and group names for -l (Unix: from PowerShell's User/Group properties; Windows: from the ACL).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleCmdlets', '', Justification = 'Get-Acl is only called on Windows.')]
    param([Parameter(Mandatory)][System.IO.FileSystemInfo]$Item)

    $owner = $null
    $group = $null
    if ($Item.PSObject.Properties['User'] -and $Item.PSObject.Properties['Group']) {
        $owner = [string]$Item.User
        $group = [string]$Item.Group
    }
    elseif (Test-GnuWindows) {
        $acl = Get-Acl -LiteralPath $Item.FullName -ErrorAction SilentlyContinue
        if ($null -ne $acl) {
            $owner = [string]$acl.Owner
            $group = [string]$acl.Group
        }
    }
    if ([string]::IsNullOrEmpty($owner)) { $owner = '-' }
    if ([string]::IsNullOrEmpty($group)) { $group = '-' }
    @{ Owner = ($owner -replace '^.*\\', ''); Group = ($group -replace '^.*\\', '') }
}

function Format-GnuLsTime {
    <#
    .SYNOPSIS
    GNU's -l time: 'Nov  7 20:02' within six months, 'Nov  7  2025' otherwise.
    #>
    param([Parameter(Mandatory)][datetime]$Time, [Parameter(Mandatory)][datetime]$Now)

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $text = $Time.ToString('MMM', $invariant) + ' ' + ([string]$Time.Day).PadLeft(2) + ' '
    if ($Time -gt $Now.AddDays(-182) -and $Time -le $Now.AddMinutes(1)) { return $text + $Time.ToString('HH:mm', $invariant) }
    $text + ([string]$Time.Year).PadLeft(5)
}

function Get-GnuLsEntry {
    <#
    .SYNOPSIS
    The sorted, filtered entries of a directory as @{ Name; Item }.
    #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][hashtable]$Settings)

    $entries = New-Object 'System.Collections.Generic.List[object]'
    if ($Settings.Show -eq 'all') {
        $entries.Add(@{ Name = '.'; Item = (Get-Item -LiteralPath $Path -Force) })
        $parent = [System.IO.Directory]::GetParent($Path)
        $parentItem = Get-Item -LiteralPath $Path -Force
        if ($null -ne $parent) { $parentItem = Get-Item -LiteralPath $parent.FullName -Force }
        $entries.Add(@{ Name = '..'; Item = $parentItem })
    }
    foreach ($entry in [System.IO.Directory]::GetFileSystemEntries($Path)) {
        $item = Get-Item -LiteralPath $entry -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) { continue }
        $hidden = $item.Name.StartsWith('.', [System.StringComparison]::Ordinal) -or ($item.Attributes -band [System.IO.FileAttributes]::Hidden)
        if ($hidden -and $Settings.Show -eq 'visible') { continue }
        $entries.Add(@{ Name = $item.Name; Item = $item })
    }
    , (Get-GnuLsSortedEntry -Entries $entries.ToArray() -Settings $Settings)
}

function Get-GnuLsSortedEntry {
    <#
    .SYNOPSIS
    Orders entries by name (default), size (-S), time (-t) or not at all (-U); -r reverses.
    #>
    param([AllowEmptyCollection()][object[]]$Entries, [Parameter(Mandatory)][hashtable]$Settings)

    $list = New-Object 'System.Collections.Generic.List[object]'
    foreach ($entry in $Entries) { $list.Add($entry) }
    $byName = {
        param($a, $b)
        $c = [string]::Compare($a.Name, $b.Name, [System.StringComparison]::OrdinalIgnoreCase)
        if ($c -eq 0) { $c = [string]::CompareOrdinal($a.Name, $b.Name) }
        $c
    }
    switch ($Settings.Sort) {
        'none' { }
        'size' {
            $list.Sort([System.Comparison[object]] {
                    param($a, $b)
                    $sizeA = [long]0; $sizeB = [long]0   # Int32.CompareTo(Int64) throws
                    if ($a.Item -is [System.IO.FileInfo]) { $sizeA = $a.Item.Length }
                    if ($b.Item -is [System.IO.FileInfo]) { $sizeB = $b.Item.Length }
                    $c = $sizeB.CompareTo($sizeA)
                    if ($c -eq 0) { $c = & $byName $a $b }
                    $c
                })
        }
        'time' {
            $list.Sort([System.Comparison[object]] {
                    param($a, $b)
                    $c = $b.Item.LastWriteTime.CompareTo($a.Item.LastWriteTime)
                    if ($c -eq 0) { $c = & $byName $a $b }
                    $c
                })
        }
        default { $list.Sort([System.Comparison[object]]$byName) }
    }
    if ($Settings.Reverse -and $Settings.Sort -ne 'none') { $list.Reverse() }
    , $list.ToArray()
}

function Format-GnuLsColumns {
    <#
    .SYNOPSIS
    Lays out names in columns filled top to bottom (GNU -C) within Width characters.
    #>
    param([AllowEmptyCollection()][string[]]$Names, [AllowEmptyCollection()][int[]]$Lengths, [int]$Width)

    $count = $Names.Length
    if ($count -eq 0) { return }
    for ($columns = $count; $columns -ge 1; $columns--) {
        $rows = [int][Math]::Ceiling($count / $columns)
        $columns = [int][Math]::Ceiling($count / $rows)
        $widths = @(for ($c = 0; $c -lt $columns; $c++) {
                $max = 0
                for ($r = 0; $r -lt $rows; $r++) {
                    $index = $c * $rows + $r
                    if ($index -lt $count -and $Lengths[$index] -gt $max) { $max = $Lengths[$index] }
                }
                $max
            })
        $total = ($widths | Measure-Object -Sum).Sum + 2 * ($columns - 1)
        if ($total -le $Width -or $Width -le 0 -or $columns -eq 1) { break }
    }
    for ($r = 0; $r -lt $rows; $r++) {
        $line = New-Object System.Text.StringBuilder
        for ($c = 0; $c -lt $columns; $c++) {
            $index = $c * $rows + $r
            if ($index -ge $count) { continue }
            [void]$line.Append($Names[$index])
            if ($c -lt $columns - 1 -and ($c + 1) * $rows + $r -lt $count) { [void]$line.Append(' ' * ($widths[$c] - $Lengths[$index] + 2)) }
        }
        $line.ToString()
    }
}

function Format-GnuLsBlock {
    <#
    .SYNOPSIS
    Formats a group of entries (one directory listing, or the file operands) in the requested format.
    #>
    param([AllowEmptyCollection()][object[]]$Entries, [Parameter(Mandatory)][hashtable]$Settings, [switch]$Total)

    if ($Settings.Format -eq 'long') {
        $rows = @(foreach ($entry in $Entries) {
                $item = $entry.Item
                $size = 0
                if ($item -is [System.IO.FileInfo]) { $size = $item.Length }
                $owner = Get-GnuLsOwner -Item $item
                $name = Format-GnuLsName -Name $entry.Name -Item $item -Settings $Settings
                $link = Get-GnuLinkTarget -Path $item.FullName
                if ($null -ne $link) { $name += " -> $link" }
                @{ Mode = (Get-GnuLsMode -Item $item); Owner = $owner.Owner; Group = $owner.Group; Size = (Format-GnuLsSize -Size $size -Human $Settings.Human); Bytes = $size; Time = (Format-GnuLsTime -Time $item.LastWriteTime -Now $Settings.Now); Name = $name }
            })
        if ($Total) {
            $blocks = 0
            foreach ($row in $rows) { $blocks += [long][Math]::Ceiling($row.Bytes / 1024) }
            if ($Settings.Human) { "total $(Format-GnuLsSize -Size ($blocks * 1024) -Human $true)" } else { "total $blocks" }
        }
        $ownerWidth = ($rows | ForEach-Object { $_.Owner.Length } | Measure-Object -Maximum).Maximum
        $groupWidth = ($rows | ForEach-Object { $_.Group.Length } | Measure-Object -Maximum).Maximum
        $sizeWidth = ($rows | ForEach-Object { $_.Size.Length } | Measure-Object -Maximum).Maximum
        foreach ($row in $rows) {
            "$($row.Mode) 1 $($row.Owner.PadRight($ownerWidth)) $($row.Group.PadRight($groupWidth)) $($row.Size.PadLeft($sizeWidth)) $($row.Time) $($row.Name)"
        }
        return
    }

    $names = [string[]]@(foreach ($entry in $Entries) { Format-GnuLsName -Name $entry.Name -Item $entry.Item -Settings $Settings })
    if ($Settings.Format -eq 'columns') {
        # Color codes take no space on screen.
        $lengths = [int[]]@(foreach ($name in $names) { ($name -replace "$([char]27)\[[0-9;]*m", '').Length })
        Format-GnuLsColumns -Names $names -Lengths $lengths -Width $Settings.Width
        return
    }
    $names
}

function Invoke-GnuList {
    <#
    .SYNOPSIS
    Implementation of ls.
    #>
    param([Parameter(Mandatory)][hashtable]$Context, [bool]$ToConsole)

    $color = $false
    if (Test-GnuOption -Context $Context -Key 'color') {
        $when = [string](Get-GnuOptionValue -Context $Context -Key 'color')
        switch -Regex ($when) {
            '^$|^(always|yes|force)$' { $color = $true }
            '^(never|no|none)$' { $color = $false }
            '^(auto|tty|if-tty)$' { $color = $ToConsole }
            default {
                Write-GnuUsageError -Context $Context -Message "invalid argument '$when' for '--color'`nValid arguments are: 'always', 'yes', 'force', 'never', 'no', 'none', 'auto', 'tty', 'if-tty'"
                return
            }
        }
    }

    $width = 80
    if ($env:COLUMNS -match '^\d+$') { $width = [int]$env:COLUMNS }
    elseif ($ToConsole) { try { $width = [System.Console]::WindowWidth } catch { $width = 80 } }
    if (Test-GnuOption -Context $Context -Key 'width') {
        $text = [string](Get-GnuOptionValue -Context $Context -Key 'width')
        if ($text -notmatch '^\d+$') {
            Write-GnuError -Context $Context -Message "invalid line width: '$text'" -ExitCode 2
            return
        }
        $width = [int]$text
    }

    $format = 'single'
    if ($ToConsole) { $format = 'columns' }
    $settings = @{
        Format    = [string](Get-GnuOptionValue -Context $Context -Key 'format' -Default $format)
        Show      = [string](Get-GnuOptionValue -Context $Context -Key 'show' -Default 'visible')
        Sort      = [string](Get-GnuOptionValue -Context $Context -Key 'sort' -Default 'name')
        Reverse   = Test-GnuOption -Context $Context -Key 'reverse'
        Human     = Test-GnuOption -Context $Context -Key 'human-readable'
        Indicator = [string](Get-GnuOptionValue -Context $Context -Key 'indicator' -Default 'none')
        Color     = $color
        Colors    = Get-GnuLsColorTable
        Width     = $width
        Now       = [datetime]::Now
    }
    $recursive = Test-GnuOption -Context $Context -Key 'recursive'
    $directoryItself = Test-GnuOption -Context $Context -Key 'directory'

    $operands = @($Context.Operands)
    $implicit = $operands.Count -eq 0
    if ($implicit) { $operands = @('.') }

    $files = New-Object 'System.Collections.Generic.List[object]'
    $directories = New-Object 'System.Collections.Generic.List[object]'
    foreach ($operand in $operands) {
        $item = Get-Item -LiteralPath (Resolve-GnuPath -Path $operand) -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            Write-GnuError -Context $Context -Message "cannot access '$operand': No such file or directory" -ExitCode 2
            continue
        }
        $entry = @{ Name = $operand; Item = $item }
        if ($item -is [System.IO.DirectoryInfo] -and -not $directoryItself) { $directories.Add($entry) } else { $files.Add($entry) }
    }

    $printed = $false
    if ($files.Count -gt 0) {
        Format-GnuLsBlock -Entries (Get-GnuLsSortedEntry -Entries $files.ToArray() -Settings $settings) -Settings $settings
        $printed = $true
    }

    $showHeaders = $recursive -or ($operands.Count -gt 1)
    $queue = New-Object 'System.Collections.Generic.List[object]'
    foreach ($entry in (Get-GnuLsSortedEntry -Entries $directories.ToArray() -Settings $settings)) { $queue.Add($entry) }
    while ($queue.Count -gt 0) {
        $entry = $queue[0]
        $queue.RemoveAt(0)
        try { $children = Get-GnuLsEntry -Path $entry.Item.FullName -Settings $settings }
        catch {
            Write-GnuError -Context $Context -Message "cannot open directory '$($entry.Name)': $(Get-GnuErrorReason -Exception $_.Exception)"
            continue
        }
        if ($printed) { '' }
        if ($showHeaders) { "$($entry.Name):" }
        Format-GnuLsBlock -Entries $children -Settings $settings -Total
        $printed = $true

        if ($recursive) {
            # GNU lists subdirectories depth first, in display order, right after their parent.
            $subdirectories = @(foreach ($child in $children) {
                    if ($child.Name -eq '.' -or $child.Name -eq '..') { continue }
                    if ($child.Item -is [System.IO.DirectoryInfo] -and $null -eq (Get-GnuLinkTarget -Path $child.Item.FullName)) {
                        @{ Name = (Join-GnuDisplayPath -Directory $entry.Name -Leaf $child.Name); Item = $child.Item }
                    }
                })
            for ($i = $subdirectories.Count - 1; $i -ge 0; $i--) { $queue.Insert(0, $subdirectories[$i]) }
        }
    }
}
