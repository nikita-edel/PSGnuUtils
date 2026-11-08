Register-GnuUtil @{
    Name               = 'env'
    Category           = 'Running commands'
    Synopsis           = 'Run a program in a modified environment.'
    Usage              = @('env [OPTION]... [-] [NAME=VALUE]... [COMMAND [ARG]...]')
    Description        = @('Set each NAME to VALUE in the environment and run COMMAND.')
    StopAtFirstOperand = $true
    UsageExitCode      = 125
    Options            = @(
        @{ Short = 'i'; Long = 'ignore-environment'; Help = 'start with an empty environment' }
        @{ Short = '0'; Long = 'null'; Help = 'end each output line with NUL, not newline' }
        @{ Short = 'u'; Long = 'unset'; Arg = 'NAME'; Multi = $true; Help = 'remove variable from the environment' }
        @{ Short = 'C'; Long = 'chdir'; Arg = 'DIR'; Help = 'change working directory to DIR' }
        @{ Short = 'S'; Long = 'split-string'; Arg = 'S'; Help = 'process and split S into separate arguments; used to pass multiple arguments on shebang lines' }
    )
    Notes              = @(
        'A mere - implies -i.  If no COMMAND, print the resulting environment.',
        '',
        'Exit status: 125 if env itself fails, 126 if COMMAND is found but cannot be invoked,',
        '127 if COMMAND cannot be found, the exit status of COMMAND otherwise.',
        '',
        'PowerShell note: COMMAND may be a PowerShell command too; it runs in this session with',
        'the modified environment, which is restored afterwards. The environment is printed',
        'sorted by name. Arguments reach native programs as PowerShell passes them (Windows',
        'PowerShell 5.1 does not escape embedded double quotes).'
    )
}

function Invoke-GnuEnv {
    <#
    .SYNOPSIS
    GNU env: print the environment, or run a command in a modified environment.

    .DESCRIPTION
    Without COMMAND prints NAME=VALUE for every environment variable. Otherwise sets each
    NAME=VALUE (after -i clears everything and -u removes names), runs COMMAND (in DIR with -C)
    and restores the environment. -S splits a string into arguments like GNU env.
    Enable the GNU name with: Enable-GnuUtil env

    .EXAMPLE
    Invoke-GnuEnv DEBUG=1 node app.js

    .EXAMPLE
    Invoke-GnuEnv -i PATH=$env:PATH cmd /c set
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'env' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuEnvCommand -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function Split-GnuEnvString {
    <#
    .SYNOPSIS
    Splits an env -S string into arguments (quotes, backslash escapes, ${VAR}, # comments). Returns @{ Arguments } or @{ Error }.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $arguments = New-Object 'System.Collections.Generic.List[string]'
    $current = New-Object System.Text.StringBuilder
    $inWord = $false
    $quote = $null
    $i = 0
    while ($i -lt $Text.Length) {
        $char = $Text[$i]
        if ($null -eq $quote -and ($char -eq ' ' -or $char -eq "`t")) {
            if ($inWord) { $arguments.Add($current.ToString()); [void]$current.Clear(); $inWord = $false }
            $i++
            continue
        }
        if ($null -eq $quote -and $char -eq '#' -and -not $inWord) { break }
        if ($char -eq "'" -and $quote -ne '"') {
            if ($null -eq $quote) { $quote = "'" } else { $quote = $null }
            $inWord = $true
            $i++
            continue
        }
        if ($char -eq '"' -and $quote -ne "'") {
            if ($null -eq $quote) { $quote = '"' } else { $quote = $null }
            $inWord = $true
            $i++
            continue
        }
        if ($char -eq '\' -and $quote -ne "'" -and $i + 1 -lt $Text.Length) {
            $next = [string]$Text[$i + 1]
            $i += 2
            switch -CaseSensitive ($next) {
                'c' { if ($inWord) { $arguments.Add($current.ToString()) }; return @{ Arguments = $arguments.ToArray() } }
                '_' { if ($null -eq $quote) { if ($inWord) { $arguments.Add($current.ToString()); [void]$current.Clear(); $inWord = $false } } else { [void]$current.Append(' '); $inWord = $true } }
                'n' { [void]$current.Append("`n"); $inWord = $true }
                't' { [void]$current.Append("`t"); $inWord = $true }
                'r' { [void]$current.Append("`r"); $inWord = $true }
                'f' { [void]$current.Append([char]12); $inWord = $true }
                'v' { [void]$current.Append([char]11); $inWord = $true }
                { '\', '"', "'", '$', '#', ' ' -ccontains $_ } { [void]$current.Append($next); $inWord = $true }
                default { return @{ Error = "invalid sequence '\$next' in -S" } }
            }
            continue
        }
        if ($char -eq '$' -and $quote -ne "'") {
            $match = [regex]::Match($Text.Substring($i), '^\$\{([A-Za-z_][A-Za-z0-9_]*)\}')
            if (-not $match.Success) { return @{ Error = "only `${VARNAME} expansion is supported, error at: $($Text.Substring($i))" } }
            [void]$current.Append([System.Environment]::GetEnvironmentVariable($match.Groups[1].Value))
            $inWord = $true
            $i += $match.Length
            continue
        }
        [void]$current.Append($char)
        $inWord = $true
        $i++
    }
    if ($null -ne $quote) { return @{ Error = "no terminating quote in -S string" } }
    if ($inWord) { $arguments.Add($current.ToString()) }
    @{ Arguments = $arguments.ToArray() }
}

function Invoke-GnuEnvCommand {
    <#
    .SYNOPSIS
    Implementation of env.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $operands = New-Object 'System.Collections.Generic.List[string]'
    if (Test-GnuOption -Context $Context -Key 'split-string') {
        $split = Split-GnuEnvString -Text ([string](Get-GnuOptionValue -Context $Context -Key 'split-string'))
        if ($split.ContainsKey('Error')) { Write-GnuError -Context $Context -Message $split.Error -ExitCode 125; return }
        foreach ($item in $split.Arguments) { $operands.Add($item) }
    }
    foreach ($item in @($Context.Operands)) { $operands.Add($item) }

    $ignore = Test-GnuOption -Context $Context -Key 'ignore-environment'
    if ($operands.Count -gt 0 -and $operands[0] -ceq '-') { $ignore = $true; $operands.RemoveAt(0) }
    $assignments = New-Object 'System.Collections.Generic.List[string]'
    while ($operands.Count -gt 0 -and $operands[0].IndexOf('=') -gt 0) { $assignments.Add($operands[0]); $operands.RemoveAt(0) }
    $unset = @(Get-GnuOptionValue -Context $Context -Key 'unset' -Default @())
    foreach ($name in $unset) {
        if ([string]::IsNullOrEmpty($name) -or $name.Contains('=')) { Write-GnuError -Context $Context -Message "cannot unset '$name': Invalid argument" -ExitCode 125; return }
    }
    $zero = Test-GnuOption -Context $Context -Key 'null'
    $hasDirectory = Test-GnuOption -Context $Context -Key 'chdir'
    if ($operands.Count -gt 0 -and $zero) { Write-GnuUsageError -Context $Context -Message 'cannot specify --null (-0) with command'; return }
    if ($operands.Count -eq 0 -and $hasDirectory) { Write-GnuUsageError -Context $Context -Message 'must specify command with --chdir (-C)'; return }

    $command = $null
    if ($operands.Count -gt 0) {
        # Resolve before the environment changes: -i would remove PATH.
        $command = Resolve-GnuChildCommand -Context $Context -Name $operands[0]
        if ($null -eq $command) { return }
    }

    $saved = [System.Environment]::GetEnvironmentVariables()
    $pushed = $false
    try {
        if ($ignore) { foreach ($name in @($saved.Keys)) { [System.Environment]::SetEnvironmentVariable([string]$name, [NullString]::Value) } }
        foreach ($name in $unset) { [System.Environment]::SetEnvironmentVariable($name, [NullString]::Value) }
        foreach ($assignment in $assignments) {
            $index = $assignment.IndexOf('=')
            # An empty VALUE creates an empty variable on .NET 9+ and removes it on older runtimes.
            [System.Environment]::SetEnvironmentVariable($assignment.Substring(0, $index), $assignment.Substring($index + 1))
        }

        if ($null -eq $command) {
            # Print our own view: .NET Framework misreads a nearly empty environment block after -i.
            $variables = @{}
            if (-not $ignore) { foreach ($name in @($saved.Keys)) { $variables[[string]$name] = [string]$saved[$name] } }
            foreach ($name in $unset) { $variables.Remove($name) }
            foreach ($assignment in $assignments) {
                $index = $assignment.IndexOf('=')
                $variables[$assignment.Substring(0, $index)] = $assignment.Substring($index + 1)
            }
            $names = New-Object 'System.Collections.Generic.List[string]'
            foreach ($name in $variables.Keys) { $names.Add([string]$name) }
            $names.Sort([System.StringComparer]::Ordinal)
            ConvertTo-GnuRecordOutput -Record @(foreach ($name in $names) { "$name=$($variables[$name])" }) -Zero:$zero
            return
        }
        if ($hasDirectory) {
            $directory = [string](Get-GnuOptionValue -Context $Context -Key 'chdir')
            try { Push-Location -LiteralPath $directory -ErrorAction Stop; $pushed = $true }
            catch { Write-GnuError -Context $Context -Message "cannot change directory to '$directory': No such file or directory" -ExitCode 125; return }
        }
        $arguments = @()
        if ($operands.Count -gt 1) { $arguments = $operands.GetRange(1, $operands.Count - 1).ToArray() }
        $inputLines = $null
        if ($Context.ExpectingInput) { $inputLines = @(Read-GnuStdinLine -Context $Context) }
        Invoke-GnuChildCommand -Context $Context -Command $command -Arguments $arguments -InputObject $inputLines
    }
    finally {
        if ($pushed) { Pop-Location }
        $now = [System.Environment]::GetEnvironmentVariables()
        foreach ($name in @($now.Keys)) { if (-not $saved.Contains($name)) { [System.Environment]::SetEnvironmentVariable([string]$name, [NullString]::Value) } }
        foreach ($name in @($saved.Keys)) { [System.Environment]::SetEnvironmentVariable([string]$name, [string]$saved[$name]) }
    }
}
