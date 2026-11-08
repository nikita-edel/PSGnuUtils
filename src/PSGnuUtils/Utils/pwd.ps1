Register-GnuUtil @{
    Name        = 'pwd'
    Category    = 'Paths and names'
    Synopsis    = 'Print name of current/working directory.'
    Usage       = @('pwd [OPTION]...')
    Description = @('Print the full filename of the current working directory.')
    Options     = @(
        @{ Short = 'L'; Long = 'logical'; Key = 'mode'; Value = 'logical'; Help = 'use PWD from environment, even if it contains symlinks' }
        @{ Short = 'P'; Long = 'physical'; Key = 'mode'; Value = 'physical'; Help = 'avoid all symlinks' }
    )
    Notes       = @(
        'If no option is specified, -P is assumed (like GNU coreutils pwd).',
        'PowerShell note: the working directory is the current PowerShell file system location.'
    )
}

function Invoke-GnuPwd {
    <#
    .SYNOPSIS
    GNU pwd: print the current working directory.

    .DESCRIPTION
    Prints the current PowerShell file system location. -L prints it as is, -P (the GNU
    coreutils default) resolves symbolic links and junctions.
    Enable the GNU name with: Enable-GnuAlias pwd (replaces the pwd -> Get-Location alias).

    .EXAMPLE
    Invoke-GnuPwd -L

    C:\Users\me
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'pwd' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            if (@($ctx.Operands).Count -gt 0) {
                Write-GnuWarning -Context $ctx -Message 'ignoring non-option arguments'
            }
            $location = Get-GnuCurrentDirectory
            if ((Get-GnuOptionValue -Context $ctx -Key 'mode' -Default 'physical') -eq 'physical') {
                $location = Resolve-GnuPhysicalPath -Path $location
            }
            $location
        }
        Complete-GnuUtil -Context $ctx
    }
}
