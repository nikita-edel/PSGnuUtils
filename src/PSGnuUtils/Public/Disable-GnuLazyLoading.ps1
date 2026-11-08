function Disable-GnuLazyLoading {
    <#
    .SYNOPSIS
    Turns lazy loading off for this session by loading every util now.

    .DESCRIPTION
    Normally each util loads the first time it runs. After this command every util is in memory
    and none of them loads on first use. This takes about 200 ms and needs more memory, so it
    only pays off if no first call may ever be delayed. Put it in your profile to make it permanent.

    .EXAMPLE
    Disable-GnuLazyLoading
    #>
    [CmdletBinding()]
    param()

    foreach ($utilName in @(Get-GnuUtilNameList)) { Import-GnuUtilBody -Name $utilName }
}
