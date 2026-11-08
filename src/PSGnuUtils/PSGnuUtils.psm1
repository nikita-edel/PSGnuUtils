<#
    PSGnuUtils root module.

    Load order:
      1. Private  - core framework (argument parser, input/output, registry) and shared libraries
      2. Utils    - one file per GNU util; each registers its spec and defines Invoke-Gnu<Name>
      3. Public   - management commands (Get-GnuUtil, Enable-GnuAlias, Disable-GnuAlias, Import-GnuUtil, Disable-GnuLazyLoading)

    The build (./build.ps1 -Build) replaces the "Loader" region below with the
    concatenated core and each util's small entry function; everything else of a util
    stays in Utils/<name>.ps1 and is loaded on the util's first call.
#>
param(
    # Optional import-time configuration, for example:
    #   Import-Module PSGnuUtils -ArgumentList @{ All = $true; Exclude = 'ls', 'rm' }
    #   Import-Module PSGnuUtils -ArgumentList @{ Name = 'cat', 'head', 'tail' }
    [hashtable]$Configuration
)

Set-StrictMode -Version Latest

#region Loader
foreach ($folder in @('Private', 'Utils', 'Public')) {
    $folderPath = Join-Path -Path $PSScriptRoot -ChildPath $folder
    if (-not (Test-Path -LiteralPath $folderPath)) { continue }
    foreach ($file in @(Get-ChildItem -LiteralPath $folderPath -Filter '*.ps1' -Recurse | Sort-Object -Property FullName)) {
        . $file.FullName
    }
}
#endregion Loader

$publicFunctions = @('Get-GnuUtil', 'Enable-GnuAlias', 'Disable-GnuAlias', 'Import-GnuUtil', 'Disable-GnuLazyLoading')
$utilFunctions = @(Get-GnuUtilNameList | ForEach-Object { Get-GnuFunctionName -Name $_ })
Export-ModuleMember -Function ($publicFunctions + $utilFunctions)

# Restore every alias we replaced when the module is removed (Remove-Module / Import-Module -Force).
$ExecutionContext.SessionState.Module.OnRemove = { Disable-GnuAlias -All }

if ($Configuration) {
    Invoke-GnuImportConfiguration -Configuration $Configuration
}
