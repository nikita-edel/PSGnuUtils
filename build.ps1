<#
.SYNOPSIS
    Build, test and publish automation for PSGnuUtils.

.DESCRIPTION
    Run tasks with switches (./build.ps1 -Test -Install) or by name (./build.ps1 -Task Test, Install).
    Switches run in the order listed below; -Task values run in the order given, before any switches.
    Without any task, Analyze and Test run.

    Tasks:
      Bootstrap  Install Pester (>= 5.5) and PSScriptAnalyzer for the current user.
      Manifest   Regenerate FunctionsToExport in the module manifest from src/PSGnuUtils/Utils/*.ps1.
      Analyze    Run PSScriptAnalyzer (incl. PowerShell 5.1 / 7 syntax compatibility rules) on src/.
      Test       Run the Pester tests against the source module (tests/).
      Build      Create out/PSGnuUtils: manifest + a single merged psm1 + LICENSE/README.
      TestBuild  Run the Pester tests against the built module in out/PSGnuUtils.
      Install    Build, then copy the module into the current user's module folder(s), so that
                 'Import-Module PSGnuUtils' works in new sessions. On Windows both Windows PowerShell 5.1
                 (Documents\WindowsPowerShell\Modules) and PowerShell 7 (Documents\PowerShell\Modules);
                 on Linux/macOS ~/.local/share/powershell/Modules. -ModulePath overrides the target.
      Uninstall  Remove the installed copy of the current version again.
      Publish    Build, then publish out/PSGnuUtils to the PowerShell Gallery.
      Clean      Remove out/.

.EXAMPLE
    ./build.ps1
    Runs Analyze and Test (the default).

.EXAMPLE
    ./build.ps1 -Test -TestPath tests/Utils/head.Tests.ps1
    Runs a single test file.

.EXAMPLE
    ./build.ps1 -Test -CodeCoverage
    Runs all tests, writes out/coverage.xml (JaCoCo) and fails below 98% line coverage.

.EXAMPLE
    ./build.ps1 -Test -TestTimeoutMinutes 10
    Stops the run if the tests take longer than 10 minutes (default 30), so a hanging test cannot block.
    Standard input is empty during the tests: a test that reads the console gets end-of-file.
    The tests run in a child process without a profile, so a module or aliases loaded by the profile cannot interfere.

.EXAMPLE
    ./build.ps1 -Install
    Builds and installs the module for the current user (open a new session, then: Import-Module PSGnuUtils).

.EXAMPLE
    ./build.ps1 -Publish -NuGetApiKey $env:PSGALLERY_API_KEY
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Script parameters are used by the task functions below.')]
[CmdletBinding()]
param(
    # Tasks by name (for scripts). The switches below do the same: ./build.ps1 -Install
    [ValidateSet('Bootstrap', 'Manifest', 'Analyze', 'Test', 'Build', 'TestBuild', 'Install', 'Uninstall', 'Publish', 'Clean')]
    [string[]]$Task,

    [switch]$Bootstrap,
    [switch]$Clean,
    [switch]$Manifest,
    [switch]$Analyze,
    [switch]$Test,
    [switch]$Build,
    [switch]$TestBuild,
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Publish,


    [string[]]$TestPath,

    [switch]$CodeCoverage,

    # Test/TestBuild: stop the run (and the process) if it takes longer than this, so a hanging test cannot block.
    [ValidateRange(1, 1440)]
    [int]$TestTimeoutMinutes = 30,

    [string]$NuGetApiKey = $env:PSGALLERY_API_KEY,

    # Install/Uninstall: module folder(s) to use instead of the current user's default module folder(s).
    [string[]]$ModulePath,

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
# 100% on Windows; Linux/macOS cannot run the Windows-only branches (and vice versa).
$CoverageMinimum = 98

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
    $functions = @('Disable-GnuLazyLoading', 'Disable-GnuUtil', 'Enable-GnuAlias', 'Get-GnuUtil', 'Import-GnuUtil') + @(Get-UtilFunctionName) | Sort-Object
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

function Invoke-IsolatedTest([string]$TaskName) {
    # The tests get a process of their own: a profile that loads the installed module puts a second PSGnuUtils beside
    # the one under test (Pester refuses that), its aliases would leak in, and the watchdog would kill the user's shell.
    $arguments = @("-Task $TaskName", "-TestTimeoutMinutes $TestTimeoutMinutes")
    if ($TestPath) { $arguments += '-TestPath ' + (@($TestPath | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ',') }
    if ($CodeCoverage) { $arguments += '-CodeCoverage' }
    $command = "& '$($PSCommandPath -replace "'", "''")' $($arguments -join ' ')"
    $originalModulePath = $env:PSModulePath
    $env:PSGNUUTILS_TEST_ISOLATED = '1'
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
        Remove-Item Env:\PSGNUUTILS_TEST_ISOLATED -ErrorAction SilentlyContinue
    }
}

function Invoke-Test([string]$ModuleManifest, [string]$TaskName) {
    if (-not $env:PSGNUUTILS_TEST_ISOLATED) { Invoke-IsolatedTest -TaskName $TaskName; return }
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
        $configuration.CodeCoverage.CoveragePercentTarget = $CoverageMinimum
    }

    # No test may wait for console input: an accidental read gets end-of-file instead of blocking.
    $originalInput = [Console]::In
    [Console]::SetIn((New-Object System.IO.StringReader -ArgumentList ''))
    # Watchdog in a second runspace: ends the process if the tests hang (the last test shown is the culprit).
    $watchdog = [powershell]::Create()
    $null = $watchdog.AddScript({
            param($Minutes)
            Start-Sleep -Seconds ($Minutes * 60)
            [Console]::Error.WriteLine("build.ps1: the tests did not finish within $Minutes minutes; the last test shown above hangs. Stopping.")
            [System.Diagnostics.Process]::GetCurrentProcess().Kill()
        }).AddArgument($TestTimeoutMinutes)
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
    if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') {
        throw "$($result.FailedCount) test(s) failed."
    }
    if ($CodeCoverage -and $result.CodeCoverage.CoveragePercent -lt $CoverageMinimum) {
        throw "Code coverage $([Math]::Round($result.CodeCoverage.CoveragePercent, 2))% is below the minimum of $CoverageMinimum%."
    }
}

function Get-UtilSummary {
    # Category and synopsis of every util, from the source module in a runspace of its own: some specs are built by code.
    $shell = [powershell]::Create()
    try {
        $null = $shell.AddScript({ param($Manifest) Import-Module -Name $Manifest -ErrorAction Stop; Get-GnuUtil }).AddArgument($ManifestPath)
        $summaries = @{}
        foreach ($util in $shell.Invoke()) { $summaries[$util.Name] = $util }
        $summaries
    }
    finally { $shell.Dispose() }
}

function Get-LazyUtilText($Ast, [string]$Text, $Entry) {
    # The file without its entry function. Helpers become script: functions: the file is dot-sourced from inside a
    # function of the module, where a plain definition would vanish when that function returns.
    $edited = New-Object System.Text.StringBuilder -ArgumentList $Text
    $functions = @($Ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false) | Sort-Object -Property { $_.Extent.StartOffset } -Descending)
    foreach ($function in $functions) {
        if ([object]::ReferenceEquals($function, $Entry)) {
            [void]$edited.Remove($function.Extent.StartOffset, $function.Extent.EndOffset - $function.Extent.StartOffset)
            continue
        }
        $start = $function.Extent.StartOffset + $function.Extent.Text.IndexOf($function.Name, [System.StringComparison]::Ordinal)
        [void]$edited.Insert($start, 'script:')
    }
    $edited.ToString()
}

function Split-UtilForLazyLoading([System.Text.Encoding]$Encoding) {
    # Writes each util without its entry function to out/.../Utils and returns the psm1 text: the entry functions
    # plus the index the module needs to list utils and to load them on first use.
    $utilsOut = Join-Path $OutputDir 'Utils'
    $null = New-Item -ItemType Directory -Force -Path $utilsOut
    $parsed = @{}
    $owners = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $SourceDir 'Utils') -Filter '*.ps1' | Sort-Object -Property Name)) {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        $parsed[$file.BaseName] = @{ Ast = $ast; Text = [System.IO.File]::ReadAllText($file.FullName) }
        foreach ($function in $ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { $owners[$function.Name] = $file.BaseName }
    }

    $summaries = Get-UtilSummary
    $entries = New-Object System.Text.StringBuilder
    $index = New-Object System.Text.StringBuilder
    [void]$index.AppendLine('$script:GnuLazyRoot = [System.IO.Path]::Combine($PSScriptRoot, ''Utils'')')
    [void]$index.AppendLine('$script:GnuLazyUtils = @{')
    foreach ($name in @($parsed.Keys | Sort-Object)) {
        $ast = $parsed[$name].Ast
        $text = $parsed[$name].Text
        $entryName = 'Invoke-Gnu' + $name.Substring(0, 1).ToUpperInvariant() + $name.Substring(1)
        $entry = @($ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq $entryName }, $false))[0]
        if ($null -eq $entry -or $entry.Extent.Text -notmatch 'Initialize-GnuUtil -Name') { throw "$($name).ps1: $entryName must exist and start with Initialize-GnuUtil." }
        [void]$entries.AppendLine($entry.Extent.Text).AppendLine()
        $remainder = Get-LazyUtilText -Ast $ast -Text $text -Entry $entry
        [System.IO.File]::WriteAllText((Join-Path $utilsOut "$name.ps1"), $remainder, $Encoding)

        $depends = @($ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } |
            Where-Object { $_ -and $owners.ContainsKey($_) -and $owners[$_] -cne $name -and $_ -cnotlike 'Invoke-Gnu*' } | ForEach-Object { $owners[$_] } | Sort-Object -Unique)
        $dependsText = @($depends | ForEach-Object { "'$_'" }) -join ', '
        $category = $summaries[$name].Category.Replace("'", "''")
        $synopsis = $summaries[$name].Synopsis.Replace("'", "''")
        [void]$index.AppendLine("    '$name' = @{ File = '$name.ps1'; Depends = @($dependsText); Category = '$category'; Synopsis = '$synopsis'; Loaded = `$false }")
    }
    [void]$index.AppendLine('}')
    $index.ToString() + [Environment]::NewLine + $entries.ToString()
}

function Invoke-Build {
    Invoke-Manifest
    Write-Step "Build -> $OutputDir"
    if (Test-Path -LiteralPath $OutputDir) { Remove-Item -LiteralPath $OutputDir -Recurse -Force }
    $null = New-Item -ItemType Directory -Force -Path $OutputDir

    # UTF-8 with BOM so Windows PowerShell 5.1 never misreads the files.
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    $builder = New-Object System.Text.StringBuilder
    foreach ($folder in @('Private', 'Public')) {
        foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $SourceDir $folder) -Filter '*.ps1' -Recurse | Sort-Object -Property FullName)) {
            $relative = $file.FullName.Substring($SourceDir.Length + 1).Replace('\', '/')
            [void]$builder.AppendLine("#region $relative")
            [void]$builder.AppendLine([System.IO.File]::ReadAllText($file.FullName).TrimEnd())
            [void]$builder.AppendLine("#endregion $relative")
            [void]$builder.AppendLine()
        }
    }
    [void]$builder.AppendLine((Split-UtilForLazyLoading -Encoding $utf8Bom))
    $merged = $builder.ToString()
    $rootModule = [System.IO.File]::ReadAllText((Join-Path $SourceDir 'PSGnuUtils.psm1'))
    $rootModule = [regex]::Replace($rootModule, '(?s)#region Loader.*?#endregion Loader', [System.Text.RegularExpressions.MatchEvaluator] { $merged.TrimEnd() })

    [System.IO.File]::WriteAllText((Join-Path $OutputDir 'PSGnuUtils.psm1'), $rootModule, $utf8Bom)
    Copy-Item -LiteralPath $ManifestPath -Destination $OutputDir
    foreach ($extra in @('LICENSE', 'README.md', 'CHANGELOG.md')) {
        $path = Join-Path $RepoRoot $extra
        if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination $OutputDir }
    }

    $null = Test-ModuleManifest -Path (Join-Path $OutputDir 'PSGnuUtils.psd1')
    Write-Host "Built $OutputDir"
}

function Get-InstallRoot {
    if ($ModulePath) { return $ModulePath }
    # $IsWindows does not exist in Windows PowerShell 5.1; -or stops before reading it there.
    if ($PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows) {
        $documents = [Environment]::GetFolderPath('MyDocuments')
        return @((Join-Path $documents 'PowerShell/Modules'), (Join-Path $documents 'WindowsPowerShell/Modules'))
    }
    $dataHome = $env:XDG_DATA_HOME
    if (-not $dataHome) { $dataHome = Join-Path $HOME '.local/share' }
    Join-Path $dataHome 'powershell/Modules'
}

function Get-ModuleVersion {
    [string](Import-PowerShellDataFile -Path $ManifestPath).ModuleVersion
}

function Invoke-Install {
    Invoke-Build
    $version = Get-ModuleVersion
    foreach ($root in @(Get-InstallRoot)) {
        $target = Join-Path (Join-Path $root 'PSGnuUtils') $version
        Write-Step "Install -> $target"
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        $null = New-Item -ItemType Directory -Force -Path $target
        Copy-Item -Path (Join-Path $OutputDir '*') -Destination $target -Recurse -Force
    }
    Write-Host "Installed PSGnuUtils $version. In a new session: Import-Module PSGnuUtils"
}

function Invoke-Uninstall {
    $version = Get-ModuleVersion
    foreach ($root in @(Get-InstallRoot)) {
        $moduleRoot = Join-Path $root 'PSGnuUtils'
        $target = Join-Path $moduleRoot $version
        if (-not (Test-Path -LiteralPath $target)) {
            Write-Host "PSGnuUtils $version is not installed in $root."
            continue
        }
        Write-Step "Uninstall $target"
        Remove-Item -LiteralPath $target -Recurse -Force
        if (@(Get-ChildItem -LiteralPath $moduleRoot -Force).Count -eq 0) { Remove-Item -LiteralPath $moduleRoot -Force }
    }
}

function Invoke-Publish {
    if (-not $NuGetApiKey) { throw 'Publish needs -NuGetApiKey or $env:PSGALLERY_API_KEY.' }
    Invoke-Build
    Write-Step "Publish to $Repository"
    Publish-Module -Path $OutputDir -NuGetApiKey $NuGetApiKey -Repository $Repository
}

# Switches run in a fixed, sensible order; without any task the default is Analyze + Test.
$selected = New-Object 'System.Collections.Generic.List[string]'
foreach ($name in @($Task)) { if ($name -and -not $selected.Contains($name)) { $selected.Add($name) } }
foreach ($name in @('Bootstrap', 'Clean', 'Manifest', 'Analyze', 'Test', 'Build', 'TestBuild', 'Install', 'Uninstall', 'Publish')) {
    if ($PSBoundParameters.ContainsKey($name) -and $PSBoundParameters[$name] -and -not $selected.Contains($name)) { $selected.Add($name) }
}
if ($selected.Count -eq 0) { $selected.AddRange([string[]]@('Analyze', 'Test')) }

foreach ($name in $selected) {
    switch ($name) {
        'Bootstrap' { Invoke-Bootstrap }
        'Manifest' { Invoke-Manifest }
        'Analyze' { Invoke-Analyze }
        'Test' { Invoke-Test -ModuleManifest $ManifestPath -TaskName 'Test' }
        'Build' { Invoke-Build }
        'TestBuild' { Invoke-Test -ModuleManifest (Join-Path $OutputDir 'PSGnuUtils.psd1') -TaskName 'TestBuild' }
        'Install' { Invoke-Install }
        'Uninstall' { Invoke-Uninstall }
        'Publish' { Invoke-Publish }
        'Clean' {
            Write-Step 'Clean'
            if (Test-Path -LiteralPath $OutputRoot) { Remove-Item -LiteralPath $OutputRoot -Recurse -Force }
        }
    }
}
