# Shared by cp, mv and ln: turning SOURCE... DEST / -t DIRECTORY / -T operands into (source, target) pairs,
# plus small file system helpers.

function Join-GnuDisplayPath {
    <#
    .SYNOPSIS
    DIRECTORY/LEAF as GNU prints it ('dir/' + 'a' -> 'dir/a').
    #>
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][string]$Leaf)
    $Directory.TrimEnd((Get-GnuPathSeparator)) + '/' + $Leaf
}

function Get-GnuTransferPlan {
    <#
    .SYNOPSIS
    Pairs every source with its target. Returns @(@{ Source; Target }) or nothing after reporting an error.
    .PARAMETER AllowSingleOperand
    ln: a single operand creates the link in the current directory.
    .PARAMETER NoDereferenceTarget
    ln -n: a DEST that is a link to a directory is treated as a file, not as a directory.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [switch]$AllowSingleOperand,
        [switch]$NoDereferenceTarget
    )

    $operands = @($Context.Operands)
    $noTargetDirectory = Test-GnuOption -Context $Context -Key 'no-target-directory'
    if (Test-GnuOption -Context $Context -Key 'target-directory') {
        $directory = [string](Get-GnuOptionValue -Context $Context -Key 'target-directory')
        if ($noTargetDirectory) {
            Write-GnuUsageError -Context $Context -Message 'cannot combine --target-directory (-t) and --no-target-directory (-T)'
            return
        }
        $path = Resolve-GnuPath -Path $directory
        if (-not [System.IO.Directory]::Exists($path)) {
            $reason = 'No such file or directory'
            if ([System.IO.File]::Exists($path)) { $reason = 'Not a directory' }
            Write-GnuError -Context $Context -Message "target directory '$directory': $reason"
            return
        }
        if ($operands.Count -eq 0) {
            Write-GnuUsageError -Context $Context -Message 'missing file operand'
            return
        }
        foreach ($source in $operands) { @{ Source = $source; Target = (Join-GnuDisplayPath -Directory $directory -Leaf (Get-GnuBaseName -Path $source)) } }
        return
    }

    if ($operands.Count -eq 0) {
        Write-GnuUsageError -Context $Context -Message 'missing file operand'
        return
    }
    if ($operands.Count -eq 1) {
        if ($AllowSingleOperand) {
            @{ Source = $operands[0]; Target = (Get-GnuBaseName -Path $operands[0]) }
            return
        }
        Write-GnuUsageError -Context $Context -Message "missing destination file operand after '$($operands[0])'"
        return
    }
    if ($noTargetDirectory) {
        if ($operands.Count -gt 2) {
            Write-GnuUsageError -Context $Context -Message "extra operand '$($operands[2])'"
            return
        }
        @{ Source = $operands[0]; Target = $operands[1] }
        return
    }

    $destination = $operands[$operands.Count - 1]
    $destinationPath = Resolve-GnuPath -Path $destination
    $isDirectory = [System.IO.Directory]::Exists($destinationPath)
    if ($isDirectory -and $NoDereferenceTarget -and $null -ne (Get-GnuLinkTarget -Path $destinationPath)) { $isDirectory = $false }

    if ($isDirectory) {
        for ($i = 0; $i -lt $operands.Count - 1; $i++) {
            @{ Source = $operands[$i]; Target = (Join-GnuDisplayPath -Directory $destination -Leaf (Get-GnuBaseName -Path $operands[$i])) }
        }
        return
    }
    if ($operands.Count -gt 2) {
        Write-GnuError -Context $Context -Message "target '$destination' is not a directory"
        return
    }
    @{ Source = $operands[0]; Target = $destination }
}

function Test-GnuSamePath {
    <#
    .SYNOPSIS
    $true if two full paths name the same file (case-insensitive on Windows and macOS).
    #>
    param([Parameter(Mandatory)][string]$Left, [Parameter(Mandatory)][string]$Right)
    $comparison = [System.StringComparison]::Ordinal
    if ((Get-GnuPlatform) -ne 'Linux' -and (Get-GnuPlatform) -ne 'Unix') { $comparison = [System.StringComparison]::OrdinalIgnoreCase }
    $separators = Get-GnuPathSeparator
    [string]::Equals([System.IO.Path]::GetFullPath($Left).TrimEnd($separators), [System.IO.Path]::GetFullPath($Right).TrimEnd($separators), $comparison)
}

function Test-GnuInsidePath {
    <#
    .SYNOPSIS
    $true if Path is Ancestor itself or lies below it (copying or moving a directory into itself).
    #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Ancestor)
    if (Test-GnuSamePath -Left $Path -Right $Ancestor) { return $true }
    $prefix = [System.IO.Path]::GetFullPath($Ancestor).TrimEnd((Get-GnuPathSeparator)) + [System.IO.Path]::DirectorySeparatorChar
    $full = [System.IO.Path]::GetFullPath($Path)
    $comparison = [System.StringComparison]::Ordinal
    if ((Get-GnuPlatform) -ne 'Linux' -and (Get-GnuPlatform) -ne 'Unix') { $comparison = [System.StringComparison]::OrdinalIgnoreCase }
    $full.StartsWith($prefix, $comparison)
}

function New-GnuSymbolicLink {
    <#
    .SYNOPSIS
    Creates a symbolic link Path -> Target, storing Target exactly as given (it may be relative to the link).
    .NOTES
    Uses File/Directory.CreateSymbolicLink (.NET 6+); Windows PowerShell 5.1 falls back to New-Item.
    Windows needs admin rights or developer mode for symbolic links.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Target,
        [switch]$Directory
    )

    if ($null -ne [System.IO.File].GetMethod('CreateSymbolicLink')) {
        if ($Directory) { $null = [System.IO.Directory]::CreateSymbolicLink($Path, $Target) }
        else { $null = [System.IO.File]::CreateSymbolicLink($Path, $Target) }
        return
    }
    $null = New-Item -ItemType SymbolicLink -Path ([System.Management.Automation.WildcardPattern]::Escape($Path)) -Value $Target -ErrorAction Stop
}

function Get-GnuRelativePath {
    <#
    .SYNOPSIS
    The path of To relative to the directory From (ln -r). Different roots give the full path of To.
    #>
    param([Parameter(Mandatory)][string]$From, [Parameter(Mandatory)][string]$To)

    $fromFull = [System.IO.Path]::GetFullPath($From).TrimEnd((Get-GnuPathSeparator))
    $toFull = [System.IO.Path]::GetFullPath($To)
    if (-not [string]::Equals([System.IO.Path]::GetPathRoot($fromFull), [System.IO.Path]::GetPathRoot($toFull), [System.StringComparison]::OrdinalIgnoreCase)) { return $toFull }

    $fromParts = @($fromFull -split '[\\/]' | Where-Object { -not [string]::IsNullOrEmpty($_) })
    $toParts = @($toFull -split '[\\/]' | Where-Object { -not [string]::IsNullOrEmpty($_) })
    $comparison = [System.StringComparison]::Ordinal
    if ((Get-GnuPlatform) -ne 'Linux' -and (Get-GnuPlatform) -ne 'Unix') { $comparison = [System.StringComparison]::OrdinalIgnoreCase }
    $common = 0
    while ($common -lt $fromParts.Count -and $common -lt $toParts.Count -and [string]::Equals($fromParts[$common], $toParts[$common], $comparison)) { $common++ }

    $parts = @()
    for ($i = $common; $i -lt $fromParts.Count; $i++) { $parts += '..' }
    for ($i = $common; $i -lt $toParts.Count; $i++) { $parts += $toParts[$i] }
    if ($parts.Count -eq 0) { return '.' }
    $parts -join '/'
}

function Copy-GnuDirectoryTree {
    <#
    .SYNOPSIS
    Copies a directory tree with timestamps (mv across drives). Links are recreated, never followed.
    #>
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination)

    $null = [System.IO.Directory]::CreateDirectory($Destination)
    foreach ($entry in [System.IO.Directory]::GetFileSystemEntries($Source)) {
        $target = [System.IO.Path]::Combine($Destination, [System.IO.Path]::GetFileName($entry))
        $link = Get-GnuLinkTarget -Path $entry
        if ($null -ne $link -and (Get-Item -LiteralPath $entry -Force).LinkType -eq 'Junction') {
            $null = New-Item -ItemType Junction -Path ([System.Management.Automation.WildcardPattern]::Escape($target)) -Value $link -ErrorAction Stop
        }
        elseif ($null -ne $link) { New-GnuSymbolicLink -Path $target -Target $link -Directory:([System.IO.Directory]::Exists($entry)) }
        elseif ([System.IO.Directory]::Exists($entry)) { Copy-GnuDirectoryTree -Source $entry -Destination $target }
        else { [System.IO.File]::Copy($entry, $target, $true) }
    }
    [System.IO.Directory]::SetLastWriteTime($Destination, [System.IO.Directory]::GetLastWriteTime($Source))
}

function Test-GnuSameVolume {
    <#
    .SYNOPSIS
    $true if both paths are on the same drive / root (Directory.Move only works within one).
    #>
    param([Parameter(Mandatory)][string]$Left, [Parameter(Mandatory)][string]$Right)
    [string]::Equals([System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($Left)), [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($Right)), [System.StringComparison]::OrdinalIgnoreCase)
}

function Remove-GnuTree {
    <#
    .SYNOPSIS
    Deletes a directory tree. Links and junctions inside are removed themselves, never followed
    (Directory.Delete(path, $true) fails with 'access denied' on junctions).
    #>
    param([Parameter(Mandatory)][string]$Path)

    foreach ($entry in [System.IO.Directory]::GetFileSystemEntries($Path)) {
        $isDirectory = [System.IO.Directory]::Exists($entry)
        if ($null -ne (Get-GnuLinkTarget -Path $entry)) {
            if ($isDirectory) { [System.IO.Directory]::Delete($entry, $false) } else { [System.IO.File]::Delete($entry) }
        }
        elseif ($isDirectory) { Remove-GnuTree -Path $entry }
        else {
            [System.IO.File]::SetAttributes($entry, [System.IO.FileAttributes]::Normal)
            [System.IO.File]::Delete($entry)
        }
    }
    [System.IO.File]::SetAttributes($Path, [System.IO.FileAttributes]::Directory)
    [System.IO.Directory]::Delete($Path, $false)
}
