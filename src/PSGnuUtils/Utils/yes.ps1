Register-GnuUtil @{
    Name               = 'yes'
    Category           = 'Shell helpers'
    Synopsis           = 'Output a string repeatedly until killed.'
    Usage              = @('yes [STRING]...', 'yes OPTION')
    Description        = @("Repeatedly output a line with all specified STRING(s), or 'y'.")
    StopAtFirstOperand = $true
    Notes              = @(
        'PowerShell note: a PowerShell function cannot stop the command that feeds it, so',
        '"yes | head" never finishes. Use "yes | Select-Object -First N" instead.'
    )
}

function Invoke-GnuYes {
    <#
    .SYNOPSIS
    GNU yes: output a string repeatedly until stopped.

    .DESCRIPTION
    Outputs 'y', or all operands joined with spaces, forever. Stop it with Ctrl+C or with a
    cmdlet that stops its input, such as Select-Object -First.
    Enable the GNU name with: Enable-GnuAlias yes

    .EXAMPLE
    Invoke-GnuYes | Select-Object -First 2

    y
    y

    .EXAMPLE
    Invoke-GnuYes hello world | Select-Object -First 1

    hello world
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'yes' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            $line = 'y'
            if (@($ctx.Operands).Count -gt 0) { $line = $ctx.Operands -join ' ' }
            while ($true) { $line }
        }
        Complete-GnuUtil -Context $ctx
    }
}
