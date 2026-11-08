Register-GnuUtil @{
    Name        = 'unlink'
    Category    = 'File and directory operations'
    Synopsis    = 'Call the unlink function to remove the specified file.'
    Usage       = @('unlink FILE', 'unlink OPTION')
    Description = @('Call the unlink function to remove the specified FILE.')
    Notes       = @('Directories are never removed; a symbolic link to a directory is removed as a link.')
}

function Invoke-GnuUnlink {
    <#
    .SYNOPSIS
    GNU unlink: remove exactly one file.

    .DESCRIPTION
    Removes a single file (or symbolic link). Takes no options, never recurses and refuses
    directories, which makes it a predictable minimal delete.
    Enable the GNU name with: Enable-GnuAlias unlink

    .EXAMPLE
    Invoke-GnuUnlink old.log
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'unlink' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            $operands = @($ctx.Operands)
            if ($operands.Count -eq 0) { Write-GnuUsageError -Context $ctx -Message 'missing operand' }
            elseif ($operands.Count -gt 1) { Write-GnuUsageError -Context $ctx -Message "extra operand '$($operands[1])'" }
            else {
                $name = $operands[0]
                $path = Resolve-GnuPath -Path $name
                $item = $null
                if (-not [string]::IsNullOrEmpty($path)) { $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
                $isLink = $null -ne $item -and ($item.LinkType -eq 'SymbolicLink' -or $item.LinkType -eq 'Junction')
                try {
                    if ($null -eq $item) {
                        Write-GnuError -Context $ctx -Message "cannot unlink '$name': No such file or directory"
                    }
                    elseif ($item -is [System.IO.DirectoryInfo] -and -not $isLink) {
                        Write-GnuError -Context $ctx -Message "cannot unlink '$name': Is a directory"
                    }
                    elseif ($item -is [System.IO.DirectoryInfo]) {
                        [System.IO.Directory]::Delete($path, $false)
                    }
                    else {
                        [System.IO.File]::Delete($path)
                    }
                }
                catch {
                    Write-GnuError -Context $ctx -Message "cannot unlink '$name': $(Get-GnuErrorReason -Exception $_.Exception)"
                }
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}
