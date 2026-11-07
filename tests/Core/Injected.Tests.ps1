# Code paths that depend on the OS, the runtime or chance, driven through mocks and explicit parameters.

BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'Platform detection' {
    It 'maps the OS probe result <Os> to <Expected>' -ForEach @(
        @{ Os = 'Windows'; Expected = 'Windows' }
        @{ Os = 'Linux'; Expected = 'Linux' }
        @{ Os = 'OSX'; Expected = 'MacOS' }
        @{ Os = 'FreeBSD'; Expected = 'Unix' }
    ) {
        if ($PSVersionTable.PSEdition -ne 'Core') { Set-ItResult -Skipped -Because 'Windows PowerShell is always Windows' }
        $global:PSGnuTestOs = $Os
        try {
            InModuleScope PSGnuUtils {
                $saved = $script:GnuPlatformCache
                try {
                    $script:GnuPlatformCache = $null
                    Mock Test-GnuOSPlatform { $Name -eq $global:PSGnuTestOs }
                    Get-GnuPlatform
                }
                finally { $script:GnuPlatformCache = $saved }
            } | Should -Be $Expected
        }
        finally { Remove-Variable -Name PSGnuTestOs -Scope Global }
    }

    It 'probes the real OS' {
        if ($PSVersionTable.PSEdition -ne 'Core') { Set-ItResult -Skipped -Because 'needs PowerShell 7' }
        InModuleScope PSGnuUtils { Test-GnuOSPlatform -Name 'Windows' } | Should -Be (Test-IsWindowsPlatform)
    }
}

Describe 'Runtime information' {
    It 'returns empty text for missing types and properties' {
        InModuleScope PSGnuUtils {
            Get-GnuRuntimeInformation -Property 'NoSuchProperty' | Should -BeExactly ''
            Get-GnuRuntimeInformation -Property 'OSDescription' -TypeName 'No.Such.Type' | Should -BeExactly ''
            Get-GnuRuntimeInformation -Property 'OSDescription' | Should -Not -BeNullOrEmpty
        }
    }

    It 'falls back to PROCESSOR_ARCHITECTURE when the runtime has no architecture' {
        $saved = $env:PROCESSOR_ARCHITECTURE
        $env:PROCESSOR_ARCHITECTURE = 'AMD64'
        try {
            InModuleScope PSGnuUtils {
                Mock Get-GnuRuntimeInformation { '' }
                Get-GnuMachineName -Platform 'Windows'
            } | Should -Be 'x86_64'
        }
        finally { $env:PROCESSOR_ARCHITECTURE = $saved }
    }

    It 'reads the OS description from the runtime when none is given' {
        InModuleScope PSGnuUtils {
            Mock Get-GnuRuntimeInformation { 'X64' }
            Mock Get-GnuRuntimeInformation { 'Linux 6.1.0 #1 SMP' } -ParameterFilter { $Property -eq 'OSDescription' }
            (Get-GnuOsInfo -Platform 'Linux').KernelRelease
        } | Should -Be '6.1.0'
    }
}

Describe 'Set-GnuUnixMode' {
    It 'does nothing on Windows' {
        InModuleScope PSGnuUtils {
            Mock Test-GnuWindows { $true }
            Set-GnuUnixMode -Path 'x' -Mode 384 | Should -BeFalse
        }
    }

    It 'reports runtimes without File.SetUnixFileMode' {
        InModuleScope PSGnuUtils {
            Mock Test-GnuWindows { $false }
            Mock Get-GnuUnixModeMethod { }
            Set-GnuUnixMode -Path 'x' -Mode 384 | Should -BeFalse
        }
    }

    It 'invokes the runtime method with the mode converted to its enum type' {
        $file = New-TestFile -Path (Join-Path $TestDrive 'mode.txt') -Content 'x'
        InModuleScope PSGnuUtils -Parameters @{ File = $file } {
            param($File)
            Mock Test-GnuWindows { $false }
            # Stand-in with the same shape (string, enum): File.SetAttributes(string, FileAttributes).
            Mock Get-GnuUnixModeMethod { [System.IO.File].GetMethod('SetAttributes', [type[]]@([string], [System.IO.FileAttributes])) }
            Set-GnuUnixMode -Path $File -Mode 128 | Should -BeTrue
        }
        (Get-Item -LiteralPath $file).Attributes | Should -Be ([System.IO.FileAttributes]::Normal)
    }

    It 'finds File.SetUnixFileMode only on .NET 7+' {
        $method = InModuleScope PSGnuUtils { Get-GnuUnixModeMethod }
        if ($PSVersionTable.PSVersion -ge [version]'7.3') { $method.Name | Should -Be 'SetUnixFileMode' }
        else { $method | Should -BeNullOrEmpty }
    }
}

Describe 'Module version' {
    It 'falls back to the manifest while the module has no version' {
        $manifest = Join-Path $TestRepoRoot 'src/PSGnuUtils/PSGnuUtils.psd1'
        $expected = [string](Import-PowerShellDataFile -Path $manifest).ModuleVersion
        InModuleScope PSGnuUtils -Parameters @{ M = $manifest } { param($M) Get-GnuModuleVersion -Module $null -ManifestPath $M } | Should -Be $expected
        InModuleScope PSGnuUtils { Get-GnuModuleVersion -Module ([pscustomobject]@{ Version = [version]'0.0' }) -ManifestPath 'no-such.psd1' } | Should -Be '0.0.0'
        InModuleScope PSGnuUtils { Get-GnuModuleVersion -Module $null } | Should -Be $expected
        InModuleScope PSGnuUtils { Get-GnuModuleVersion } | Should -Match '^\d+\.\d+\.\d+'
    }
}

Describe 'Path edge cases' {
    It 'joins paths that neither PowerShell nor .NET can parse' {
        $free = [char[]](68..90) | Where-Object { -not (Test-Path -LiteralPath "$($_):\") } | Select-Object -First 1
        $path = "a`0b"
        if ($free -and (Test-IsWindowsPlatform)) { $path = "$($free):\a`0b" }
        $result = InModuleScope PSGnuUtils -Parameters @{ P = $path } { param($P) Resolve-GnuPath -Path $P }
        $result.EndsWith("a`0b", [System.StringComparison]::Ordinal) | Should -BeTrue
    }

    It 'returns no parent for empty paths and invalid characters' {
        InModuleScope PSGnuUtils {
            Get-GnuParentPath -Path '' | Should -BeNullOrEmpty
            Get-GnuParentPath -Path "a`0b" | Should -BeNullOrEmpty
            Get-GnuParentPath -Path (Join-Path 'dir' 'file') | Should -Be 'dir'
        }
    }

    It 'resolves relative link targets' {
        $real = Join-Path $TestDrive 'relative-real'
        $null = New-Item -ItemType Directory -Path $real
        $link = Join-Path $TestDrive 'relative-link'
        InModuleScope PSGnuUtils -Parameters @{ Link = $link; Real = $real } {
            param($Link, $Real)
            # A fake symbolic link with a relative target (real ones need admin rights on Windows).
            Mock Get-GnuLinkTarget { }
            Mock Get-GnuLinkTarget { 'relative-real' } -ParameterFilter { $Path -eq $Link }
            Resolve-GnuPhysicalPath -Path $Link | Should -Be ([System.IO.Path]::GetFullPath($Real))
        }
    }
}

Describe 'mktemp collisions' {
    BeforeEach {
        $global:PSGnuTestNames = New-Object 'System.Collections.Generic.Queue[string]'
    }
    AfterEach {
        Remove-Variable -Name PSGnuTestNames -Scope Global -ErrorAction SilentlyContinue
    }

    It 'tries another name when a file exists' {
        $null = New-TestFile -Path (Join-Path $TestDrive 'cAAA') -Content 'taken'
        'AAA', 'BBB' | ForEach-Object { $global:PSGnuTestNames.Enqueue($_) }
        Push-Location -LiteralPath $TestDrive
        try {
            InModuleScope PSGnuUtils {
                Mock New-GnuRandomText { $global:PSGnuTestNames.Dequeue() }
                Invoke-GnuMktemp 'cXXX'
            } | Should -Be 'cBBB'
        }
        finally { Pop-Location }
        Test-Path -LiteralPath (Join-Path $TestDrive 'cBBB') | Should -BeTrue
    }

    It 'tries another name when a directory exists (-d and --dry-run)' {
        $null = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'dAAA')
        'AAA', 'BBB', 'AAA', 'CCC' | ForEach-Object { $global:PSGnuTestNames.Enqueue($_) }
        Push-Location -LiteralPath $TestDrive
        try {
            InModuleScope PSGnuUtils {
                Mock New-GnuRandomText { $global:PSGnuTestNames.Dequeue() }
                Invoke-GnuMktemp '-d' 'dXXX' | Should -Be 'dBBB'
                Invoke-GnuMktemp '-u' 'dXXX' | Should -Be 'dCCC'
            }
        }
        finally { Pop-Location }
    }

    It 'gives up after 100 taken names with "File exists"' {
        $null = New-TestFile -Path (Join-Path $TestDrive 'eAAA') -Content 'taken'
        Push-Location -LiteralPath $TestDrive
        try {
            $r = InModuleScope PSGnuUtils {
                Mock New-GnuRandomText { 'AAA' }
                Invoke-GnuMktemp 'eXXX' 2>&1
            }
        }
        finally { Pop-Location }
        "$r" | Should -Match "failed to create file via template 'eXXX': File exists"
    }

    It 'generates names from the portable alphabet' {
        $text = InModuleScope PSGnuUtils { New-GnuRandomText -Length 40 }
        $text | Should -Match '^[A-Za-z0-9]{40}$'
    }
}

Describe 'sleep infinity' {
    It 'sleeps in a loop until interrupted' {
        Mock -ModuleName PSGnuUtils Start-Sleep { throw 'interrupted' }
        { Invoke-GnuSleep 'inf' } | Should -Throw '*interrupted*'
        { Invoke-GnuSleep 'infinity', '1' } | Should -Throw '*interrupted*'
    }
}

Describe 'Get-GnuLinkTarget' {
    It 'returns nothing for ordinary directories and the target of junctions or symlinks' {
        $real = Join-Path $TestDrive 'target-real'
        $null = New-Item -ItemType Directory -Path $real
        InModuleScope PSGnuUtils -Parameters @{ P = $real } { param($P) Get-GnuLinkTarget -Path $P } | Should -BeNullOrEmpty
        $link = Join-Path $TestDrive 'target-link'
        if (-not (New-TestDirectoryLink -Path $link -Target $real)) { Set-ItResult -Skipped -Because 'directory links cannot be created here' }
        InModuleScope PSGnuUtils -Parameters @{ P = $link } { param($P) Get-GnuLinkTarget -Path $P } | Should -Match 'target-real$'
    }
}
