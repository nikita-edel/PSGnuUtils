Register-GnuUtil @{
    Name         = 'realpath'
    Category     = 'File info and disk usage'
    Synopsis     = 'Print the resolved path.'
    Usage        = @('realpath [OPTION]... FILE...')
    Description  = @('Print the resolved absolute file name;', 'all but the last component must exist')
    FileOperands = $true
    Options      = @(
        @{ Short = 'e'; Long = 'canonicalize-existing'; Key = 'require'; Value = 'all'; Help = 'all components of the path must exist' }
        @{ Short = 'm'; Long = 'canonicalize-missing'; Key = 'require'; Value = 'none'; Help = 'no path components need exist or be a directory' }
        @{ Short = 'L'; Long = 'logical'; Key = 'resolve'; Value = 'logical'; Help = 'resolve ''..'' components before symlinks' }
        @{ Short = 'P'; Long = 'physical'; Key = 'resolve'; Value = 'physical'; Help = 'resolve symlinks as encountered (default)' }
        @{ Short = 'q'; Long = 'quiet'; Help = 'suppress most error messages' }
        @{ Long = 'relative-to'; Arg = 'DIR'; Help = 'print the resolved path relative to DIR' }
        @{ Long = 'relative-base'; Arg = 'DIR'; Help = 'print absolute paths unless paths below DIR' }
        @{ Short = 's'; Long = 'strip'; Key = 'no-symlinks'; Help = 'don''t expand symlinks' }
        @{ Long = 'no-symlinks'; Help = 'don''t expand symlinks' }
        @{ Short = 'z'; Long = 'zero'; Help = 'end each output line with NUL, not newline' }
    )
    Notes        = @('PowerShell note: ''..'' is always resolved textually before links, so -L and -P give the same result.')
}

function Invoke-GnuRealpath {
    <#
    .SYNOPSIS
    GNU realpath: print the resolved absolute path.

    .DESCRIPTION
    Prints each FILE as an absolute path without '.', '..' and links (unless -s). By default all
    but the last component must exist; -e requires all, -m none. --relative-to prints the path
    relative to a directory; --relative-base does so only for paths below that directory.
    Enable the GNU name with: Enable-GnuAlias realpath

    .EXAMPLE
    Invoke-GnuRealpath --relative-to=. ./src/../build
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'realpath' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) { Invoke-GnuRealpathResolve -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function Invoke-GnuRealpathResolve {
    <#
    .SYNOPSIS
    Implementation of realpath.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $operands = @($Context.Operands)
    if ($operands.Count -eq 0) {
        Write-GnuUsageError -Context $Context -Message 'missing operand'
        return
    }
    $require = [string](Get-GnuOptionValue -Context $Context -Key 'require' -Default 'parent')
    $noSymlinks = Test-GnuOption -Context $Context -Key 'no-symlinks'
    $quiet = Test-GnuOption -Context $Context -Key 'quiet'

    $bases = @{}
    foreach ($key in @('relative-to', 'relative-base')) {
        if (-not (Test-GnuOption -Context $Context -Key $key)) { continue }
        $directory = [string](Get-GnuOptionValue -Context $Context -Key $key)
        $resolved = Get-GnuCanonicalPath -Path $directory -Require $require -NoSymlinks:$noSymlinks
        if (-not $resolved.ContainsKey('Path')) {
            Write-GnuError -Context $Context -Message "$($directory): $($resolved.Error)"
            return
        }
        $bases[$key] = $resolved.Path
    }
    if ($bases.ContainsKey('relative-base') -and -not $bases.ContainsKey('relative-to')) { $bases['relative-to'] = $bases['relative-base'] }

    $results = foreach ($name in $operands) {
        $resolved = Get-GnuCanonicalPath -Path $name -Require $require -NoSymlinks:$noSymlinks
        if (-not $resolved.ContainsKey('Path')) {
            if ($quiet) { $Context.ExitCode = 1 } else { Write-GnuError -Context $Context -Message "$($name): $($resolved.Error)" }
            continue
        }
        $path = $resolved.Path
        if ($bases.ContainsKey('relative-to')) {
            $useRelative = $true
            if ($bases.ContainsKey('relative-base')) {
                $useRelative = Test-GnuInsidePath -Path $path -Ancestor $bases['relative-base']
                if ($useRelative) { $useRelative = Test-GnuInsidePath -Path $bases['relative-to'] -Ancestor $bases['relative-base'] }
            }
            if ($useRelative) { $path = (Get-GnuRelativePath -From $bases['relative-to'] -To $path).Replace('/', [string][System.IO.Path]::DirectorySeparatorChar) }
        }
        $path
    }
    ConvertTo-GnuRecordOutput -Record @($results) -Zero:(Test-GnuOption -Context $Context -Key 'zero')
}
