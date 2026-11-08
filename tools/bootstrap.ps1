<#
.SYNOPSIS
    Installs Pester (>= 5.5) and PSScriptAnalyzer for the current user.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSEdition -ne 'Core') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    # Get-PackageProvider is missing when Windows PowerShell inherits PowerShell 7's PSModulePath.
    if (-not (Get-Command -Name Get-PackageProvider -ErrorAction SilentlyContinue)) {
        throw 'PackageManagement is not available. Start Windows PowerShell with its default PSModulePath (e.g. from cmd.exe, not from pwsh).'
    }
    if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
    }
}
foreach ($module in @(@{ Name = 'Pester'; Version = [version]'5.5.0' }, @{ Name = 'PSScriptAnalyzer'; Version = [version]'1.21.0' })) {
    $installed = Get-Module -ListAvailable -Name $module.Name | Where-Object { $_.Version -ge $module.Version } | Select-Object -First 1
    if ($installed) {
        Write-Host "$($module.Name) $($installed.Version) is installed."
        continue
    }
    Write-Host "Installing $($module.Name) >= $($module.Version) ..."
    Install-Module -Name $module.Name -MinimumVersion $module.Version -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber -Repository PSGallery
}
