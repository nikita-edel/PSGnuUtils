# Invocation context shared by all utils.
#
# Every util function follows the same shape (see docs/ARCHITECTURE.md):
#
#   function Invoke-GnuExample {
#       begin   { $ctx = Initialize-GnuUtil -Name 'example' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
#       process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
#       end     { if (-not $ctx.Done) { ...work... }; Complete-GnuUtil -Context $ctx }
#   }
#
# The context is a hashtable with these keys:
#   Name, Spec       util name and registered spec
#   Options          parsed options (see Set-GnuOptionValue); read them with Test-GnuOption / Get-GnuOptionValue
#   Operands         string[] of operands (wildcards already expanded for FileOperands utils)
#   ExitCode         becomes $LASTEXITCODE in Complete-GnuUtil
#   ErrorCount       number of errors written so far
#   Done             $true after --help/--version or a usage error; the util must not do any work
#   Output           lines (help/version text) emitted by Complete-GnuUtil
#   ExpectingInput   $true when the util is used in a pipeline (pipeline input acts as stdin)
#   Stdin, Pending, StdinConsumed   pipeline input buffers (see Input.ps1)

function Initialize-GnuUtil {
    <#
    .SYNOPSIS
    Parses the arguments of a util invocation and returns its context.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][AllowEmptyCollection()][object[]]$Arguments,
        [bool]$ExpectingInput
    )

    $spec = Get-GnuUtilSpec -Name $Name
    if ($null -eq $spec) { throw "PSGnuUtils: util '$Name' is not registered." }

    $context = @{
        Name           = $Name
        Spec           = $spec
        Options        = @{}
        Spellings      = @{}
        Operands       = [string[]]@()
        ExitCode       = 0
        ErrorCount     = 0
        Done           = $false
        Output         = New-Object 'System.Collections.Generic.List[string]'
        ExpectingInput = $ExpectingInput
        Stdin          = New-Object 'System.Collections.Generic.List[string]'
        Pending        = New-Object 'System.Collections.Generic.List[object]'
        StdinConsumed  = $false
    }

    $argv = [string[]]@(ConvertTo-GnuArgumentList -Arguments $Arguments -Spec $spec)

    if ($spec.RawArguments) {
        if ($argv.Length -eq 1 -and $argv[0] -eq '--help') { Set-GnuHelpOutput -Context $context }
        elseif ($argv.Length -eq 1 -and $argv[0] -eq '--version') { Set-GnuVersionOutput -Context $context }
        else { $context.Operands = $argv }
        return $context
    }

    $parsed = ConvertFrom-GnuArgument -Spec $spec -Arguments $argv
    if ($parsed.Error) {
        Write-GnuUsageError -Context $context -Message $parsed.Error
        return $context
    }
    if ($parsed.Options.ContainsKey('__help')) {
        Set-GnuHelpOutput -Context $context
        return $context
    }
    if ($parsed.Options.ContainsKey('__version')) {
        Set-GnuVersionOutput -Context $context
        return $context
    }

    $context.Options = $parsed.Options
    $context.Spellings = $parsed.Spellings
    $operands = [string[]]$parsed.Operands.ToArray()
    if ($spec.FileOperands) { $operands = [string[]]@(Expand-GnuWildcard -Operands $operands) }
    $context.Operands = $operands
    $context
}

function Complete-GnuUtil {
    <#
    .SYNOPSIS
    Emits pending help/version output and sets $LASTEXITCODE. Call at the end of every util.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    foreach ($line in $Context.Output) { $line }
    $Context.Output.Clear()
    $global:LASTEXITCODE = $Context.ExitCode
}

function Set-GnuHelpOutput {
    param([Parameter(Mandatory)][hashtable]$Context)
    foreach ($line in @(Get-GnuHelpText -Spec $Context.Spec)) { $Context.Output.Add($line) }
    $Context.Done = $true
}

function Set-GnuVersionOutput {
    param([Parameter(Mandatory)][hashtable]$Context)
    $Context.Output.Add("$($Context.Name) (PSGnuUtils) $(Get-GnuModuleVersion)")
    $Context.Output.Add('License GPLv3+: GNU GPL version 3 or later <https://gnu.org/licenses/gpl.html>.')
    $Context.Output.Add('This is free software: you are free to change and redistribute it.')
    $Context.Output.Add('There is NO WARRANTY, to the extent permitted by law.')
    $Context.Done = $true
}

function Get-GnuModuleVersion {
    <#
    .SYNOPSIS
    The module version from the manifest.
    .NOTES
    Read at call time: while the psm1 is still loading, the module's Version is 0.0.
    .PARAMETER Module
    The module info to read (default: this module).
    .PARAMETER ManifestPath
    Manifest used when the module has no version yet (default: the manifest of the source tree).
    #>
    param(
        [AllowNull()][object]$Module,
        [string]$ManifestPath
    )

    if (-not $PSBoundParameters.ContainsKey('Module')) { $Module = $ExecutionContext.SessionState.Module }
    if (-not $ManifestPath) { $ManifestPath = Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath 'PSGnuUtils.psd1' }
    if ($null -ne $Module -and $null -ne $Module.Version -and $Module.Version -ne [version]'0.0') { return $Module.Version.ToString() }
    if (Test-Path -LiteralPath $ManifestPath) { return [string](Import-PowerShellDataFile -Path $ManifestPath).ModuleVersion }
    '0.0.0'
}

function Test-GnuOption {
    <#
    .SYNOPSIS
    Returns $true if the option with the given key was specified.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$Key
    )
    $Context.Options.ContainsKey($Key)
}

function Get-GnuOptionValue {
    <#
    .SYNOPSIS
    Returns the value of an option, or Default when it was not specified.
    .NOTES
    Multi options are emitted item by item; wrap the call in @() to get an array.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$Key,
        [AllowNull()][object]$Default = $null
    )
    if ($Context.Options.ContainsKey($Key)) { return $Context.Options[$Key] }
    $Default
}

function Write-GnuError {
    <#
    .SYNOPSIS
    Writes a GNU style error ("util: message") as a non-terminating PowerShell error.
    .DESCRIPTION
    Errors go to the PowerShell error stream so 2>$null, 2>&1, -ErrorVariable on callers and
    $ErrorActionPreference behave as PowerShell users expect. The context exit code is raised
    to ExitCode (default 1).
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
        [int]$ExitCode = 1
    )

    $Context.ErrorCount++
    if ($ExitCode -gt $Context.ExitCode) { $Context.ExitCode = $ExitCode }
    Write-Error -Message "$($Context.Name): $Message" -Category NotSpecified `
        -ErrorId "PSGnuUtils.$($Context.Name)" -CategoryActivity $Context.Name
}

function Write-GnuUsageError {
    <#
    .SYNOPSIS
    Writes a usage error plus the "Try '<util> --help'" hint, sets the usage exit code and marks the context Done.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [AllowEmptyString()][string]$Message = ''
    )

    $hint = "Try '$($Context.Name) --help' for more information."
    $text = $hint
    if ($Message) { $text = "$Message`n$hint" }
    Write-GnuError -Context $Context -Message $text -ExitCode $Context.Spec.UsageExitCode
    $Context.Done = $true
}

function Write-GnuWarning {
    <#
    .SYNOPSIS
    Writes a GNU style warning ("util: message") to the PowerShell warning stream. Does not change the exit code.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$Message
    )
    Write-Warning -Message "$($Context.Name): $Message"
}

function Get-GnuErrorReason {
    <#
    .SYNOPSIS
    Converts a .NET exception into a GNU style reason such as 'No such file or directory'.
    #>
    param([Parameter(Mandatory)][System.Exception]$Exception)

    $current = $Exception
    while (($current -is [System.Management.Automation.MethodInvocationException] -or $current -is [System.Reflection.TargetInvocationException]) -and
        $null -ne $current.InnerException) {
        $current = $current.InnerException
    }
    if ($current -is [System.IO.FileNotFoundException] -or $current -is [System.IO.DirectoryNotFoundException]) {
        return 'No such file or directory'
    }
    if ($current -is [System.UnauthorizedAccessException]) { return 'Permission denied' }
    $current.Message
}
