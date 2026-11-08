BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')

    function New-LazyUtil {
        # A util that only exists as a lazy file, like every util of the built module before its first call.
        param([string]$Name, [string[]]$Depends = @())
        $file = Join-Path $TestDrive "$Name.ps1"
        $null = New-TestFile -Path $file -Content @"
Register-GnuUtil @{ Name = '$Name'; Category = 'Lazy'; Synopsis = 'Synopsis of $Name.'; Usage = @('$Name') }
function script:Get-Lazy${Name}Helper { 'helper of $Name' }
`$script:Lazy${Name}Value = 'value of $Name'
"@
        InModuleScope PSGnuUtils -Parameters @{ N = $Name; F = $file; D = $Depends } {
            param($N, $F, $D)
            $script:GnuLazyUtils[$N] = @{ File = $F; Depends = $D; Category = 'Lazy'; Synopsis = "Synopsis of $N."; Loaded = $false }
        }
    }

    function Remove-LazyUtil {
        param([string[]]$Name)
        InModuleScope PSGnuUtils -Parameters @{ N = $Name } {
            param($N)
            foreach ($item in $N) {
                $script:GnuLazyUtils.Remove($item)
                $script:GnuUtilRegistry.Remove($item)
                Remove-Item -Path "Function:\script:Get-Lazy${item}Helper" -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Lazy loading' {
    AfterEach { Remove-LazyUtil -Name 'zlazy', 'zdep', 'zloop' }

    It 'loads a util on first use, into the module scope' {
        New-LazyUtil -Name 'zlazy'
        InModuleScope PSGnuUtils {
            $script:GnuUtilRegistry.ContainsKey('zlazy') | Should -BeFalse
            (Get-GnuUtilSpec -Name 'zlazy').Synopsis | Should -Be 'Synopsis of zlazy.'
            Get-LazyzlazyHelper | Should -Be 'helper of zlazy'
            $script:LazyzlazyValue | Should -Be 'value of zlazy'
            $script:GnuLazyUtils['zlazy'].Loaded | Should -BeTrue
        }
    }

    It 'loads a util only once' {
        New-LazyUtil -Name 'zlazy'
        InModuleScope PSGnuUtils {
            Import-GnuUtilBody -Name 'zlazy'
            $script:GnuUtilRegistry.Remove('zlazy')
            Import-GnuUtilBody -Name 'zlazy'
            $script:GnuUtilRegistry.ContainsKey('zlazy') | Should -BeFalse -Because 'a loaded util is not read again'
        }
    }

    It 'loads the utils a util depends on, also when they depend on each other' {
        New-LazyUtil -Name 'zlazy' -Depends 'zdep'
        New-LazyUtil -Name 'zdep' -Depends 'zlazy'
        InModuleScope PSGnuUtils {
            Import-GnuUtilBody -Name 'zlazy'
            Get-LazyzdepHelper | Should -Be 'helper of zdep'
            Get-LazyzlazyHelper | Should -Be 'helper of zlazy'
        }
    }

    It 'lists lazy utils without loading them' {
        New-LazyUtil -Name 'zlazy'
        $info = Get-GnuUtil -Name 'zlazy'
        $info.Category | Should -Be 'Lazy'
        $info.Synopsis | Should -Be 'Synopsis of zlazy.'
        $info.Command | Should -Be 'Invoke-GnuZlazy'
        InModuleScope PSGnuUtils { $script:GnuUtilRegistry.ContainsKey('zlazy') | Should -BeFalse }
    }

    It 'ignores unknown utils' {
        InModuleScope PSGnuUtils { Get-GnuUtilSpec -Name 'nosuchutil' | Should -BeNullOrEmpty }
    }
}

Describe 'Import-GnuUtil' {
    AfterEach { Remove-LazyUtil -Name 'zlazy', 'zdep' }

    It 'loads utils by name and wildcard' {
        New-LazyUtil -Name 'zlazy'
        New-LazyUtil -Name 'zdep'
        Import-GnuUtil -Name 'zla*'
        InModuleScope PSGnuUtils {
            $script:GnuUtilRegistry.ContainsKey('zlazy') | Should -BeTrue
            $script:GnuUtilRegistry.ContainsKey('zdep') | Should -BeFalse
        }
        Import-GnuUtil 'zdep'
        InModuleScope PSGnuUtils { $script:GnuUtilRegistry.ContainsKey('zdep') | Should -BeTrue }
    }

    It 'loads everything with -All' {
        New-LazyUtil -Name 'zlazy'
        Import-GnuUtil -All
        InModuleScope PSGnuUtils { $script:GnuUtilRegistry.ContainsKey('zlazy') | Should -BeTrue }
    }

    It 'loads the most used utils with -MostUsed, which are all real utils or planned ones' {
        New-LazyUtil -Name 'zlazy'
        InModuleScope PSGnuUtils { $script:GnuMostUsedUtils += 'zlazy' }
        try {
            Import-GnuUtil -MostUsed
            InModuleScope PSGnuUtils {
                $script:GnuUtilRegistry.ContainsKey('zlazy') | Should -BeTrue
                $script:GnuUtilRegistry.ContainsKey('ls') | Should -BeTrue
            }
        }
        finally { InModuleScope PSGnuUtils { $script:GnuMostUsedUtils = @($script:GnuMostUsedUtils | Where-Object { $_ -ne 'zlazy' }) } }
    }

    It 'reports names that do not exist' {
        { Import-GnuUtil -Name 'nosuchutil' -ErrorAction Stop } | Should -Throw
    }
}

Describe 'Disable-GnuLazyLoading' {
    AfterEach { Remove-LazyUtil -Name 'zlazy' }

    It 'loads every util' {
        New-LazyUtil -Name 'zlazy'
        Disable-GnuLazyLoading
        InModuleScope PSGnuUtils { $script:GnuUtilRegistry.ContainsKey('zlazy') | Should -BeTrue }
    }
}
