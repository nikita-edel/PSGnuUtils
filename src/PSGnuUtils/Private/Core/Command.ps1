# Running child commands (env, nice, nohup, timeout) and signals (kill, timeout).

# Linux signal numbers and strsignal() descriptions (kill -l / -t, timeout -s).
$script:GnuSignals = [ordered]@{
    HUP = @(1, 'Hangup'); INT = @(2, 'Interrupt'); QUIT = @(3, 'Quit'); ILL = @(4, 'Illegal instruction')
    TRAP = @(5, 'Trace/breakpoint trap'); ABRT = @(6, 'Aborted'); BUS = @(7, 'Bus error'); FPE = @(8, 'Floating point exception')
    KILL = @(9, 'Killed'); USR1 = @(10, 'User defined signal 1'); SEGV = @(11, 'Segmentation fault'); USR2 = @(12, 'User defined signal 2')
    PIPE = @(13, 'Broken pipe'); ALRM = @(14, 'Alarm clock'); TERM = @(15, 'Terminated'); STKFLT = @(16, 'Stack fault')
    CHLD = @(17, 'Child exited'); CONT = @(18, 'Continued'); STOP = @(19, 'Stopped (signal)'); TSTP = @(20, 'Stopped')
    TTIN = @(21, 'Stopped (tty input)'); TTOU = @(22, 'Stopped (tty output)'); URG = @(23, 'Urgent I/O condition')
    XCPU = @(24, 'CPU time limit exceeded'); XFSZ = @(25, 'File size limit exceeded'); VTALRM = @(26, 'Virtual timer expired')
    PROF = @(27, 'Profiling timer expired'); WINCH = @(28, 'Window changed'); POLL = @(29, 'I/O possible')
    PWR = @(30, 'Power failure'); SYS = @(31, 'Bad system call')
}

function ConvertFrom-GnuSignal {
    <#
    .SYNOPSIS
    A signal name or number (TERM, SIGTERM, 15; 0 = existence check) as @{ Name; Number }, or $null.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    if ($Text -match '^\d+$') {
        $number = [int]$Text
        if ($number -eq 0) { return @{ Name = '0'; Number = 0 } }
        foreach ($entry in $script:GnuSignals.GetEnumerator()) {
            if ($entry.Value[0] -eq $number) { return @{ Name = $entry.Key; Number = $number } }
        }
        return $null
    }
    $name = $Text.ToUpperInvariant()
    if ($name.StartsWith('SIG', [System.StringComparison]::Ordinal)) { $name = $name.Substring(3) }
    if ($name -eq 'IO') { $name = 'POLL' }
    if ($name -eq 'CLD') { $name = 'CHLD' }
    if ($script:GnuSignals.Contains($name)) { return @{ Name = $name; Number = $script:GnuSignals[$name][0] } }
    $null
}

function Send-GnuSignal {
    <#
    .SYNOPSIS
    Sends a signal to a process. Windows (and KILL everywhere) terminates the process; Unix uses kill(1) for others.
    .OUTPUTS
    $null on success, else the reason ('No such process', 'Operation not permitted', ...).
    #>
    param([Parameter(Mandatory)][int]$Id, [Parameter(Mandatory)][hashtable]$Signal)

    $process = Get-Process -Id $Id -ErrorAction SilentlyContinue
    if ($null -eq $process) { return 'No such process' }
    if ($Signal.Number -eq 0) { return $null }
    try {
        if ((Test-GnuWindows) -or $Signal.Name -eq 'KILL') {
            Stop-GnuProcess -Process $process
            return $null
        }
        $native = Start-Process -FilePath 'kill' -ArgumentList @('-s', $Signal.Name, [string]$Id) -NoNewWindow -Wait -PassThru
        if ($native.ExitCode -ne 0) { return 'Operation not permitted' }
        $null
    }
    catch {
        Get-GnuErrorReason -Exception $_.Exception
    }
}

function Stop-GnuProcess {
    <#
    .SYNOPSIS
    Kills a process and, where .NET supports it (Core 3+), its child processes.
    #>
    param([Parameter(Mandatory)][System.Diagnostics.Process]$Process, [switch]$NoTree)
    $treeKill = $null
    if (-not $NoTree) { $treeKill = $Process.GetType().GetMethod('Kill', [type[]]@([bool])) }
    if ($null -ne $treeKill) { [void]$treeKill.Invoke($Process, @($true)) }
    else { $Process.Kill() }
}

function Resolve-GnuChildCommand {
    <#
    .SYNOPSIS
    The command to run for env / nice / nohup / timeout, or $null after reporting it (exit code 127).
    .PARAMETER Format
    Message format for a missing command; {0} is the name.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$Name,
        [string]$Format = "'{0}': No such file or directory"
    )
    $command = Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) {
        Write-GnuError -Context $Context -Message ($Format -f $Name) -ExitCode 127
        return $null
    }
    $command
}

function Invoke-GnuChildCommand {
    <#
    .SYNOPSIS
    Runs a command (native program or PowerShell command), streaming its output; sets the context's exit code.
    .PARAMETER InputObject
    Lines passed to the command's input (the util's pipeline input).
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][System.Management.Automation.CommandInfo]$Command,
        [AllowEmptyCollection()][string[]]$Arguments = @(),
        [AllowNull()][object[]]$InputObject
    )

    $global:LASTEXITCODE = 0
    $failed = $false
    try {
        if ($Command.CommandType -eq 'Application') {
            if ($null -ne $InputObject) { $InputObject | & $Command @Arguments }
            else { & $Command @Arguments }
        }
        else {
            # Splatted strings are positional for PowerShell commands, so build the call as if it was typed:
            # '-Name' tokens stay parameter names, everything else is a quoted literal.
            $tokens = foreach ($argument in $Arguments) {
                if ($argument -cmatch '^-[A-Za-z_][\w-]*:?$') { $argument } else { "'" + $argument.Replace("'", "''") + "'" }
            }
            $call = [scriptblock]::Create('param($__command, $__input) if ($null -ne $__input) { $__input | & $__command ' + (@($tokens) -join ' ') + ' } else { & $__command ' + (@($tokens) -join ' ') + ' }')
            # $? does not see errors written inside the script block; a new $Error[0] does ($Error.Count is
            # capped at $MaximumErrorCount, so compare the newest entry instead of the count).
            $newest = $null
            if ($global:Error.Count -gt 0) { $newest = $global:Error[0] }
            & $call $Command $InputObject
            $failed = $global:Error.Count -gt 0 -and -not [object]::ReferenceEquals($global:Error[0], $newest)
        }
    }
    catch {
        Write-GnuError -Context $Context -Message $_.Exception.Message -ExitCode 126
        return
    }
    # This module's utils set $LASTEXITCODE like a native program; other PowerShell commands only report errors.
    if ($Command.CommandType -eq 'Application' -or $Command.Name -like 'Invoke-Gnu*') { $Context.ExitCode = $global:LASTEXITCODE }
    elseif ($failed) { $Context.ExitCode = 1 }
}

function ConvertTo-GnuCommandLine {
    <#
    .SYNOPSIS
    Quotes arguments for a Windows command line (the rules of CommandLineToArgvW / the C runtime).
    #>
    param([AllowEmptyCollection()][string[]]$Arguments = @())

    $quoted = foreach ($argument in $Arguments) {
        if ($argument.Length -gt 0 -and $argument -notmatch '[\s"]') { $argument; continue }
        $builder = New-Object System.Text.StringBuilder
        [void]$builder.Append('"')
        $backslashes = 0
        foreach ($char in $argument.ToCharArray()) {
            if ($char -eq [char]92) { $backslashes++; continue }
            if ($char -eq '"') { [void]$builder.Append([string][char]92 * (2 * $backslashes + 1)) }
            elseif ($backslashes -gt 0) { [void]$builder.Append([string][char]92 * $backslashes) }
            $backslashes = 0
            [void]$builder.Append($char)
        }
        [void]$builder.Append([string][char]92 * (2 * $backslashes))
        [void]$builder.Append('"')
        $builder.ToString()
    }
    @($quoted) -join ' '
}

function New-GnuProcessStartInfo {
    <#
    .SYNOPSIS
    ProcessStartInfo for a program with arguments (ArgumentList on .NET Core, a quoted command line otherwise).
    #>
    param([Parameter(Mandatory)][string]$Path, [AllowEmptyCollection()][string[]]$Arguments = @(), [switch]$CommandLine)

    $info = New-Object System.Diagnostics.ProcessStartInfo -ArgumentList $Path
    $info.UseShellExecute = $false
    $info.WorkingDirectory = (Get-Location -PSProvider FileSystem).ProviderPath
    if (-not $CommandLine -and $null -ne $info.PSObject.Properties['ArgumentList']) { foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) } }
    else { $info.Arguments = ConvertTo-GnuCommandLine -Arguments $Arguments }
    $info
}

function Resolve-GnuExecCommand {
    <#
    .SYNOPSIS
    The command find -exec and xargs run for a name, or $null.
    .DESCRIPTION
    A util of this module answers to its GNU name, as in a shell where GNU tools are installed, even where
    PowerShell has an alias of that name (echo -> Write-Output). Anything else resolves like in PowerShell.
    #>
    param([Parameter(Mandatory)][string]$Name)
    if ($Name -notmatch '[\/]' -and @(Get-GnuUtilNameList) -ccontains $Name) {
        return Get-Command -Name (Get-GnuFunctionName -Name $Name) -CommandType Function
    }
    Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
}
