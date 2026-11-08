Register-GnuUtil @{
    Name         = 'false'
    Category     = 'Shell helpers'
    Synopsis     = 'Do nothing, unsuccessfully.'
    Usage        = @('false [ignored command line arguments]', 'false OPTION')
    Description  = @('Exit with a status code indicating failure.')
    RawArguments = $true
    Notes        = @('PowerShell note: functions cannot set $? to $false; check $LASTEXITCODE instead.')
}

function Invoke-GnuFalse {
    <#
    .SYNOPSIS
    GNU false: do nothing, unsuccessfully ($LASTEXITCODE = 1).

    .DESCRIPTION
    All arguments are ignored, except a single --help or --version. Like GNU false, the exit
    code is 1 even for --help and --version.
    Enable the GNU name with: Enable-GnuAlias false

    .EXAMPLE
    Invoke-GnuFalse; $LASTEXITCODE

    1
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'false' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        $ctx.ExitCode = 1
        Complete-GnuUtil -Context $ctx
    }
}
