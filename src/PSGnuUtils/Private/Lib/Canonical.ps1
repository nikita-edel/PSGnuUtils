# Canonical paths for readlink -f/-e/-m and realpath.

function Get-GnuCanonicalPath {
    <#
    .SYNOPSIS
    Resolves a path to an absolute path without '.', '..' or (unless -NoSymlinks) symbolic links.
    .PARAMETER Require
    'all' every component must exist (-e), 'parent' all but the last (-f, realpath default), 'none' (-m).
    .OUTPUTS
    @{ Path } or @{ Error } with a GNU reason such as 'No such file or directory'.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [ValidateSet('all', 'parent', 'none')][string]$Require = 'parent',
        [switch]$NoSymlinks
    )

    if ([string]::IsNullOrEmpty($Path)) { return @{ Error = 'No such file or directory' } }
    $full = [System.IO.Path]::GetFullPath((Resolve-GnuPath -Path $Path))
    $root = [System.IO.Path]::GetPathRoot($full)
    $parts = @($full.Substring($root.Length) -split '[\\/]' | Where-Object { -not [string]::IsNullOrEmpty($_) })

    # The longest existing prefix is resolved physically; the rest is appended as text.
    $existing = $root
    $index = 0
    while ($index -lt $parts.Count) {
        $candidate = [System.IO.Path]::Combine($existing, $parts[$index])
        if (-not ([System.IO.File]::Exists($candidate) -or [System.IO.Directory]::Exists($candidate))) { break }
        $existing = $candidate
        $index++
    }
    $missing = $parts.Count - $index
    if ($Require -eq 'all' -and $missing -gt 0) { return @{ Error = 'No such file or directory' } }
    if ($Require -eq 'parent' -and $missing -gt 1) { return @{ Error = 'No such file or directory' } }
    if ($Require -ne 'none' -and $missing -gt 0 -and [System.IO.File]::Exists($existing)) { return @{ Error = 'Not a directory' } }

    $resolved = $existing
    if (-not $NoSymlinks) { $resolved = Resolve-GnuPhysicalPath -Path $existing }
    for ($i = $index; $i -lt $parts.Count; $i++) { $resolved = [System.IO.Path]::Combine($resolved, $parts[$i]) }
    @{ Path = $resolved }
}
