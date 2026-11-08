Register-GnuUtil @{
    Name         = 'rmdir'
    Category     = 'File and directory operations'
    Synopsis     = 'Remove empty directories.'
    Usage        = @('rmdir [OPTION]... DIRECTORY...')
    Description  = @('Remove the DIRECTORY(ies), if they are empty.')
    FileOperands = $true
    Options      = @(
        @{ Long = 'ignore-fail-on-non-empty'; Help = 'ignore each failure to remove a non-empty directory' }
        @{ Short = 'p'; Long = 'parents'; Help = "remove DIRECTORY and its ancestors; e.g., 'rmdir -p a/b' is similar to 'rmdir a/b a'" }
        @{ Short = 'v'; Long = 'verbose'; Help = 'output a diagnostic for every directory processed' }
    )
}

function Invoke-GnuRmdir {
    <#
    .SYNOPSIS
    GNU rmdir: remove empty directories.

    .DESCRIPTION
    Removes each DIRECTORY if it is empty. With -p, the ancestors given in the path are
    removed as well. Never removes files or non-empty directories.
    Enable the GNU name with: Enable-GnuAlias rmdir (replaces the rmdir -> Remove-Item alias).

    .EXAMPLE
    Invoke-GnuRmdir -p a/b/c

    Removes a/b/c, then a/b, then a.
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'rmdir' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            $operands = @($ctx.Operands)
            if ($operands.Count -eq 0) {
                Write-GnuUsageError -Context $ctx -Message 'missing operand'
            }
            else {
                $parents = Test-GnuOption -Context $ctx -Key 'parents'
                $verbose = Test-GnuOption -Context $ctx -Key 'verbose'
                $ignoreNonEmpty = Test-GnuOption -Context $ctx -Key 'ignore-fail-on-non-empty'
                foreach ($directory in $operands) {
                    $targets = @($directory)
                    if ($parents) {
                        $targets = @(Get-GnuPathPrefix -Path $directory)
                        [System.Array]::Reverse($targets)
                    }
                    foreach ($target in $targets) {
                        $path = Resolve-GnuPath -Path $target
                        if ($verbose) { "rmdir: removing directory, '$target'" }
                        if (-not [System.IO.Directory]::Exists($path)) {
                            $reason = 'No such file or directory'
                            if ([System.IO.File]::Exists($path)) { $reason = 'Not a directory' }
                            Write-GnuError -Context $ctx -Message "failed to remove '$target': $reason"
                            break
                        }
                        if (@([System.IO.Directory]::GetFileSystemEntries($path)).Count -gt 0) {
                            if (-not $ignoreNonEmpty) { Write-GnuError -Context $ctx -Message "failed to remove '$target': Directory not empty" }
                            break
                        }
                        try {
                            [System.IO.Directory]::Delete($path, $false)
                        }
                        catch {
                            Write-GnuError -Context $ctx -Message "failed to remove '$target': $(Get-GnuErrorReason -Exception $_.Exception)"
                            break
                        }
                    }
                }
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}
