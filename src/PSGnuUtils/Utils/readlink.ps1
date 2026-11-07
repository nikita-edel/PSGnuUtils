Register-GnuUtil @{
    Name         = 'readlink'
    Category     = 'File info and disk usage'
    Synopsis     = 'Print resolved symbolic links or canonical file names.'
    Usage        = @('readlink [OPTION]... FILE...')
    Description  = @(
        'Print value of a symbolic link or canonical file name',
        ''
    )
    FileOperands = $true
    Options      = @(
        @{ Short = 'f'; Long = 'canonicalize'; Key = 'mode'; Value = 'parent'; Help = 'canonicalize by following every symlink in every component of the given name recursively; all but the last component must exist' }
        @{ Short = 'e'; Long = 'canonicalize-existing'; Key = 'mode'; Value = 'all'; Help = 'canonicalize by following every symlink in every component of the given name recursively, all components must exist' }
        @{ Short = 'm'; Long = 'canonicalize-missing'; Key = 'mode'; Value = 'none'; Help = 'canonicalize by following every symlink in every component of the given name recursively, without requirements on components existence' }
        @{ Short = 'n'; Long = 'no-newline'; Help = 'do not output the trailing delimiter' }
        @{ Short = 'q'; Long = 'quiet'; Key = 'verbosity'; Value = 'quiet'; Help = 'suppress most error messages (on by default)' }
        @{ Short = 's'; Long = 'silent'; Key = 'verbosity'; Value = 'quiet'; Help = 'suppress most error messages (on by default)' }
        @{ Short = 'v'; Long = 'verbose'; Key = 'verbosity'; Value = 'verbose'; Help = 'report error messages' }
        @{ Short = 'z'; Long = 'zero'; Help = 'end each output line with NUL, not newline' }
    )
    Notes        = @('PowerShell note: junctions count as symbolic links; -n has no visible effect on pipeline output.')
}

function Invoke-GnuReadlink {
    <#
    .SYNOPSIS
    GNU readlink: print the target of a symbolic link, or a canonical path with -f / -e / -m.

    .DESCRIPTION
    Without options prints the stored target of each symbolic link or junction (exit code 1 for
    anything that is not a link). -f, -e and -m print the absolute path with every link resolved.
    Enable the GNU name with: Enable-GnuUtil readlink

    .EXAMPLE
    Invoke-GnuReadlink -f ./build/../out
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'readlink' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            $operands = @($ctx.Operands)
            if ($operands.Count -eq 0) { Write-GnuUsageError -Context $ctx -Message 'missing operand' }
            else {
                $mode = [string](Get-GnuOptionValue -Context $ctx -Key 'mode' -Default '')
                $verbose = (Get-GnuOptionValue -Context $ctx -Key 'verbosity' -Default 'quiet') -eq 'verbose'
                $results = foreach ($name in $operands) {
                    if ($mode) {
                        $canonical = Get-GnuCanonicalPath -Path $name -Require $mode
                        if ($canonical.ContainsKey('Path')) { $canonical.Path; continue }
                        if ($verbose) { Write-GnuError -Context $ctx -Message "$($name): $($canonical.Error)" } else { $ctx.ExitCode = 1 }
                        continue
                    }
                    $target = $null
                    if (-not [string]::IsNullOrEmpty($name)) { $target = Get-GnuLinkTarget -Path (Resolve-GnuPath -Path $name) }
                    if ($null -ne $target) { $target; continue }
                    $reason = 'Invalid argument'
                    if ([string]::IsNullOrEmpty($name) -or -not (Test-Path -LiteralPath (Resolve-GnuPath -Path $name))) { $reason = 'No such file or directory' }
                    if ($verbose) { Write-GnuError -Context $ctx -Message "$($name): $reason" } else { $ctx.ExitCode = 1 }
                }
                ConvertTo-GnuRecordOutput -Record @($results) -Zero:(Test-GnuOption -Context $ctx -Key 'zero')
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}
