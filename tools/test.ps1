<#
.SYNOPSIS
    Runs the Pester tests. Use ./build.ps1 -Test, which starts this in a process without a profile.

.PARAMETER Name
    Tests to run: a test name (head, wildcards allowed) or a path to a test file or folder.
    Without it, everything in tests/ runs.

.PARAMETER ManifestPath
    The module to test. Defaults to the source module; ./build.ps1 -TestBuild passes the staged one.

.PARAMETER CodeCoverage
    Write out/coverage.xml (JaCoCo) and fail below the minimum line coverage.

.PARAMETER TimeoutMinutes
    Stop the run, and the process, if it takes longer than this, so a hanging test cannot block.
#>
[CmdletBinding()]
param(
    [string[]]$Name,
    [string]$ManifestPath,
    [switch]$CodeCoverage,
    [ValidateRange(1, 1440)]
    [int]$TimeoutMinutes = 30
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$testsDir = Join-Path $repoRoot 'tests'
$outputRoot = Join-Path $repoRoot 'out'
$pesterMinimumVersion = [version]'5.5.0'
# 100% on Windows; Linux/macOS cannot run the Windows-only branches (and vice versa).
$coverageMinimum = 98

$sources = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'src') -Directory)
if ($sources.Count -ne 1) { throw "Expected exactly one module folder in src/, found $($sources.Count)." }
if (-not $ManifestPath) { $ManifestPath = Join-Path $sources[0].FullName "$($sources[0].Name).psd1" }

if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge $pesterMinimumVersion })) {
    throw "Pester >= $pesterMinimumVersion is required: ./build.ps1 -Bootstrap"
}
Import-Module Pester -MinimumVersion $pesterMinimumVersion

$paths = @($testsDir)
if ($Name) {
    $paths = @(foreach ($item in $Name) {
            if (Test-Path -LiteralPath $item) {
                (Resolve-Path -LiteralPath $item).ProviderPath
                continue
            }
            $found = @(Get-ChildItem -LiteralPath $testsDir -Recurse -File -Filter "$item.Tests.ps1")
            if ($found.Count -eq 0) { throw "No test matches '$item'." }
            $found.FullName
        })
}

Write-Host "==> Test ($ManifestPath)"
$env:PSGNUUTILS_TEST_MANIFEST = $ManifestPath

$configuration = New-PesterConfiguration
$configuration.Run.Path = $paths
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Detailed'
$null = New-Item -ItemType Directory -Force -Path $outputRoot
$configuration.TestResult.Enabled = $true
$configuration.TestResult.OutputFormat = 'NUnitXml'
$configuration.TestResult.OutputPath = Join-Path $outputRoot "testResults-$($PSVersionTable.PSEdition).xml"
if ($CodeCoverage) {
    $configuration.CodeCoverage.Enabled = $true
    $configuration.CodeCoverage.Path = @(Get-ChildItem -LiteralPath $sources[0].FullName -Recurse -Filter '*.ps1' | ForEach-Object { $_.FullName })
    $configuration.CodeCoverage.OutputPath = Join-Path $outputRoot 'coverage.xml'
    $configuration.CodeCoverage.CoveragePercentTarget = $coverageMinimum
}

# No test may wait for console input: an accidental read gets end-of-file instead of blocking.
$originalInput = [Console]::In
[Console]::SetIn((New-Object System.IO.StringReader -ArgumentList ''))
# Watchdog in a second runspace: ends the process if the tests hang (the last test shown is the culprit).
$watchdog = [powershell]::Create()
$null = $watchdog.AddScript({
        param($Minutes)
        Start-Sleep -Seconds ($Minutes * 60)
        [Console]::Error.WriteLine("tools/test.ps1: the tests did not finish within $Minutes minutes; the last test shown above hangs. Stopping.")
        [System.Diagnostics.Process]::GetCurrentProcess().Kill()
    }).AddArgument($TimeoutMinutes)
$watch = $watchdog.BeginInvoke()
try {
    $result = Invoke-Pester -Configuration $configuration
}
finally {
    $watchdog.Stop()
    $watchdog.Dispose()
    $null = $watch
    [Console]::SetIn($originalInput)
    Remove-Item Env:\PSGNUUTILS_TEST_MANIFEST -ErrorAction SilentlyContinue
}
if ($result.Result -ne 'Passed') { throw "$($result.FailedCount) test(s) failed." }
if ($CodeCoverage -and $result.CodeCoverage.CoveragePercent -lt $coverageMinimum) {
    throw "Code coverage $([Math]::Round($result.CodeCoverage.CoveragePercent, 2))% is below the minimum of $coverageMinimum%."
}
