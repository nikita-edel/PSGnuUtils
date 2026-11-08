<#
.SYNOPSIS
    Test, install, package and publish this module.

.DESCRIPTION
    Several actions can be combined; they run in the order Bootstrap, Clean, Manifest, Analyze, Test, Build,
    TestBuild, Package, Install, Uninstall, Publish. The scripts behind them are in tools/.

.PARAMETER Bootstrap
    Install Pester (>= 5.5) and PSScriptAnalyzer for the current user.

.PARAMETER Clean
    Remove out/.

.PARAMETER Manifest
    Regenerate FunctionsToExport in the module manifest from the utils.

.PARAMETER Analyze
    Run PSScriptAnalyzer on src/, build.ps1 and tools/.

.PARAMETER Test
    Run the Pester tests against the source module, in a process without a profile. Names after -Test select what
    runs: a test name, or a path to a test file or folder.

.PARAMETER TestName
    The tests to run. Given positionally, after -Test or -TestBuild.

.PARAMETER CodeCoverage
    With -Test: write out/coverage.xml (JaCoCo) and fail below 98% line coverage.

.PARAMETER TestTimeoutMinutes
    With -Test or -TestBuild: stop the run if it takes longer than this, so a hanging test cannot block.

.PARAMETER Build
    Stage the module in out/<Name>/<Version>, with its utils split for loading on first use.

.PARAMETER TestBuild
    Run the Pester tests against the staged module. Run -Build first, or together with this.

.PARAMETER Package
    Write out/<Name>-<Version>.zip: the module and an install.ps1 that installs it offline.

.PARAMETER Install
    Build the module and run tools/install.ps1 to install it for the current user.

.PARAMETER Uninstall
    Remove the installed copy of the current version again.

.PARAMETER ModulePath
    With -Install or -Uninstall: module folder(s) to use instead of the current user's default ones.

.PARAMETER Publish
    The PowerShell Gallery API key. Builds the module and publishes it.

.PARAMETER Repository
    With -Publish: the repository to publish to.

.EXAMPLE
    ./build.ps1 -Analyze -Test
    Runs the analyzer and all tests.

.EXAMPLE
    ./build.ps1 -Test head tests/Core
    Runs tests/Utils/head.Tests.ps1 and everything in tests/Core.

.EXAMPLE
    ./build.ps1 -Test -CodeCoverage

.EXAMPLE
    ./build.ps1 -Build -TestBuild

.EXAMPLE
    ./build.ps1 -Install

.EXAMPLE
    ./build.ps1 -Package

.EXAMPLE
    ./build.ps1 -Publish $env:PSGALLERY_API_KEY
#>
[CmdletBinding()]
param(
    [switch]$Test,

    # object[], not string[]: -Test a,b arrives here as one array, which string[] would join into 'a b'.
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [object[]]$TestName,

    [switch]$TestBuild,

    [switch]$CodeCoverage,

    [ValidateRange(1, 1440)]
    [int]$TestTimeoutMinutes = 30,

    [switch]$Bootstrap,

    [switch]$Clean,

    [switch]$Manifest,

    [switch]$Analyze,

    [switch]$Build,

    [switch]$Package,

    [switch]$Install,

    [switch]$Uninstall,

    [string[]]$ModulePath,

    [string]$Publish,

    [string]$Repository = 'PSGallery'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$tools = Join-Path $PSScriptRoot 'tools'
$names = @($TestName | ForEach-Object { $_ } | Where-Object { $_ } | ForEach-Object { [string]$_ })
$wantsPublish = $PSBoundParameters.ContainsKey('Publish')

if ($names.Count -gt 0 -and -not ($Test -or $TestBuild)) { throw "Unexpected argument(s): $($names -join ' '). Test names go after -Test." }
if ($wantsPublish -and [string]::IsNullOrWhiteSpace($Publish)) { throw 'The API key given to -Publish is empty.' }
if ($wantsPublish -and -not (Get-Command -Name Publish-PSResource -ErrorAction SilentlyContinue)) {
    throw 'Publishing needs PSResourceGet, which comes with PowerShell 7.4 and later. Use pwsh, or: Install-Module Microsoft.PowerShell.PSResourceGet -Scope CurrentUser'
}
if (-not ($Bootstrap -or $Clean -or $Manifest -or $Analyze -or $Test -or $Build -or $TestBuild -or $Package -or $Install -or $Uninstall -or $wantsPublish)) {
    Get-Help -Name $PSCommandPath
    return
}

function Invoke-TestProcess([string]$ManifestPath) {
    # A process of its own: a profile that loads the installed module puts a second copy beside the one under test
    # (Pester refuses that), its aliases would leak in, and the watchdog would kill the user's shell.
    $command = "& '$((Join-Path $tools 'test.ps1') -replace "'", "''")' -TimeoutMinutes $TestTimeoutMinutes"
    if ($ManifestPath) { $command += " -ManifestPath '$($ManifestPath -replace "'", "''")'" }
    if ($names.Count -gt 0) { $command += ' -Name ' + (@($names | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ',') }
    if ($CodeCoverage) { $command += ' -CodeCoverage' }
    $originalModulePath = $env:PSModulePath
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        # Started from PowerShell 7, Windows PowerShell inherits 7's module folders and loses core cmdlets (Get-Acl, ...).
        $folders = @($env:PSModulePath -split ';' | Where-Object { $_ -notmatch '\\PowerShell\\|microsoft\.powershell_' })
        $system = Join-Path $PSHOME 'Modules'
        if ($folders -notcontains $system) { $folders += $system }
        $env:PSModulePath = $folders -join ';'
    }
    try {
        & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -Command $command
        if ($LASTEXITCODE -ne 0) { throw 'The tests failed; see the output above.' }
    }
    finally {
        $env:PSModulePath = $originalModulePath
    }
}

if ($Bootstrap) { & (Join-Path $tools 'bootstrap.ps1') }

if ($Clean) {
    $output = Join-Path $PSScriptRoot 'out'
    if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Recurse -Force }
}

if ($Manifest) { & (Join-Path $tools 'manifest.ps1') }

if ($Analyze) { & (Join-Path $tools 'analyze.ps1') }

if ($Test) { Invoke-TestProcess }

if ($Build) { $null = & (Join-Path $tools 'build.ps1') }

if ($TestBuild) {
    $sourceManifest = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'src/*/*.psd1'))[0]
    $version = [string](Import-PowerShellDataFile -Path $sourceManifest.FullName).ModuleVersion
    $staged = Join-Path $PSScriptRoot "out/$($sourceManifest.BaseName)/$version/$($sourceManifest.Name)"
    if (-not (Test-Path -LiteralPath $staged)) { throw "$staged does not exist. Run -Build first." }
    Invoke-TestProcess -ManifestPath $staged
}

if ($Package) {
    $null = & (Join-Path $tools 'package.ps1')
}

if ($Install -or $Uninstall) {
    $module = & (Join-Path $tools 'build.ps1')
    $installArguments = @{ SourcePath = Split-Path -Parent (Split-Path -Parent $module.Path) }
    if ($ModulePath) { $installArguments.ModulePath = $ModulePath }
    if ($Install) { & (Join-Path $tools 'install.ps1') @installArguments }
    if ($Uninstall) { & (Join-Path $tools 'install.ps1') @installArguments -Uninstall }
}

if ($wantsPublish) {
    $module = & (Join-Path $tools 'build.ps1')
    # Not Publish-Module: it needs nuget or dotnet, and parses nuget's English output, so it fails on other locales.
    Publish-PSResource -Path $module.Path -ApiKey $Publish -Repository $Repository -ErrorAction Stop
    Write-Host "Published $($module.Name) $($module.Version) to $Repository"
}
