function Import-GnuUtil {
    <#
    .SYNOPSIS
    Loads utils now instead of on their first use.

    .DESCRIPTION
    Every util is loaded the first time it runs, which costs about 10 ms once. Import-GnuUtil
    does that work up front, for commands that should answer without that delay. Call it from
    your profile for the utils you use all the time.

    From the source tree every util is already loaded, and this does nothing.

    .PARAMETER Name
    Utils to load. Wildcards are supported (sha*sum).

    .PARAMETER MostUsed
    Load the common everyday utils (ls, cat, grep, head, tail, sort, cp, mv, rm, ...).

    .PARAMETER All
    Load every util.

    .EXAMPLE
    Import-GnuUtil -MostUsed

    .EXAMPLE
    Import-GnuUtil ls, grep, sha*sum
    #>
    [CmdletBinding(DefaultParameterSetName = 'Name')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Name', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [SupportsWildcards()]
        [string[]]$Name,

        [Parameter(Mandatory, ParameterSetName = 'MostUsed')]
        [switch]$MostUsed,

        [Parameter(Mandatory, ParameterSetName = 'All')]
        [switch]$All
    )

    process {
        $patterns = $Name
        if ($All) { $patterns = @('*') }
        if ($MostUsed) { $patterns = @($script:GnuMostUsedUtils | Where-Object { @(Get-GnuUtilNameList) -contains $_ }) }
        foreach ($utilName in @(Resolve-GnuUtilName -Name $patterns)) { Import-GnuUtilBody -Name $utilName }
    }
}
