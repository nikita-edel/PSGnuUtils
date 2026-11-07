BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'Get-GnuUtil' {
    It 'lists every registered util with its command' {
        $utils = @(Get-GnuUtil)
        $utils.Count | Should -BeGreaterThan 30
        ($utils | Where-Object Name -EQ 'head').Command | Should -Be 'Invoke-GnuHead'
        $utils[0].PSObject.TypeNames | Should -Contain 'PSGnuUtils.UtilInfo'
    }

    It 'filters by name wildcard and category' {
        @(Get-GnuUtil -Name 'sha*sum').Count | Should -Be 5
        @(Get-GnuUtil -Category 'Checksums').Name | Should -Contain 'md5sum'
        @(Get-GnuUtil -Category 'Checksums').Name | Should -Not -Contain 'cat'
    }

    It 'accepts names from the pipeline' {
        @('cat', 'tac' | Get-GnuUtil).Name | Should -Be @('cat', 'tac')
    }

    It 'writes an error for unknown names' {
        $null = Get-GnuUtil -Name 'definitely-not-a-util' -ErrorVariable failures -ErrorAction SilentlyContinue
        "$failures" | Should -Match "no util named 'definitely-not-a-util'"
    }
}

Describe 'Enable-GnuUtil / Disable-GnuUtil' {
    AfterEach {
        Disable-GnuUtil -All
        Remove-Item -LiteralPath 'Alias:\tac' -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath 'Alias:\seq' -Force -ErrorAction SilentlyContinue
    }

    It 'creates a global alias for the GNU name' {
        Enable-GnuUtil -Name tac
        (Get-Alias -Name tac -Scope Global).Definition | Should -Be 'Invoke-GnuTac'
        (Get-GnuUtil -Name tac).Enabled | Should -BeTrue
        @(Get-GnuUtil -Enabled).Name | Should -Be @('tac')
    }

    It 'makes the GNU name run the implementation' {
        Enable-GnuUtil -Name tac
        $result = & ([scriptblock]::Create("'a', 'b' | tac"))
        $result | Should -Be @('b', 'a')
    }

    It 'removes the alias again on Disable-GnuUtil' {
        Enable-GnuUtil -Name tac
        Disable-GnuUtil -Name tac
        Get-Alias -Name tac -Scope Global -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        (Get-GnuUtil -Name tac).Enabled | Should -BeFalse
    }

    It 'overrides an existing alias and restores it with its options' {
        Set-Alias -Name seq -Value Get-Date -Scope Global -Option AllScope -Description 'user alias' -Force
        (Get-GnuUtil -Name seq).Shadows | Should -Be 'Alias -> Get-Date'

        Enable-GnuUtil -Name seq
        (Get-Alias -Name seq -Scope Global).Definition | Should -Be 'Invoke-GnuSeq'
        (Get-GnuUtil -Name seq).Shadows | Should -Be 'Alias -> Get-Date'

        Disable-GnuUtil -Name seq
        $restored = Get-Alias -Name seq -Scope Global
        $restored.Definition | Should -Be 'Get-Date'
        $restored.Description | Should -Be 'user alias'
        ($restored.Options -band [System.Management.Automation.ScopedItemOptions]::AllScope) | Should -Be ([System.Management.Automation.ScopedItemOptions]::AllScope)
    }

    It 'restores non-AllScope aliases' {
        Set-Alias -Name seq -Value Get-Date -Scope Global -Force
        Enable-GnuUtil -Name seq
        Disable-GnuUtil -Name seq
        (Get-Alias -Name seq -Scope Global).Definition | Should -Be 'Get-Date'
    }

    It 'skips existing commands with -NoClobber' {
        Set-Alias -Name seq -Value Get-Date -Scope Global -Force
        Enable-GnuUtil -Name seq -NoClobber
        (Get-Alias -Name seq -Scope Global).Definition | Should -Be 'Get-Date'
        (Get-GnuUtil -Name seq).Enabled | Should -BeFalse
    }

    It 'enables everything with -All and honors -Exclude' {
        Enable-GnuUtil -All -Exclude 'sha*', 'echo', 'pwd', 'sleep', 'tee', 'cat', 'mkdir', 'rmdir'
        $enabled = @(Get-GnuUtil -Enabled).Name
        $enabled | Should -Contain 'tac'
        $enabled | Should -Contain 'md5sum'
        $enabled | Should -Not -Contain 'sha256sum'
        $enabled | Should -Not -Contain 'cat'
    }

    It 'is idempotent' {
        Enable-GnuUtil -Name tac
        Enable-GnuUtil -Name tac
        Disable-GnuUtil -Name tac
        Get-Alias -Name tac -Scope Global -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'returns util info with -PassThru' {
        (Enable-GnuUtil -Name tac -PassThru).Enabled | Should -BeTrue
        (Disable-GnuUtil -Name tac -PassThru).Enabled | Should -BeFalse
    }

    It 'accepts Get-GnuUtil output from the pipeline' {
        Get-GnuUtil -Name tac | Enable-GnuUtil
        (Get-GnuUtil -Name tac).Enabled | Should -BeTrue
        Get-GnuUtil -Enabled | Disable-GnuUtil
        (Get-GnuUtil -Name tac).Enabled | Should -BeFalse
    }

    It 'writes an error for unknown names' {
        Enable-GnuUtil -Name 'not-a-util' -ErrorVariable failures -ErrorAction SilentlyContinue
        "$failures" | Should -Match "no util named 'not-a-util'"
    }
}

Describe 'Import-time configuration' {
    AfterEach {
        Disable-GnuUtil -All
        Remove-Item -LiteralPath 'Alias:\tac' -Force -ErrorAction SilentlyContinue
    }

    It 'enables utils by name' {
        InModuleScope PSGnuUtils { Invoke-GnuImportConfiguration -Configuration @{ Name = 'tac', 'seq' } }
        @(Get-GnuUtil -Enabled).Name | Should -Be @('seq', 'tac')
    }

    It 'enables all utils except excluded ones' {
        InModuleScope PSGnuUtils { Invoke-GnuImportConfiguration -Configuration @{ All = $true; Exclude = @('cat', 'echo', 'pwd', 'sleep', 'tee', 'mkdir', 'rmdir') } }
        @(Get-GnuUtil -Enabled).Name | Should -Contain 'tac'
        @(Get-GnuUtil -Enabled).Name | Should -Not -Contain 'cat'
    }

    It 'warns about unknown keys' {
        $warnings = InModuleScope PSGnuUtils { Invoke-GnuImportConfiguration -Configuration @{ Bogus = 1 } 3>&1 }
        "$warnings" | Should -Match "unknown import option 'Bogus'"
    }

    It 'works through Import-Module -ArgumentList and restores aliases on Remove-Module' {
        $manifest = (Get-Module PSGnuUtils).Path -replace '\.psm1$', '.psd1'
        $script = @"
Import-Module '$manifest' -ArgumentList @{ Name = 'tac' }
`$enabled = (Get-Alias -Name tac -Scope Global -ErrorAction SilentlyContinue).Definition
Remove-Module PSGnuUtils
`$after = Get-Alias -Name tac -Scope Global -ErrorAction SilentlyContinue
"`$enabled|`$(`$null -eq `$after)"
"@
        $powershell = (Get-Process -Id $PID).Path
        # -EncodedCommand: Windows PowerShell 5.1 does not escape embedded quotes for native arguments.
        $encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($script))
        $result = & $powershell -NoProfile -NonInteractive -EncodedCommand $encoded
        $result | Should -Be 'Invoke-GnuTac|True'
    }
}
