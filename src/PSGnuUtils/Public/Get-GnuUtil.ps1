function Get-GnuUtil {
    <#
    .SYNOPSIS
    Lists the GNU utils provided by PSGnuUtils.

    .DESCRIPTION
    Returns one object per util with its GNU name, category, PowerShell function name, whether
    the GNU name is currently enabled (see Enable-GnuAlias) and what the GNU name resolves to
    without PSGnuUtils (for example 'Alias -> Get-Content' for cat on Windows).

    .PARAMETER Name
    Util names to return. Wildcards are supported. Default: all utils.

    .PARAMETER Category
    Only return utils of this category (wildcards supported), e.g. 'Checksums'.

    .PARAMETER Enabled
    Only return utils whose GNU name is currently enabled.

    .EXAMPLE
    Get-GnuUtil

    Lists all utils.

    .EXAMPLE
    Get-GnuUtil -Name sha*sum

    Lists the checksum utils.

    .EXAMPLE
    Get-GnuUtil -Enabled | Disable-GnuUtil

    Disables every enabled util.
    #>
    [CmdletBinding()]
    [OutputType('PSGnuUtils.UtilInfo')]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [SupportsWildcards()]
        [string[]]$Name,

        [SupportsWildcards()]
        [string]$Category = '*',

        [switch]$Enabled
    )

    process {
        $patterns = $Name
        if ($null -eq $patterns -or $patterns.Count -eq 0) { $patterns = @('*') }
        foreach ($utilName in @(Resolve-GnuUtilName -Name $patterns)) {
            $summary = Get-GnuUtilSummary -Name $utilName
            if ($summary.Category -notlike $Category) { continue }
            $isEnabled = $script:GnuEnabledUtils.ContainsKey($utilName)
            if ($Enabled -and -not $isEnabled) { continue }

            [pscustomobject]@{
                PSTypeName = 'PSGnuUtils.UtilInfo'
                Name       = $utilName
                Category   = $summary.Category
                Synopsis   = $summary.Synopsis
                Command    = $summary.FunctionName
                Enabled    = $isEnabled
                Shadows    = Get-GnuShadowedCommand -Name $utilName
            }
        }
    }
}
