<#
.SYNOPSIS
    Installs PSGnuUtils from this release package, without internet access.

.DESCRIPTION
    Copies the PSGnuUtils/<version> folder next to this script into the current user's module folder(s), so
    that 'Import-Module PSGnuUtils' works in new sessions. On Windows that is both Windows PowerShell 5.1
    (Documents\WindowsPowerShell\Modules) and PowerShell 7 (Documents\PowerShell\Modules); on Linux and macOS
    ~/.local/share/powershell/Modules. An installed copy of the same version is replaced.

.PARAMETER ModulePath
    Module folder(s) to use instead of the default ones.

.PARAMETER Uninstall
    Remove this version again.

.EXAMPLE
    ./install.ps1

.EXAMPLE
    ./install.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [string[]]$ModulePath,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$source = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'PSGnuUtils') -Directory)
if ($source.Count -ne 1) { throw "Expected one version folder in $(Join-Path $PSScriptRoot 'PSGnuUtils')." }
$version = $source[0].Name

$roots = $ModulePath
if (-not $roots) {
    # $IsWindows does not exist in Windows PowerShell 5.1; -or stops before reading it there.
    if ($PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows) {
        $documents = [Environment]::GetFolderPath('MyDocuments')
        $roots = @((Join-Path $documents 'PowerShell/Modules'), (Join-Path $documents 'WindowsPowerShell/Modules'))
    }
    else {
        $dataHome = $env:XDG_DATA_HOME
        if (-not $dataHome) { $dataHome = Join-Path $HOME '.local/share' }
        $roots = @(Join-Path $dataHome 'powershell/Modules')
    }
}

foreach ($root in $roots) {
    $moduleRoot = Join-Path $root 'PSGnuUtils'
    $target = Join-Path $moduleRoot $version
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    if ($Uninstall) {
        if ((Test-Path -LiteralPath $moduleRoot) -and @(Get-ChildItem -LiteralPath $moduleRoot -Force).Count -eq 0) { Remove-Item -LiteralPath $moduleRoot -Force }
        Write-Host "Removed PSGnuUtils $version from $root"
        continue
    }
    $null = New-Item -ItemType Directory -Force -Path $target
    Copy-Item -Path (Join-Path $source[0].FullName '*') -Destination $target -Recurse -Force
    # Files from a downloaded zip are marked as coming from the internet, which blocks them under RemoteSigned.
    # Unblock-File exists in PowerShell on Linux and macOS too, but fails there.
    if ($PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows) { Get-ChildItem -LiteralPath $target -Recurse -File | Unblock-File }
    Write-Host "Installed PSGnuUtils $version to $target"
}
if (-not $Uninstall) { Write-Host 'In a new session: Import-Module PSGnuUtils' }
