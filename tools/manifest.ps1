<#
.SYNOPSIS
    Regenerates FunctionsToExport in the module manifest from src/<Name>/Utils/*.ps1 and the public functions.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot

$sources = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'src') -Directory)
if ($sources.Count -ne 1) { throw "Expected exactly one module folder in src/, found $($sources.Count)." }
$source = $sources[0]
$manifestPath = Join-Path $source.FullName "$($source.Name).psd1"

# Mirrors Get-GnuFunctionName in src/PSGnuUtils/Private/Core/Registry.ps1.
$utils = Get-ChildItem -LiteralPath (Join-Path $source.FullName 'Utils') -Filter '*.ps1' | ForEach-Object {
    $name = $_.BaseName
    'Invoke-Gnu' + $name.Substring(0, 1).ToUpperInvariant() + $name.Substring(1)
}
$functions = @('Disable-GnuLazyLoading', 'Disable-GnuAlias', 'Enable-GnuAlias', 'Get-GnuUtil', 'Import-GnuUtil') + @($utils) | Sort-Object

$list = ($functions | ForEach-Object { "        '$_'" }) -join ",`n"
$replacement = "FunctionsToExport    = @(`n$list`n    )"
$content = [System.IO.File]::ReadAllText($manifestPath)
$updated = [regex]::Replace($content, '(?s)FunctionsToExport\s*=\s*@\(.*?\)', [System.Text.RegularExpressions.MatchEvaluator] { $replacement })
if ($updated -ne $content) {
    [System.IO.File]::WriteAllText($manifestPath, $updated, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Updated $manifestPath ($($functions.Count) functions)."
}
else {
    Write-Host 'Manifest is up to date.'
}
