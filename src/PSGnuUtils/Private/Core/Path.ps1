# Path helpers.
#
# Utils must resolve relative paths against the PowerShell location ($PWD), not the process
# working directory ([Environment]::CurrentDirectory), which PowerShell does not keep in sync.

function Resolve-GnuPath {
    <#
    .SYNOPSIS
    Converts a (possibly relative, possibly non-existing) path to a full provider path.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Path)

    if ([string]::IsNullOrEmpty($Path)) { return '' }
    try {
        return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    }
    catch {
        # e.g. 'a:b' on Unix is parsed as a drive that does not exist.
        $base = $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.ProviderPath
        $combined = [System.IO.Path]::Combine($base, $Path)
        # .NET Framework's GetFullPath rejects ':' inside names; the unnormalized path is still usable.
        try { return [System.IO.Path]::GetFullPath($combined) } catch { return $combined }
    }
}

function Get-GnuCurrentDirectory {
    <#
    .SYNOPSIS
    The current file system location (logical, symlinks not resolved).
    #>
    $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.ProviderPath
}

function Resolve-GnuPhysicalPath {
    <#
    .SYNOPSIS
    Resolves every symbolic link and junction in an existing path (like 'pwd -P' / 'realpath').
    #>
    param([Parameter(Mandatory)][string]$Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($full)
    $parts = @($full.Substring($root.Length) -split '[\\/]' | Where-Object { -not [string]::IsNullOrEmpty($_) })
    $current = $root
    $hops = 0
    $index = 0

    while ($index -lt $parts.Count) {
        $candidate = [System.IO.Path]::Combine($current, $parts[$index])
        $item = Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
        $isLink = $null -ne $item -and ($item.LinkType -eq 'SymbolicLink' -or $item.LinkType -eq 'Junction')
        if ($isLink -and $hops -lt 40) {
            $hops++
            $target = [string](@($item.Target)[0])
            if (-not [System.IO.Path]::IsPathRooted($target)) { $target = [System.IO.Path]::Combine($current, $target) }
            $target = [System.IO.Path]::GetFullPath($target)

            $rest = @()
            if ($index + 1 -lt $parts.Count) { $rest = @($parts[($index + 1)..($parts.Count - 1)]) }
            $root = [System.IO.Path]::GetPathRoot($target)
            $parts = @(@($target.Substring($root.Length) -split '[\\/]' | Where-Object { -not [string]::IsNullOrEmpty($_) }) + $rest)
            $current = $root
            $index = 0
            continue
        }
        $current = $candidate
        $index++
    }
    $current
}

function Get-GnuBaseName {
    <#
    .SYNOPSIS
    GNU basename semantics: strip trailing separators, the directory part and an optional suffix.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [AllowNull()][AllowEmptyString()][string]$Suffix
    )

    if ([string]::IsNullOrEmpty($Path)) { return '' }
    $separators = Get-GnuPathSeparator
    $trimmed = $Path.TrimEnd($separators)
    if ([string]::IsNullOrEmpty($trimmed)) { return [string]$Path[0] }

    $base = $trimmed.Substring($trimmed.LastIndexOfAny($separators) + 1)
    if ($Suffix -and $base -ne $Suffix -and $base.EndsWith($Suffix, [System.StringComparison]::Ordinal)) {
        $base = $base.Substring(0, $base.Length - $Suffix.Length)
    }
    $base
}

function Get-GnuDirName {
    <#
    .SYNOPSIS
    GNU dirname semantics: the path without its last component ('.' if there is no directory part).
    On Windows a drive root keeps its separator (C:\foo -> C:\).
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Path)

    if ([string]::IsNullOrEmpty($Path)) { return '.' }
    $separators = Get-GnuPathSeparator
    $trimmed = $Path.TrimEnd($separators)
    if ([string]::IsNullOrEmpty($trimmed)) { return [string]$Path[0] }

    $index = $trimmed.LastIndexOfAny($separators)
    if ($index -lt 0) { return '.' }

    $directory = $trimmed.Substring(0, $index).TrimEnd($separators)
    if ([string]::IsNullOrEmpty($directory)) { return [string]$trimmed[0] }
    if ((Test-GnuWindows) -and $directory -match '^[A-Za-z]:$') { return $directory + $trimmed[$index] }
    $directory
}

function Get-GnuPathPrefix {
    <#
    .SYNOPSIS
    Returns every ancestor prefix of a path as typed, ending with the path itself ('a/b/c' -> 'a', 'a/b', 'a/b/c').
    #>
    param([Parameter(Mandatory)][string]$Path)

    $separators = Get-GnuPathSeparator
    $trimmed = $Path.TrimEnd($separators)
    if ([string]::IsNullOrEmpty($trimmed)) { return $Path }
    for ($i = 1; $i -lt $trimmed.Length; $i++) {
        if ($separators -contains $trimmed[$i] -and $separators -notcontains $trimmed[$i - 1]) {
            $prefix = $trimmed.Substring(0, $i)
            if ($prefix -notmatch '^[A-Za-z]:$') { $prefix }
        }
    }
    $trimmed
}
