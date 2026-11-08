Register-GnuUtil @{
    Name         = 'true'
    Category     = 'Shell helpers'
    Synopsis     = 'Do nothing, successfully.'
    Usage        = @('true [ignored command line arguments]', 'true OPTION')
    Description  = @('Exit with a status code indicating success.')
    RawArguments = $true
    Notes        = @('PowerShell note: functions cannot set $? to $false; check $LASTEXITCODE instead.')
}

function Invoke-GnuTrue {
    <#
    .SYNOPSIS
    GNU true: do nothing, successfully ($LASTEXITCODE = 0).

    .DESCRIPTION
    All arguments are ignored, except a single --help or --version.
    Enable the GNU name with: Enable-GnuAlias true

    .EXAMPLE
    Invoke-GnuTrue; $LASTEXITCODE

    0
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'true' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end { Complete-GnuUtil -Context $ctx }
}
