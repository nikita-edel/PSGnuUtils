<#
.SYNOPSIS
    Build, test and publish automation for PSGnuUtils.

.DESCRIPTION
    Tasks (run in the order given):
      Bootstrap  Install Pester (>= 5.5) and PSScriptAnalyzer for the current user.
      Manifest   Regenerate FunctionsToExport in the module manifest from src/PSGnuUtils/Utils/*.ps1.
      Analyze    Run PSScriptAnalyzer (incl. PowerShell 5.1 / 7 syntax compatibility rules) on src/.
      Test       Run the Pester tests against the source module (tests/).
      Build      Create out/PSGnuUtils: manifest + a single merged psm1 + LICENSE/README.
      TestBuild  Run the Pester tests against the built module in out/PSGnuUtils.
      Publish    Build, then publish out/PSGnuUtils to the PowerShell Gallery.
      Clean      Remove out/.

.EXAMPLE
    ./build.ps1
    Runs Analyze and Test (the default).

.EXAMPLE
    ./build.ps1 -Task Test -TestPath tests/Utils/head.Tests.ps1
    Runs a single test file.

.EXAMPLE
    ./build.ps1 -Task Test -CodeCoverage
    Runs all tests and writes out/coverage.xml (JaCoCo).

.EXAMPLE
    ./build.ps1 -Task Publish -NuGetApiKey $env:PSGALLERY_API_KEY
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Script parameters are used by the task functions below.')]
[CmdletBinding()]
param(
    [ValidateSet('Bootstrap', 'Manifest', 'Analyze', 'Test', 'Build', 'TestBuild', 'Publish', 'Clean')]
    [string[]]$Task = @('Analyze', 'Test'),

    [string[]]$TestPath,

    [switch]$CodeCoverage,

    [string]$NuGetApiKey = $env:PSGALLERY_API_KEY,

    [string]$Repository = 'PSGallery'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = $PSScriptRoot
$SourceDir = Join-Path $RepoRoot 'src/PSGnuUtils'
$ManifestPath = Join-Path $SourceDir 'PSGnuUtils.psd1'
$OutputRoot = Join-Path $RepoRoot 'out'
$OutputDir = Join-Path $OutputRoot 'PSGnuUtils'
$TestsDir = Join-Path $RepoRoot 'tests'
$PesterMinimumVersion = [version]'5.5.0'
$AnalyzerMinimumVersion = [version]'1.21.0'

function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-UtilFunctionName {
    # Mirrors Get-GnuFunctionName in src/PSGnuUtils/Private/Core/Registry.ps1.
    Get-ChildItem -LiteralPath (Join-Path $SourceDir 'Utils') -Filter '*.ps1' | ForEach-Object {
        $name = $_.BaseName
        'Invoke-Gnu' + $name.Substring(0, 1).ToUpperInvariant() + $name.Substring(1)
    }
}

function Invoke-Bootstrap {
    Write-Step 'Bootstrap'
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
    foreach ($module in @(@{ Name = 'Pester'; Version = $PesterMinimumVersion }, @{ Name = 'PSScriptAnalyzer'; Version = $AnalyzerMinimumVersion })) {
        $installed = Get-Module -ListAvailable -Name $module.Name | Where-Object { $_.Version -ge $module.Version } | Select-Object -First 1
        if ($installed) {
            Write-Host "$($module.Name) $($installed.Version) is installed."
            continue
        }
        Write-Host "Installing $($module.Name) >= $($module.Version) ..."
        Install-Module -Name $module.Name -MinimumVersion $module.Version -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber -Repository PSGallery
    }
}

function Invoke-Manifest {
    Write-Step 'Manifest: FunctionsToExport'
    $functions = @('Disable-GnuUtil', 'Enable-GnuUtil', 'Get-GnuUtil') + @(Get-UtilFunctionName) | Sort-Object
    $list = ($functions | ForEach-Object { "        '$_'" }) -join ",`n"
    $replacement = "FunctionsToExport    = @(`n$list`n    )"
    $content = [System.IO.File]::ReadAllText($ManifestPath)
    $updated = [regex]::Replace($content, '(?s)FunctionsToExport\s*=\s*@\(.*?\)', [System.Text.RegularExpressions.MatchEvaluator] { $replacement })
    if ($updated -ne $content) {
        [System.IO.File]::WriteAllText($ManifestPath, $updated, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "Updated $ManifestPath ($($functions.Count) functions)."
    }
    else {
        Write-Host 'Manifest is up to date.'
    }
}

function Invoke-Analyze {
    Write-Step 'Analyze'
    Import-Module PSScriptAnalyzer -MinimumVersion $AnalyzerMinimumVersion
    $settings = Join-Path $RepoRoot 'PSScriptAnalyzerSettings.psd1'
    $results = @(Invoke-ScriptAnalyzer -Path $SourceDir -Recurse -Settings $settings)
    $results += @(Invoke-ScriptAnalyzer -Path (Join-Path $RepoRoot 'build.ps1') -Settings $settings)
    if ($results.Count -gt 0) {
        $results | Format-Table -AutoSize -Property Severity, RuleName, ScriptName, Line, Message | Out-String -Width 300 | Write-Host
        throw "PSScriptAnalyzer reported $($results.Count) issue(s)."
    }
    Write-Host 'No analyzer issues.'
}

function Invoke-Test([string]$ModuleManifest) {
    Write-Step "Test ($ModuleManifest)"
    Import-Module Pester -MinimumVersion $PesterMinimumVersion
    $env:PSGNUUTILS_TEST_MANIFEST = $ModuleManifest

    $configuration = New-PesterConfiguration
    $configuration.Run.Path = @($TestsDir)
    if ($TestPath) { $configuration.Run.Path = $TestPath }
    $configuration.Run.PassThru = $true
    $configuration.Output.Verbosity = 'Detailed'
    $null = New-Item -ItemType Directory -Force -Path $OutputRoot
    $configuration.TestResult.Enabled = $true
    $configuration.TestResult.OutputFormat = 'NUnitXml'
    $configuration.TestResult.OutputPath = Join-Path $OutputRoot "testResults-$($PSVersionTable.PSEdition).xml"
    if ($CodeCoverage) {
        $configuration.CodeCoverage.Enabled = $true
        $configuration.CodeCoverage.Path = @(Get-ChildItem -LiteralPath $SourceDir -Recurse -Filter '*.ps1' | ForEach-Object { $_.FullName })
        $configuration.CodeCoverage.OutputPath = Join-Path $OutputRoot 'coverage.xml'
        $configuration.CodeCoverage.CoveragePercentTarget = 90
    }

    try {
        $result = Invoke-Pester -Configuration $configuration
    }
    finally {
        Remove-Item Env:\PSGNUUTILS_TEST_MANIFEST -ErrorAction SilentlyContinue
    }
    if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') {
        throw "$($result.FailedCount) test(s) failed."
    }
}

function Invoke-Build {
    Invoke-Manifest
    Write-Step "Build -> $OutputDir"
    if (Test-Path -LiteralPath $OutputDir) { Remove-Item -LiteralPath $OutputDir -Recurse -Force }
    $null = New-Item -ItemType Directory -Force -Path $OutputDir

    $builder = New-Object System.Text.StringBuilder
    foreach ($folder in @('Private', 'Utils', 'Public')) {
        foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $SourceDir $folder) -Filter '*.ps1' -Recurse | Sort-Object -Property FullName)) {
            $relative = $file.FullName.Substring($SourceDir.Length + 1).Replace('\', '/')
            [void]$builder.AppendLine("#region $relative")
            [void]$builder.AppendLine([System.IO.File]::ReadAllText($file.FullName).TrimEnd())
            [void]$builder.AppendLine("#endregion $relative")
            [void]$builder.AppendLine()
        }
    }
    $merged = $builder.ToString()
    $rootModule = [System.IO.File]::ReadAllText((Join-Path $SourceDir 'PSGnuUtils.psm1'))
    $rootModule = [regex]::Replace($rootModule, '(?s)#region Loader.*?#endregion Loader', [System.Text.RegularExpressions.MatchEvaluator] { $merged.TrimEnd() })

    # UTF-8 with BOM so Windows PowerShell 5.1 never misreads the file.
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText((Join-Path $OutputDir 'PSGnuUtils.psm1'), $rootModule, $utf8Bom)
    Copy-Item -LiteralPath $ManifestPath -Destination $OutputDir
    foreach ($extra in @('LICENSE', 'README.md', 'CHANGELOG.md')) {
        $path = Join-Path $RepoRoot $extra
        if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination $OutputDir }
    }

    $null = Test-ModuleManifest -Path (Join-Path $OutputDir 'PSGnuUtils.psd1')
    Write-Host "Built $OutputDir"
}

function Invoke-Publish {
    if (-not $NuGetApiKey) { throw 'Publish needs -NuGetApiKey or $env:PSGALLERY_API_KEY.' }
    Invoke-Build
    Write-Step "Publish to $Repository"
    Publish-Module -Path $OutputDir -NuGetApiKey $NuGetApiKey -Repository $Repository
}

foreach ($name in $Task) {
    switch ($name) {
        'Bootstrap' { Invoke-Bootstrap }
        'Manifest' { Invoke-Manifest }
        'Analyze' { Invoke-Analyze }
        'Test' { Invoke-Test -ModuleManifest $ManifestPath }
        'Build' { Invoke-Build }
        'TestBuild' { Invoke-Test -ModuleManifest (Join-Path $OutputDir 'PSGnuUtils.psd1') }
        'Publish' { Invoke-Publish }
        'Clean' {
            Write-Step 'Clean'
            if (Test-Path -LiteralPath $OutputRoot) { Remove-Item -LiteralPath $OutputRoot -Recurse -Force }
        }
    }
}
