Register-GnuUtil @{
    Name        = 'arch'
    Category    = 'User and system info'
    Synopsis    = 'Print machine hardware name (same as uname -m).'
    Usage       = @('arch [OPTION]...')
    Description = @('Print machine architecture.')
}

function Invoke-GnuArch {
    <#
    .SYNOPSIS
    GNU arch: print the machine hardware name (same as uname -m).

    .DESCRIPTION
    Prints x86_64, aarch64 (arm64 on macOS), i686 or armv7l.
    Enable the GNU name with: Enable-GnuUtil arch

    .EXAMPLE
    Invoke-GnuArch

    x86_64
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'arch' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            $operands = @($ctx.Operands)
            if ($operands.Count -gt 0) { Write-GnuUsageError -Context $ctx -Message "extra operand '$($operands[0])'" }
            else { Get-GnuMachineName }
        }
        Complete-GnuUtil -Context $ctx
    }
}
