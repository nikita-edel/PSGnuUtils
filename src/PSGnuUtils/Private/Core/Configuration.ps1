# Import-time configuration (Import-Module PSGnuUtils -ArgumentList @{ ... }).

$script:GnuImportOptions = @('All', 'Name', 'Exclude', 'NoClobber')

function Invoke-GnuImportConfiguration {
    <#
    .SYNOPSIS
    Applies the hashtable passed with Import-Module -ArgumentList.
    .DESCRIPTION
    Keys:
      All       = $true          enable every util
      Name      = 'cat', 'head'  enable these utils (wildcards allowed)
      Exclude   = 'ls', 'rm'     with All or Name: skip these utils (wildcards allowed)
      NoClobber = $true          skip names that already resolve to another command
    #>
    param([Parameter(Mandatory)][hashtable]$Configuration)

    foreach ($key in @($Configuration.Keys)) {
        if ($script:GnuImportOptions -notcontains $key) {
            Write-Warning "PSGnuUtils: unknown import option '$key'. Known options: $($script:GnuImportOptions -join ', ')."
        }
    }

    $parameters = @{}
    if ($Configuration.ContainsKey('Exclude')) { $parameters['Exclude'] = [string[]]@($Configuration['Exclude']) }
    if ($Configuration.ContainsKey('NoClobber') -and $Configuration['NoClobber']) { $parameters['NoClobber'] = $true }

    if ($Configuration.ContainsKey('All') -and $Configuration['All']) {
        Enable-GnuAlias -All @parameters
    }
    elseif ($Configuration.ContainsKey('Name')) {
        Enable-GnuAlias -Name ([string[]]@($Configuration['Name'])) @parameters
    }
}
