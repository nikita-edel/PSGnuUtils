function Disable-GnuUtil {
    <#
    .SYNOPSIS
    Removes GNU name aliases created by Enable-GnuAlias and restores the aliases they replaced.

    .DESCRIPTION
    The PowerShell functions (Invoke-GnuCat, ...) stay available. Aliases that Enable-GnuAlias
    replaced (for example cat -> Get-Content) are restored with their original options.
    Removing the module (Remove-Module PSGnuUtils) disables all utils automatically.

    .PARAMETER Name
    Utils to disable. Wildcards are supported.

    .PARAMETER All
    Disable every enabled util.

    .PARAMETER Exclude
    Utils to keep enabled when using -All or wildcards.

    .PARAMETER PassThru
    Return the util info objects (see Get-GnuUtil).

    .EXAMPLE
    Disable-GnuUtil -Name cat

    'cat' is Get-Content again (on Windows).

    .EXAMPLE
    Disable-GnuUtil -All
    #>
    [CmdletBinding(DefaultParameterSetName = 'Name')]
    [OutputType('PSGnuUtils.UtilInfo')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Name', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [SupportsWildcards()]
        [string[]]$Name,

        [Parameter(Mandatory, ParameterSetName = 'All')]
        [switch]$All,

        [SupportsWildcards()]
        [string[]]$Exclude = @(),

        [switch]$PassThru
    )

    process {
        $patterns = $Name
        if ($All) { $patterns = @('*') }

        foreach ($utilName in @(Resolve-GnuUtilName -Name $patterns -Exclude $Exclude)) {
            Disable-GnuUtilAlias -Name $utilName
            if ($PassThru) { Get-GnuUtil -Name $utilName }
        }
    }
}
