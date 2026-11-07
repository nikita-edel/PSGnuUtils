# GNU name aliases.
#
# Each util is a normal PowerShell function (Invoke-GnuCat). Enabling a util creates a global
# alias with the GNU name (cat -> Invoke-GnuCat). Aliases have the highest command precedence
# (alias > function > cmdlet > native executable), so the GNU name wins over built-in aliases
# such as cat -> Get-Content, functions such as mkdir, and native tools such as sort.exe.
#
# Built-in aliases that get replaced are remembered and restored on Disable-GnuUtil or when the
# module is removed. Our aliases are always created with AllScope: Windows PowerShell's built-in
# aliases are AllScope (an AllScope flag cannot be removed again), and Remove-Item Alias:\x run
# from inside the module reliably removes AllScope aliases from the global scope.

$script:GnuEnabledUtils = @{}
$script:GnuAliasDescription = 'PSGnuUtils'

function Enable-GnuUtilAlias {
    <#
    .SYNOPSIS
    Creates the global GNU name alias for one util and remembers the alias it replaces.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$NoClobber
    )

    if ($script:GnuEnabledUtils.ContainsKey($Name)) { return }
    $spec = Get-GnuUtilSpec -Name $Name

    if ($NoClobber) {
        $other = Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $other) {
            Write-Verbose "PSGnuUtils: not enabling '$Name' because it already resolves to $($other.CommandType) '$($other.Name)'."
            return
        }
    }

    $saved = $null
    $existing = Get-Alias -Name $Name -Scope Global -ErrorAction SilentlyContinue
    if ($null -ne $existing -and [string]$existing.Description -ne $script:GnuAliasDescription) {
        $saved = @{
            Definition  = $existing.Definition
            Options     = $existing.Options
            Description = [string]$existing.Description
        }
    }

    try {
        Set-Alias -Name $Name -Value $spec.FunctionName -Scope Global -Force -ErrorAction Stop `
            -Option ([System.Management.Automation.ScopedItemOptions]::AllScope) -Description $script:GnuAliasDescription
        $script:GnuEnabledUtils[$Name] = $saved
    }
    catch {
        Write-Error -Message "PSGnuUtils: cannot enable '$Name': $($_.Exception.Message)" `
            -Category InvalidOperation -ErrorId 'PSGnuUtils.EnableFailed' -TargetObject $Name
    }
}

function Disable-GnuUtilAlias {
    <#
    .SYNOPSIS
    Removes the GNU name alias of one util and restores the alias it replaced, if any.
    #>
    param([Parameter(Mandatory)][string]$Name)

    if (-not $script:GnuEnabledUtils.ContainsKey($Name)) { return }
    $saved = $script:GnuEnabledUtils[$Name]

    try {
        Remove-Item -LiteralPath "Alias:\$Name" -Force -ErrorAction SilentlyContinue
        if ($null -ne $saved) {
            Set-Alias -Name $Name -Value $saved.Definition -Scope Global -Force -ErrorAction Stop `
                -Option $saved.Options -Description $saved.Description
        }
    }
    catch {
        Write-Error -Message "PSGnuUtils: cannot restore '$Name': $($_.Exception.Message)" `
            -Category InvalidOperation -ErrorId 'PSGnuUtils.DisableFailed' -TargetObject $Name
    }
    $script:GnuEnabledUtils.Remove($Name)
}

function Get-GnuShadowedCommand {
    <#
    .SYNOPSIS
    Describes what the GNU name resolves to without PSGnuUtils (e.g. 'Alias -> Get-Content').
    #>
    param([Parameter(Mandatory)][string]$Name)

    if ($script:GnuEnabledUtils.ContainsKey($Name)) {
        $saved = $script:GnuEnabledUtils[$Name]
        if ($null -ne $saved) { return "Alias -> $($saved.Definition)" }
    }

    $commands = @(Get-Command -Name $Name -All -ErrorAction SilentlyContinue | Where-Object {
            -not ($_.CommandType -eq 'Alias' -and [string]$_.Description -eq $script:GnuAliasDescription)
        })
    if ($commands.Count -eq 0) { return $null }

    $command = $commands[0]
    switch ([string]$command.CommandType) {
        'Alias' { return "Alias -> $($command.Definition)" }
        'Application' { return "Application -> $($command.Source)" }
        default { return "$($command.CommandType) -> $($command.Name)" }
    }
}
