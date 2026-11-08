<#
.SYNOPSIS
    Stages the module in out/<Name>/<Version> and returns its name, version and path.

.DESCRIPTION
    The module is the one folder in src/, which holds <Name>.psd1. Install, Package and Publish all work
    from this staged copy, which also carries LICENSE, README.md and CHANGELOG.txt.

    The staged module is a manifest, one psm1 with the core, the entry function of every util and an index, and
    Utils/<name>.ps1 with the rest of each util, which loads on first use.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot

$sources = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'src') -Directory)
if ($sources.Count -ne 1) { throw "Expected exactly one module folder in src/, found $($sources.Count)." }
$source = $sources[0]
$moduleName = $source.Name
$sourceManifest = Join-Path $source.FullName "$moduleName.psd1"
if (-not (Test-Path -LiteralPath $sourceManifest)) { throw "Missing manifest: $sourceManifest" }

function Get-UtilSummary {
    # Category and synopsis of every util, from the source module in a runspace of its own: some specs are built by code.
    $shell = [powershell]::Create()
    try {
        $null = $shell.AddScript({ param($Manifest) Import-Module -Name $Manifest -ErrorAction Stop; Get-GnuUtil }).AddArgument($sourceManifest)
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

function Split-UtilForLazyLoading([string]$Target, [System.Text.Encoding]$Encoding) {
    # Writes each util without its entry function to <Target>/Utils and returns the psm1 text: the entry functions
    # plus the index the module needs to list utils and to load them on first use.
    $utilsOut = Join-Path $Target 'Utils'
    $null = New-Item -ItemType Directory -Force -Path $utilsOut
    $parsed = @{}
    $owners = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $source.FullName 'Utils') -Filter '*.ps1' | Sort-Object -Property Name)) {
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

& (Join-Path $PSScriptRoot 'manifest.ps1')
$version = [string](Import-PowerShellDataFile -Path $sourceManifest).ModuleVersion

$moduleRoot = Join-Path (Join-Path $repoRoot 'out') $moduleName
$target = Join-Path $moduleRoot $version
if (Test-Path -LiteralPath $moduleRoot) { Remove-Item -LiteralPath $moduleRoot -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path $target

# UTF-8 with BOM so Windows PowerShell 5.1 never misreads the files.
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$builder = New-Object System.Text.StringBuilder
foreach ($folder in @('Private', 'Public')) {
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $source.FullName $folder) -Filter '*.ps1' -Recurse | Sort-Object -Property FullName)) {
        $relative = $file.FullName.Substring($source.FullName.Length + 1).Replace('\', '/')
        [void]$builder.AppendLine("#region $relative")
        [void]$builder.AppendLine([System.IO.File]::ReadAllText($file.FullName).TrimEnd())
        [void]$builder.AppendLine("#endregion $relative")
        [void]$builder.AppendLine()
    }
}
[void]$builder.AppendLine((Split-UtilForLazyLoading -Target $target -Encoding $utf8Bom))
$merged = $builder.ToString()
$rootModule = [System.IO.File]::ReadAllText((Join-Path $source.FullName "$moduleName.psm1"))
$rootModule = [regex]::Replace($rootModule, '(?s)#region Loader.*?#endregion Loader', [System.Text.RegularExpressions.MatchEvaluator] { $merged.TrimEnd() })

[System.IO.File]::WriteAllText((Join-Path $target "$moduleName.psm1"), $rootModule, $utf8Bom)
Copy-Item -LiteralPath $sourceManifest -Destination $target
foreach ($extra in @('LICENSE', 'README.md', 'CHANGELOG.txt')) {
    Copy-Item -LiteralPath (Join-Path $repoRoot $extra) -Destination $target
}

$null = Test-ModuleManifest -Path (Join-Path $target "$moduleName.psd1")
Write-Host "Built $target"

[pscustomobject]@{
    Name    = $moduleName
    Version = $version
    Path    = $target
}
