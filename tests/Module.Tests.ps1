# Meta tests: enforce the repository rules from docs/AGENTS.md / CONTRIBUTING.md for every util.
#   * the manifest is valid and exports exactly the public commands plus one function per util
#   * every util has a test file, and every option of the util is exercised in its tests
#   * every util has comment-based help (synopsis + example), --help and --version
#   * every util is listed in docs/UTILS.md
#   * all source and test files are ASCII (Windows PowerShell 5.1 reads BOM-less files as ANSI)

BeforeDiscovery {
    # Do not import the module during discovery: code run before the run phase is invisible to code coverage.
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $script:utilCases = @(
        Get-ChildItem -LiteralPath (Join-Path $repoRoot 'src/PSGnuUtils/Utils') -Filter '*.ps1' | ForEach-Object {
            $name = $_.BaseName
            @{ Name = $name; Command = 'Invoke-Gnu' + $name.Substring(0, 1).ToUpperInvariant() + $name.Substring(1) }
        }
    )
    $script:fileCases = @(
        Get-ChildItem -LiteralPath (Join-Path $repoRoot 'src'), (Join-Path $repoRoot 'tests'), (Join-Path $repoRoot 'tools') -Recurse -Include '*.ps1', '*.psm1', '*.psd1' |
            Where-Object { -not $_.PSIsContainer } |   # Windows PowerShell 5.1 also returns directories here
            ForEach-Object { @{ Path = $_.FullName; Name = $_.FullName.Substring($repoRoot.Length + 1) } }
    )
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:utilsDoc = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'docs/UTILS.md'))
}

Describe 'Module manifest' {
    It 'is valid' {
        { Test-ModuleManifest -Path $TestManifest -ErrorAction Stop } | Should -Not -Throw
    }

    It 'supports Windows PowerShell 5.1 and PowerShell 7 (Desktop and Core)' {
        $data = Import-PowerShellDataFile -Path (Join-Path $repoRoot 'src/PSGnuUtils/PSGnuUtils.psd1')
        $data.PowerShellVersion | Should -Be '5.1'
        $data.CompatiblePSEditions | Should -Be @('Desktop', 'Core')
    }

    It 'exports the public commands and one function per util, nothing else' {
        $data = Import-PowerShellDataFile -Path (Join-Path $repoRoot 'src/PSGnuUtils/PSGnuUtils.psd1')
        $expected = @('Disable-GnuUtil', 'Enable-GnuUtil', 'Get-GnuUtil') + @(Get-GnuUtil | ForEach-Object { $_.Command }) | Sort-Object
        @($data.FunctionsToExport | Sort-Object) | Should -Be $expected
        @((Get-Module PSGnuUtils).ExportedFunctions.Keys | Sort-Object) | Should -Be $expected
        @((Get-Module PSGnuUtils).ExportedAliases.Keys).Count | Should -Be 0
    }

    It 'has one Utils file per registered util' {
        $files = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'src/PSGnuUtils/Utils') -Filter '*.ps1' | ForEach-Object { $_.BaseName } | Sort-Object)
        $files | Should -Be @(Get-GnuUtil | ForEach-Object { $_.Name } | Sort-Object)
    }
}

Describe 'Util <Name>' -ForEach $utilCases {
    BeforeAll {
        $testFile = Join-Path $repoRoot "tests/Utils/$Name.Tests.ps1"
        $script:testText = ''
        if (Test-Path -LiteralPath $testFile) {
            $script:testText = [System.IO.File]::ReadAllText($testFile)
            foreach ($suite in [regex]::Matches($testText, "'([A-Za-z]+\.Suite\.ps1)'")) {
                $testText += [System.IO.File]::ReadAllText((Join-Path $repoRoot "tests/Utils/$($suite.Groups[1].Value)"))
            }
        }
    }

    It 'is defined by its own Utils file (no helper function with the same name)' {
        $file = (Get-Command -Name $Command -Module PSGnuUtils).ScriptBlock.File
        # The built module merges every file into one psm1, so only the definition can tell there.
        if ($file -and [System.IO.Path]::GetFileName($file) -ne 'PSGnuUtils.psm1') { [System.IO.Path]::GetFileName($file) | Should -Be "$Name.ps1" }
        else { (Get-Command -Name $Command -Module PSGnuUtils).Definition | Should -Match "Initialize-GnuUtil -Name '$Name'" }
    }

    It 'has a test file' {
        Test-Path -LiteralPath (Join-Path $repoRoot "tests/Utils/$Name.Tests.ps1") | Should -BeTrue
    }

    It 'exercises every option in its tests' {
        $spec = InModuleScope PSGnuUtils -Parameters @{ N = $Name } { param($N) Get-GnuUtilSpec -Name $N }
        $missing = foreach ($option in $spec.Options) {
            $covered = $false
            if ($option.Long -and $testText.Contains("--$($option.Long)")) { $covered = $true }
            if ($option.Short -and ($testText.Contains("'-$($option.Short)'") -or $testText -cmatch "'-[A-Za-z0-9]*$([regex]::Escape($option.Short))[A-Za-z0-9]*'")) { $covered = $true }
            if (-not $covered) { if ($option.Long) { "--$($option.Long)" } else { "-$($option.Short)" } }
        }
        @($missing) | Should -BeNullOrEmpty -Because "every option of '$Name' needs a test"
    }

    It 'has comment-based help with a synopsis and an example' {
        $help = Get-Help -Name $Command -Full
        $help.Synopsis | Should -Match 'GNU'
        @($help.Examples.Example).Count | Should -BeGreaterThan 0
    }

    It 'supports --help and --version' {
        $help = Invoke-TestGnu $Name '--help'
        $help.Output[0] | Should -Match "^Usage: $([regex]::Escape($Name))"
        $help.Text | Should -Match '--help'
        $version = Invoke-TestGnu $Name '--version'
        $version.Output[0] | Should -Match "^$([regex]::Escape($Name)) \(PSGnuUtils\)"
    }

    It 'is listed in docs/UTILS.md' {
        $utilsDoc | Should -Match ("\|\s*``$([regex]::Escape($Name))``\s*\|")
    }
}

Describe 'Source file <Name>' -ForEach $fileCases {
    It 'is ASCII only' {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}
