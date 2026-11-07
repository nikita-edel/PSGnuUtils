Register-GnuUtil @{
    Name        = 'hostname'
    Category    = 'User and system info'
    Synopsis    = 'Print the system host name.'
    Usage       = @('hostname [NAME]', 'hostname OPTION')
    Description = @('Print the current host name.')
    Notes       = @('PowerShell note: setting the host name (hostname NAME) is not supported.')
}

function Invoke-GnuHostname {
    <#
    .SYNOPSIS
    GNU hostname: print the system host name.

    .DESCRIPTION
    Prints [System.Net.Dns]::GetHostName(). Setting the host name is not supported.
    Enable the GNU name with: Enable-GnuUtil hostname

    .EXAMPLE
    Invoke-GnuHostname

    my-laptop
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'hostname' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            $operands = @($ctx.Operands)
            if ($operands.Count -gt 1) { Write-GnuUsageError -Context $ctx -Message "extra operand '$($operands[1])'" }
            elseif ($operands.Count -eq 1) { Write-GnuError -Context $ctx -Message "cannot set name to '$($operands[0])': Operation not supported" }
            else { [System.Net.Dns]::GetHostName() }
        }
        Complete-GnuUtil -Context $ctx
    }
}
