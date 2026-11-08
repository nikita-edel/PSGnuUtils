<#
.SYNOPSIS
    Runs PSScriptAnalyzer, including the PowerShell 5.1 / 7 syntax rules, on src/, build.ps1 and tools/.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$analyzerMinimumVersion = [version]'1.21.0'

Import-Module PSScriptAnalyzer -MinimumVersion $analyzerMinimumVersion
$settings = Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
$results = @(Invoke-ScriptAnalyzer -Path (Join-Path $repoRoot 'src') -Recurse -Settings $settings)
$results += @(Invoke-ScriptAnalyzer -Path (Join-Path $repoRoot 'tools') -Recurse -Settings $settings)
$results += @(Invoke-ScriptAnalyzer -Path (Join-Path $repoRoot 'build.ps1') -Settings $settings)
if ($results.Count -gt 0) {
    $results | Format-Table -AutoSize -Property Severity, RuleName, ScriptName, Line, Message | Out-String -Width 300 | Write-Host
    throw "PSScriptAnalyzer reported $($results.Count) issue(s)."
}
Write-Host 'No analyzer issues.'
