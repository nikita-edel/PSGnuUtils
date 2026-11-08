Register-GnuUtil @{
    Name        = 'uname'
    Category    = 'User and system info'
    Synopsis    = 'Print system information.'
    Usage       = @('uname [OPTION]...')
    Description = @('Print certain system information.  With no OPTION, same as -s.')
    Options     = @(
        @{ Short = 'a'; Long = 'all'; Help = 'print all information, in the following order, except omit -p and -i if unknown:' }
        @{ Short = 's'; Long = 'kernel-name'; Help = 'print the kernel name' }
        @{ Short = 'n'; Long = 'nodename'; Help = 'print the network node hostname' }
        @{ Short = 'r'; Long = 'kernel-release'; Help = 'print the kernel release' }
        @{ Short = 'v'; Long = 'kernel-version'; Help = 'print the kernel version' }
        @{ Short = 'm'; Long = 'machine'; Help = 'print the machine hardware name' }
        @{ Short = 'p'; Long = 'processor'; Help = 'print the processor type (non-portable)' }
        @{ Short = 'i'; Long = 'hardware-platform'; Help = 'print the hardware platform (non-portable)' }
        @{ Short = 'o'; Long = 'operating-system'; Help = 'print the operating system' }
    )
    Notes       = @('PowerShell note: on Windows the kernel name is Windows_NT and the operating system is Windows.')
}

function Invoke-GnuUname {
    <#
    .SYNOPSIS
    GNU uname: print system information.

    .DESCRIPTION
    Prints the selected fields in GNU order: kernel name, node name, kernel release, kernel
    version, machine, processor, hardware platform, operating system.
    Enable the GNU name with: Enable-GnuAlias uname

    .EXAMPLE
    Invoke-GnuUname -sm

    Linux x86_64
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'uname' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            $operands = @($ctx.Operands)
            if ($operands.Count -gt 0) {
                Write-GnuUsageError -Context $ctx -Message "extra operand '$($operands[0])'"
            }
            else {
                $info = Get-GnuOsInfo
                $fields = @(
                    @{ Key = 'kernel-name'; Value = $info.KernelName; Optional = $false }
                    @{ Key = 'nodename'; Value = $info.NodeName; Optional = $false }
                    @{ Key = 'kernel-release'; Value = $info.KernelRelease; Optional = $false }
                    @{ Key = 'kernel-version'; Value = $info.KernelVersion; Optional = $false }
                    @{ Key = 'machine'; Value = $info.Machine; Optional = $false }
                    @{ Key = 'processor'; Value = $info.Processor; Optional = $true }
                    @{ Key = 'hardware-platform'; Value = $info.HardwarePlatform; Optional = $true }
                    @{ Key = 'operating-system'; Value = $info.OperatingSystem; Optional = $false }
                )
                $all = Test-GnuOption -Context $ctx -Key 'all'
                $selected = @($fields | Where-Object { Test-GnuOption -Context $ctx -Key $_.Key })
                if (-not $all -and $selected.Count -eq 0) { $selected = @($fields[0]) }

                $values = foreach ($field in $fields) {
                    $wanted = Test-GnuOption -Context $ctx -Key $field.Key
                    if ($all -and -not ($field.Optional -and $field.Value -eq 'unknown')) { $wanted = $true }
                    if ($selected.Count -eq 1 -and $selected[0].Key -eq $field.Key) { $wanted = $true }
                    if ($wanted) { $field.Value }
                }
                ($values -join ' ')
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}
