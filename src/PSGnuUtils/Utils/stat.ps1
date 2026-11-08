Register-GnuUtil @{
    Name         = 'stat'
    Category     = 'File info and disk usage'
    Synopsis     = 'Display file or file system status.'
    Usage        = @('stat [OPTION]... FILE...')
    Description  = @('Display file or file system status.')
    FileOperands = $true
    Options      = @(
        @{ Short = 'L'; Long = 'dereference'; Help = 'follow links' }
        @{ Short = 'f'; Long = 'file-system'; Help = 'display file system status instead of file status' }
        @{ Short = 'c'; Long = 'format'; Arg = 'FORMAT'; Help = 'use the specified FORMAT instead of the default; output a newline after each use of FORMAT' }
        @{ Long = 'printf'; Arg = 'FORMAT'; Help = 'like --format, but interpret backslash escapes, and do not output a mandatory trailing newline; if you want a newline, include \n in FORMAT' }
        @{ Short = 't'; Long = 'terse'; Help = 'print the information in terse form' }
    )
    Notes        = @(
        'The valid format sequences for files (without --file-system):',
        '',
        '  %a   access rights in octal',
        '  %A   access rights in human readable form',
        '  %b   number of blocks allocated (see %B)',
        '  %B   the size in bytes of each block reported by %b',
        '  %d   device number in decimal',
        '  %D   device number in hex',
        '  %f   raw mode in hex',
        '  %F   file type',
        '  %g   group ID of owner',
        '  %G   group name of owner',
        '  %h   number of hard links',
        '  %i   inode number',
        '  %n   file name',
        '  %N   quoted file name with dereference if symbolic link',
        '  %o   optimal I/O transfer size hint',
        '  %s   total size, in bytes',
        '  %t   major device type in hex, for character/block device special files',
        '  %T   minor device type in hex, for character/block device special files',
        '  %u   user ID of owner',
        '  %U   user name of owner',
        '  %w   time of file birth, human-readable; - if unknown',
        '  %W   time of file birth, seconds since Epoch; 0 if unknown',
        '  %x   time of last access, human-readable',
        '  %X   time of last access, seconds since Epoch',
        '  %y   time of last data modification, human-readable',
        '  %Y   time of last data modification, seconds since Epoch',
        '  %z   time of last status change, human-readable',
        '  %Z   time of last status change, seconds since Epoch',
        '',
        'Valid format sequences for file systems:',
        '',
        '  %a   free blocks available to non-superuser',
        '  %b   total data blocks in file system',
        '  %c   total file nodes in file system',
        '  %d   free file nodes in file system',
        '  %f   free blocks in file system',
        '  %i   file system ID in hex',
        '  %l   maximum length of filenames',
        '  %n   file name',
        '  %s   block size (for faster transfers)',
        '  %S   fundamental block size (for block counts)',
        '  %t   file system type in hex',
        '  %T   file system type in human readable form',
        '',
        'PowerShell note: .NET does not expose inode, device or link counts (shown as 0, 0',
        'and 1) nor the status change time (the modification time is used). Windows has no',
        'Unix modes: they are derived from the attributes, and the ids of owner and group',
        'follow Cygwin''s mapping (local accounts 0x30000 + RID). File systems: 4096-byte',
        'blocks, no inode counts.'
    )
}

$script:GnuStatFileSystems = @{
    ntfs = @(0x5346544e, 'ntfs'); fat32 = @(0x4d44, 'msdos'); fat = @(0x4d44, 'msdos'); exfat = @(0x2011bab0, 'exfat')
    ext2 = @(0xef53, 'ext2/ext3'); ext3 = @(0xef53, 'ext2/ext3'); ext4 = @(0xef53, 'ext2/ext3'); xfs = @(0x58465342, 'xfs')
    btrfs = @(0x9123683e, 'btrfs'); tmpfs = @(0x01021994, 'tmpfs'); apfs = @(0x1a, 'apfs'); refs = @(0x5265, 'refs')
}

function Invoke-GnuStat {
    <#
    .SYNOPSIS
    GNU stat: display file or file system status.

    .DESCRIPTION
    Prints the size, blocks, type, permissions, owner and times of each FILE, or the
    file system status with -f. -c / --printf print custom FORMATs (%n %s %y ...), -t the
    terse form, -L follows links.
    Enable the GNU name with: Enable-GnuUtil stat

    .EXAMPLE
    Invoke-GnuStat -c '%n %s %y' *.log
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'stat' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) { Invoke-GnuStatFile -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function Get-GnuStatId {
    <#
    .SYNOPSIS
    A numeric user/group id: Unix ids, or Cygwin's mapping of a Windows SID (local accounts 0x30000 + RID).
    #>
    param([AllowEmptyString()][string]$Name, [switch]$Group)

    if ([string]::IsNullOrEmpty($Name) -or $Name -eq '-') { return '0' }
    if (-not (Test-GnuWindows)) {
        $identity = Get-GnuIdentity -User $Name
        if ($null -eq $identity) { return '0' }
        if ($Group) { return [string]$identity.GroupId }
        return [string]$identity.UserId
    }
    try { $sid = (New-Object System.Security.Principal.NTAccount -ArgumentList $Name).Translate([System.Security.Principal.SecurityIdentifier]).Value }
    catch { return '0' }
    $parts = $sid.Split('-')
    $rid = [long]$parts[$parts.Length - 1]
    if ($sid.StartsWith('S-1-5-21-', [System.StringComparison]::Ordinal)) { return [string](0x30000 + $rid) }
    [string]$rid
}

function New-GnuStatTable {
    <#
    .SYNOPSIS
    A case-sensitive letter -> value table from alternating keys and values.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string[]]$Pairs)
    $table = New-Object 'System.Collections.Generic.Dictionary[string,string]' -ArgumentList ([System.StringComparer]::Ordinal)
    for ($i = 0; $i -lt $Pairs.Length; $i += 2) { $table[$Pairs[$i]] = $Pairs[$i + 1] }
    , $table
}

function Get-GnuStatInfo {
    <#
    .SYNOPSIS
    The status fields of one file as a hashtable of format letter -> value.
    #>
    param([Parameter(Mandatory)][System.IO.FileSystemInfo]$Item, [Parameter(Mandatory)][string]$Name)

    $isLink = $null -ne (Get-GnuLinkTarget -Path $Item.FullName)
    $isDirectory = $Item -is [System.IO.DirectoryInfo]
    $size = [long]0
    if (-not $isDirectory) { $size = [long]$Item.Length }
    $modeString = Get-GnuLsMode -Item $Item
    $bits = Get-GnuUnixFileMode -Path $Item.FullName
    if ($null -eq $bits) {
        $bits = 0
        $permissions = $modeString.Substring(1)
        for ($i = 0; $i -lt 9; $i++) { if ($permissions[$i] -ne '-') { $bits = $bits -bor (1 -shl (8 - $i)) } }
    }
    $typeBits = 0x8000
    $type = 'regular file'
    if ($size -eq 0) { $type = 'regular empty file' }
    $unixMode = Get-GnuUnixModeString -Path $Item.FullName
    if ($isLink) { $type = 'symbolic link'; $typeBits = 0xA000; $modeString = 'l' + $modeString.Substring(1) }
    elseif ($isDirectory) { $type = 'directory'; $typeBits = 0x4000 }
    elseif ($null -ne $unixMode -and $unixMode.Length -gt 0) {
        switch -CaseSensitive ([string]$unixMode[0]) {
            'c' { $type = 'character special file'; $typeBits = 0x2000 }
            'b' { $type = 'block special file'; $typeBits = 0x6000 }
            'p' { $type = 'fifo'; $typeBits = 0x1000 }
            's' { $type = 'socket'; $typeBits = 0xC000 }
        }
        $modeString = [string]$unixMode[0] + $modeString.Substring(1)
    }
    $owner = Get-GnuLsOwner -Item $Item
    $quoted = "'" + $Name.Replace("'", "'\''") + "'"
    if ($isLink) { $quoted += " -> '" + (Get-GnuLinkTarget -Path $Item.FullName).Replace("'", "'\''") + "'" }
    $times = New-Object 'System.Collections.Generic.Dictionary[string,string]' -ArgumentList ([System.StringComparer]::Ordinal)
    foreach ($entry in @(@('x', $Item.LastAccessTimeUtc), @('y', $Item.LastWriteTimeUtc), @('z', $Item.LastWriteTimeUtc), @('w', $Item.CreationTimeUtc))) {
        $time = [System.DateTimeOffset]::new([datetime]::SpecifyKind($entry[1], [System.DateTimeKind]::Utc)).ToLocalTime()
        $times[$entry[0]] = Format-GnuDate -Time $time -Format '%Y-%m-%d %H:%M:%S.%N %z'
        $times[$entry[0].ToUpperInvariant()] = [string]$time.ToUnixTimeSeconds()
    }
    $blocks = [long]0
    if ($size -gt 0) { $blocks = [long][Math]::Ceiling($size / 4096) * 8 }
    # Format letters are case-sensitive (%a / %A), so no hashtable literal.
    $values = New-GnuStatTable -Pairs @(
        'a', [System.Convert]::ToString($bits, 8), 'A', $modeString, 'b', [string]$blocks, 'B', '512', 'd', '0', 'D', '0',
        'f', [System.Convert]::ToString($typeBits -bor $bits, 16), 'F', $type, 'g', (Get-GnuStatId -Name $owner.Group -Group), 'G', $owner.Group,
        'h', '1', 'i', '0', 'n', $Name, 'N', $quoted, 'o', '4096', 's', [string]$size, 't', '0', 'T', '0',
        'u', (Get-GnuStatId -Name $owner.Owner), 'U', $owner.Owner)
    foreach ($key in @($times.Keys)) { $values[[string]$key] = $times[$key] }
    , $values
}

function Get-GnuStatDrive {
    <#
    .SYNOPSIS
    The mounted drives (mockable in tests).
    #>
    [System.IO.DriveInfo]::GetDrives()
}

function Get-GnuStatFileSystemInfo {
    <#
    .SYNOPSIS
    The file system fields (--file-system) of the drive that holds a path.
    #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)

    $root = [System.IO.Path]::GetPathRoot($Path)
    $best = $null
    foreach ($drive in @(Get-GnuStatDrive)) {
        if (-not $drive.IsReady) { continue }
        $mount = $drive.RootDirectory.FullName
        if ($Path.StartsWith($mount, [System.StringComparison]::OrdinalIgnoreCase) -and ($null -eq $best -or $mount.Length -gt $best.RootDirectory.FullName.Length)) { $best = $drive }
    }
    if ($null -eq $best) { $best = New-Object System.IO.DriveInfo -ArgumentList $root }
    $format = [string]$best.DriveFormat
    $known = $script:GnuStatFileSystems[$format.ToLowerInvariant()]
    $hex = '0'
    $typeName = $format.ToLowerInvariant()
    if ($null -ne $known) { $hex = [System.Convert]::ToString([long]$known[0], 16); $typeName = $known[1] }
    $id = [System.Convert]::ToString([long]($best.RootDirectory.FullName.GetHashCode() -band 0x7fffffff), 16)
    , (New-GnuStatTable -Pairs @(
            'n', $Name, 't', $hex, 'T', $typeName, 's', '4096', 'S', '4096', 'b', [string][long][Math]::Floor($best.TotalSize / 4096),
            'f', [string][long][Math]::Floor($best.TotalFreeSpace / 4096), 'a', [string][long][Math]::Floor($best.AvailableFreeSpace / 4096),
            'c', '?', 'd', '?', 'i', $id, 'l', '255'))
}

function Format-GnuStatText {
    <#
    .SYNOPSIS
    Expands %-sequences (with printf flags, width and precision) from a value table; unknown ones print '?'.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Format, [Parameter(Mandatory)][System.Collections.Generic.Dictionary[string, string]]$Values)

    $numeric = 'abBdDfghioOstTuXYZW'
    [regex]::Replace($Format, "%([-+ #0']*)(\d*)(?:\.(\d*))?(.?)", [System.Text.RegularExpressions.MatchEvaluator] {
            param($m)
            $letter = $m.Groups[4].Value
            if ($letter -eq '%') { return '%' }
            if ($letter.Length -eq 0) { return '%' }
            $value = '?'
            if ($Values.ContainsKey($letter)) { $value = $Values[$letter] }
            $flags = $m.Groups[1].Value
            $width = 0
            if ($m.Groups[2].Value.Length -gt 0) { $width = [int]$m.Groups[2].Value }
            if ($m.Groups[3].Success -and $numeric.IndexOf($letter, [System.StringComparison]::Ordinal) -lt 0) {
                $precision = 0
                if ($m.Groups[3].Value.Length -gt 0) { $precision = [int]$m.Groups[3].Value }
                if ($value.Length -gt $precision) { $value = $value.Substring(0, $precision) }
            }
            if ($value.Length -ge $width) { return $value }
            if ($flags.Contains('-')) { return $value.PadRight($width) }
            if ($flags.Contains('0') -and $value -match '^-?\d+$') { return $value.PadLeft($width, '0') }
            $value.PadLeft($width)
        })
}

function Invoke-GnuStatFile {
    <#
    .SYNOPSIS
    Implementation of stat.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $operands = @($Context.Operands)
    if ($operands.Count -eq 0) { Write-GnuUsageError -Context $Context -Message 'missing operand'; return }
    $fileSystem = Test-GnuOption -Context $Context -Key 'file-system'
    $terse = Test-GnuOption -Context $Context -Key 'terse'
    $format = $null
    $newline = $true
    if (Test-GnuOption -Context $Context -Key 'format') { $format = [string](Get-GnuOptionValue -Context $Context -Key 'format') }
    if (Test-GnuOption -Context $Context -Key 'printf') {
        $escaped = ConvertFrom-GnuPrintfEscape -Context $Context -Text ([string](Get-GnuOptionValue -Context $Context -Key 'printf')) -Start 0 -All
        $format = $escaped.Text
        $newline = $false
    }
    $builder = New-Object System.Text.StringBuilder
    foreach ($name in $operands) {
        $path = Resolve-GnuPath -Path $name
        if ($fileSystem) {
            if (-not (Test-Path -LiteralPath $path)) { Write-GnuError -Context $Context -Message "cannot read file system information for '$name': No such file or directory"; continue }
            $values = Get-GnuStatFileSystemInfo -Path ([System.IO.Path]::GetFullPath($path)) -Name $name
            $current = $format
            if ($null -eq $current) {
                if ($terse) { $current = '%n %i %l %t %s %S %b %f %a %c %d' }
                else { $current = "  File: `"%n`"`n    ID: %-8i Namelen: %-7l Type: %T`nBlock size: %-10s Fundamental block size: %S`nBlocks: Total: %-10b Free: %-10f Available: %a`nInodes: Total: %-10c Free: %d" }
            }
        }
        else {
            $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            if ($null -eq $item) { Write-GnuError -Context $Context -Message "cannot stat '$name': No such file or directory"; continue }
            if ((Test-GnuOption -Context $Context -Key 'dereference') -and $null -ne (Get-GnuLinkTarget -Path $item.FullName)) {
                $target = Resolve-GnuPhysicalPath -Path $item.FullName
                $item = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
                if ($null -eq $item) { Write-GnuError -Context $Context -Message "cannot stat '$name': No such file or directory"; continue }
            }
            $values = Get-GnuStatInfo -Item $item -Name $name
            $current = $format
            if ($null -eq $current) {
                if ($terse) { $current = '%n %s %b %f %u %g %D %i %h %t %T %X %Y %Z %W %o' }
                else {
                    $file = $name
                    if ($name -match "[\s'`"\\$]") { $file = "'" + $name.Replace("'", "'\''") + "'" }
                    if ($values['F'] -eq 'symbolic link') { $file = $values['N'] }
                    $current = "  File: $($file.Replace('%', '%%'))`n  Size: %-10s`tBlocks: %-10b IO Block: %-6o %F`nDevice: %Dh/%dd`tInode: %-10i  Links: %h`nAccess: (%04a/%10.10A)  Uid: (%5u/%8U)   Gid: (%5g/%8G)`nAccess: %x`nModify: %y`nChange: %z`n Birth: %w"
                }
            }
        }
        [void]$builder.Append((Format-GnuStatText -Format $current -Values $values))
        if ($newline) { [void]$builder.Append("`n") }
    }
    if ($builder.Length -gt 0) { ConvertTo-GnuOutputLine -Text $builder.ToString() }
}
