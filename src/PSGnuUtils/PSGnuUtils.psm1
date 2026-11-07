<#
    PSGnuUtils root module.

    Load order:
      1. Private  - core framework (argument parser, input/output, registry) and shared libraries
      2. Utils    - one file per GNU util; each registers its spec and defines Invoke-Gnu<Name>
      3. Public   - management commands (Get-GnuUtil, Enable-GnuUtil, Disable-GnuUtil)

    The build (./build.ps1 -Task Build) replaces the "Loader" region below with the
    concatenated source files, so the released module is a single fast-loading psm1.
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

$publicFunctions = @('Get-GnuUtil', 'Enable-GnuUtil', 'Disable-GnuUtil')
$utilFunctions = @($script:GnuUtilRegistry.Values | ForEach-Object { $_.FunctionName })
Export-ModuleMember -Function ($publicFunctions + $utilFunctions)

# Restore every alias we replaced when the module is removed (Remove-Module / Import-Module -Force).
$ExecutionContext.SessionState.Module.OnRemove = { Disable-GnuUtil -All }

if ($Configuration) {
    Invoke-GnuImportConfiguration -Configuration $Configuration
}
