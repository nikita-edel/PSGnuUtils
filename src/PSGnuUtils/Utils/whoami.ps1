Register-GnuUtil @{
    Name        = 'whoami'
    Category    = 'User and system info'
    Synopsis    = 'Print effective user name.'
    Usage       = @('whoami [OPTION]...')
    Description = @('Print the user name associated with the current effective user ID.')
    Notes       = @('PowerShell note: prints [Environment]::UserName (no DOMAIN\ prefix, unlike whoami.exe).')
}

function Invoke-GnuWhoami {
    <#
    .SYNOPSIS
    GNU whoami: print the effective user name.

    .DESCRIPTION
    Prints [Environment]::UserName. Unlike Windows whoami.exe there is no DOMAIN\ prefix.
    Enable the GNU name with: Enable-GnuUtil whoami

    .EXAMPLE
    Invoke-GnuWhoami

    alice
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'whoami' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            $operands = @($ctx.Operands)
            if ($operands.Count -gt 0) { Write-GnuUsageError -Context $ctx -Message "extra operand '$($operands[0])'" }
            else { [System.Environment]::UserName }
        }
        Complete-GnuUtil -Context $ctx
    }
}
