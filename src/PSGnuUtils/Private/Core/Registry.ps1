# Util registry.
#
# Every Utils/<name>.ps1 file calls Register-GnuUtil with a spec hashtable. The spec drives
# argument parsing (Arguments.ps1), --help output (Help.ps1), Get-GnuUtil and the module
# exports. Specs and option definitions are normalized here so that every key always exists;
# the module runs under Set-StrictMode -Version Latest, where reading a missing hashtable key
# with dot notation is an error.

$script:GnuUtilRegistry = @{}

# The built module keeps only each util's small Invoke-Gnu<Name> function in the psm1. The rest (spec and helpers) is
# Utils/<name>.ps1, loaded on the util's first call: name -> @{ File; Depends; Category; Synopsis; Loaded }.
# Empty when running from the source tree, where every file is loaded at import.
$script:GnuLazyUtils = @{}
$script:GnuLazyRoot = ''

# What Import-GnuUtil -MostUsed loads: the utils a new shell is likely to need right away.
$script:GnuMostUsedUtils = @('basename', 'cat', 'cp', 'cut', 'date', 'diff', 'dirname', 'echo', 'find', 'grep', 'head', 'ls', 'mkdir', 'mv', 'rm', 'sed', 'seq', 'sort', 'tail', 'tee', 'touch', 'tr', 'uniq', 'wc', 'xargs')

# Spec keys (see docs/ARCHITECTURE.md for the meaning of each one).
$script:GnuSpecDefaults = @{
    Options                = @()
    Description            = @()
    Notes                  = @()
    RawArguments           = $false   # do not parse options; only a sole --help / --version is recognized
    StopAtFirstOperand     = $false   # stop option parsing at the first operand (POSIX style)
    FileOperands           = $false   # operands are file names; expand wildcards like a Unix shell
    NumericOption          = $null    # short option letter that "-NUM" maps to (head -5 == head -n 5)
    NegativeNumberOperands = $false   # treat "-5" / "-.5" as operands instead of options (seq)
    UsageExitCode          = 1        # exit code for usage errors
    UsageHintHasName       = $false   # diffutils style: the "Try ..." hint starts with the util's name too
    OpenErrorFormat        = '{0}: {1}'   # message when an input file cannot be opened ({0}=name, {1}=reason)
    ReadErrorFormat        = '{0}: {1}'   # message when an input cannot be read (directories)
}

function ConvertTo-GnuOptionDefinition {
    <#
    .SYNOPSIS
    Normalizes one option definition of a util spec.
    .DESCRIPTION
    Keys:
      Short       single option letter (case-sensitive), e.g. 'n'
      Long        long option name without dashes, e.g. 'lines'
      Key         name under which the parsed value is stored (default: Long, else Short)
      Arg         argument placeholder for --help (e.g. 'NUM'); presence means the option takes a value
      OptionalArg the value is optional and can only be given as --long=VALUE
      Multi       collect every occurrence into a list instead of keeping the last value
      Prefix      text put before a Multi value (tells options apart that share a Key and an order, sed -e / -f)
      Value       constant stored under Key when the option is given (flags only)
      Sets        hashtable of additional Key = Value pairs set when the option is given
      Hidden      do not show the option in --help
      Help        description for --help
    #>
    param([Parameter(Mandatory)][hashtable]$Option)

    $definition = @{
        Short       = $null
        Long        = $null
        Key         = $null
        Arg         = $null
        OptionalArg = $false
        Multi       = $false
        Prefix      = ''
        Value       = $null
        HasValue    = $Option.ContainsKey('Value')
        Sets        = @{}
        Hidden      = $false
        Help        = ''
    }
    foreach ($entry in $Option.GetEnumerator()) { $definition[$entry.Key] = $entry.Value }

    if (-not $definition['Short'] -and -not $definition['Long']) {
        throw 'PSGnuUtils: an option definition needs a Short or a Long name.'
    }
    if (-not $definition['Key']) {
        if ($definition['Long']) { $definition['Key'] = $definition['Long'] } else { $definition['Key'] = $definition['Short'] }
    }
    $definition
}

function Get-GnuFunctionName {
    <#
    .SYNOPSIS
    Returns the PowerShell function name of a util: 'head' -> 'Invoke-GnuHead'.
    #>
    param([Parameter(Mandatory)][string]$Name)
    'Invoke-Gnu' + $Name.Substring(0, 1).ToUpperInvariant() + $Name.Substring(1)
}

function Register-GnuUtil {
    <#
    .SYNOPSIS
    Adds a util spec to the registry. Called once at load time by every Utils/<name>.ps1.
    #>
    param([Parameter(Mandatory)][hashtable]$Definition)

    foreach ($required in @('Name', 'Category', 'Synopsis', 'Usage')) {
        if (-not $Definition.ContainsKey($required) -or -not $Definition[$required]) {
            throw "PSGnuUtils: util definition is missing '$required'."
        }
    }

    $spec = @{}
    foreach ($entry in $script:GnuSpecDefaults.GetEnumerator()) { $spec[$entry.Key] = $entry.Value }
    foreach ($entry in $Definition.GetEnumerator()) { $spec[$entry.Key] = $entry.Value }

    $spec['Usage'] = @($spec['Usage'])
    $spec['Description'] = @($spec['Description'])
    $spec['Notes'] = @($spec['Notes'])
    $spec['Options'] = @(foreach ($option in @($spec['Options'])) { ConvertTo-GnuOptionDefinition -Option $option })
    $spec['FunctionName'] = Get-GnuFunctionName -Name $spec['Name']

    $script:GnuUtilRegistry[$spec['Name']] = $spec
}

function Get-GnuUtilSpec {
    <#
    .SYNOPSIS
    Returns the registered spec of a util (loading the util if needed), or nothing if the util does not exist.
    #>
    param([Parameter(Mandatory)][string]$Name)
    if (-not $script:GnuUtilRegistry.ContainsKey($Name)) { Import-GnuUtilBody -Name $Name }
    if ($script:GnuUtilRegistry.ContainsKey($Name)) { $script:GnuUtilRegistry[$Name] }
}

function Import-GnuUtilBody {
    <#
    .SYNOPSIS
    Loads a lazy util's spec and helpers into the module, first those of the utils it calls. Does nothing for loaded utils.
    #>
    param([Parameter(Mandatory)][string]$Name)

    if (-not $script:GnuLazyUtils.ContainsKey($Name)) { return }
    $entry = $script:GnuLazyUtils[$Name]
    if ($entry.Loaded) { return }
    $entry.Loaded = $true
    foreach ($dependency in $entry.Depends) { Import-GnuUtilBody -Name $dependency }
    # The build writes the helpers as script: functions, so that they outlive this function's scope.
    . ([System.IO.Path]::Combine($script:GnuLazyRoot, $entry.File))
}

function Get-GnuUtilNameList {
    <#
    .SYNOPSIS
    The names of all utils, loaded or not, sorted.
    #>
    @(@($script:GnuUtilRegistry.Keys) + @($script:GnuLazyUtils.Keys) | Sort-Object -Unique)
}

function Get-GnuUtilSummary {
    <#
    .SYNOPSIS
    @{ Category; Synopsis; FunctionName } of a util, without loading it.
    #>
    param([Parameter(Mandatory)][string]$Name)
    if ($script:GnuUtilRegistry.ContainsKey($Name)) {
        $spec = $script:GnuUtilRegistry[$Name]
        return @{ Category = $spec.Category; Synopsis = $spec.Synopsis; FunctionName = $spec.FunctionName }
    }
    $entry = $script:GnuLazyUtils[$Name]
    @{ Category = $entry.Category; Synopsis = $entry.Synopsis; FunctionName = (Get-GnuFunctionName -Name $Name) }
}

function Get-GnuStandardOption {
    <#
    .SYNOPSIS
    Returns the --help and --version option definitions every util understands.
    #>
    ConvertTo-GnuOptionDefinition -Option @{ Long = 'help'; Key = '__help'; Help = 'display this help and exit' }
    ConvertTo-GnuOptionDefinition -Option @{ Long = 'version'; Key = '__version'; Help = 'output version information and exit' }
}

function Resolve-GnuUtilName {
    <#
    .SYNOPSIS
    Expands util name patterns (wildcards allowed) to registered util names, minus exclusions.
    .DESCRIPTION
    Writes a non-terminating error for every literal (non-wildcard) name that is not registered.
    #>
    param(
        [string[]]$Name = @('*'),
        [AllowEmptyCollection()][string[]]$Exclude = @()
    )

    $all = @(Get-GnuUtilNameList)
    $selected = New-Object 'System.Collections.Generic.List[string]'
    foreach ($pattern in $Name) {
        $found = @($all | Where-Object { $_ -like $pattern })
        if ($found.Count -eq 0 -and -not [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($pattern)) {
            Write-Error -Message "PSGnuUtils: there is no util named '$pattern'. Run Get-GnuUtil to list the available utils." `
                -Category ObjectNotFound -ErrorId 'PSGnuUtils.UnknownUtil' -TargetObject $pattern
        }
        foreach ($item in $found) {
            if (-not $selected.Contains($item)) { $selected.Add($item) }
        }
    }

    foreach ($item in $selected) {
        $excluded = $false
        foreach ($pattern in $Exclude) {
            if ($item -like $pattern) { $excluded = $true; break }
        }
        if (-not $excluded) { $item }
    }
}
