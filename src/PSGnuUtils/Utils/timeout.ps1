Register-GnuUtil @{
    Name               = 'timeout'
    Category           = 'Running commands'
    Synopsis           = 'Run a command with a time limit.'
    Usage              = @('timeout [OPTION] DURATION COMMAND [ARG]...', 'timeout [OPTION]')
    Description        = @('Start COMMAND, and kill it if still running after DURATION.')
    StopAtFirstOperand = $true
    UsageExitCode      = 125
    Options            = @(
        @{ Long = 'preserve-status'; Help = 'exit with the same status as COMMAND, even when the command times out' }
        @{ Long = 'foreground'; Help = 'when not running timeout directly from a shell prompt, allow COMMAND to read from the TTY and get TTY signals; in this mode, children of COMMAND will not be timed out' }
        @{ Short = 'k'; Long = 'kill-after'; Arg = 'DURATION'; Help = 'also send a KILL signal if COMMAND is still running this long after the initial signal was sent' }
        @{ Short = 's'; Long = 'signal'; Arg = 'SIGNAL'; Help = 'specify the signal to be sent on timeout; SIGNAL may be a name like ''HUP'' or a number; see ''kill -l'' for a list of signals' }
        @{ Short = 'v'; Long = 'verbose'; Help = 'diagnose to stderr any signal sent upon timeout' }
    )
    Notes              = @(
        'DURATION is a floating point number with an optional suffix:',
        '''s'' for seconds (the default), ''m'' for minutes, ''h'' for hours or ''d'' for days.',
        'A duration of 0 disables the associated timeout.',
        '',
        'If the command times out, and --preserve-status is not set, then exit with',
        'status 124.  Otherwise, exit with the status of COMMAND.  If no signal',
        'is specified, send the TERM signal upon timeout.  The TERM signal kills',
        'any process that does not block or catch that signal.  It may be necessary',
        'to use the KILL signal, since this signal cannot be caught, in which case',
        'the exit status is 128+9 rather than 124.',
        '',
        'PowerShell note: COMMAND must be an external program (PowerShell commands cannot be',
        'stopped from outside). On Windows every signal terminates the program and its',
        'children; a timed out program reports 128+SIGNAL with --preserve-status. Error',
        'output goes straight to the console; --foreground has no effect.'
    )
}

function Invoke-GnuTimeout {
    <#
    .SYNOPSIS
    GNU timeout: run a program with a time limit.

    .DESCRIPTION
    Runs COMMAND and terminates it after DURATION (5, 1.5m, 2h, 1d). The exit code is 124
    after a timeout (137 with -s KILL), otherwise the program's own exit code. Output is
    passed through line by line; pipeline input is written to the program's input.
    Enable the GNU name with: Enable-GnuAlias timeout

    .EXAMPLE
    Invoke-GnuTimeout 30s ping example.com

    .EXAMPLE
    Invoke-GnuTimeout -k 5 1m ./build.cmd
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'timeout' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuTimeoutCommand -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function ConvertFrom-GnuDuration {
    <#
    .SYNOPSIS
    A DURATION (number with optional s/m/h/d suffix) in seconds, or $null if invalid.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $match = [regex]::Match($Text, '^(\d+\.?\d*|\.\d+)([smhd]?)$')
    if (-not $match.Success) { return $null }
    $value = [double]::Parse($match.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture)
    switch ($match.Groups[2].Value) {
        'm' { $value *= 60 }
        'h' { $value *= 3600 }
        'd' { $value *= 86400 }
    }
    $value
}

function Invoke-GnuTimeoutCommand {
    <#
    .SYNOPSIS
    Implementation of timeout.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $operands = @($Context.Operands)
    if ($operands.Count -lt 2) { Write-GnuUsageError -Context $Context -Message 'missing operand'; return }
    $duration = ConvertFrom-GnuDuration -Text $operands[0]
    if ($null -eq $duration) { Write-GnuUsageError -Context $Context -Message "invalid time interval '$($operands[0])'"; return }
    $killAfter = 0.0
    if (Test-GnuOption -Context $Context -Key 'kill-after') {
        $text = [string](Get-GnuOptionValue -Context $Context -Key 'kill-after')
        $killAfter = ConvertFrom-GnuDuration -Text $text
        if ($null -eq $killAfter) { Write-GnuUsageError -Context $Context -Message "invalid time interval '$text'"; return }
    }
    $signalText = [string](Get-GnuOptionValue -Context $Context -Key 'signal' -Default 'TERM')
    $signal = ConvertFrom-GnuSignal -Text $signalText
    if ($null -eq $signal) { Write-GnuError -Context $Context -Message "'$signalText': invalid signal" -ExitCode 125; return }

    $name = $operands[1]
    $command = Resolve-GnuChildCommand -Context $Context -Name $name -Format "failed to run command '{0}': No such file or directory"
    if ($null -eq $command) { return }
    if ($command.CommandType -ne 'Application') {
        Write-GnuError -Context $Context -Message "failed to run command '$name': not an external program" -ExitCode 126
        return
    }

    $info = New-GnuProcessStartInfo -Path $command.Source -Arguments @($operands | Select-Object -Skip 2)
    $info.RedirectStandardOutput = $true
    $info.StandardOutputEncoding = $script:GnuUtf8
    $inputLines = $null
    if ($Context.ExpectingInput) {
        $inputLines = @(Read-GnuStdinLine -Context $Context)
        $info.RedirectStandardInput = $true
    }
    try { $process = [System.Diagnostics.Process]::Start($info) }
    catch { Write-GnuError -Context $Context -Message "failed to run command '$name': $(Get-GnuErrorReason -Exception $_.Exception)" -ExitCode 126; return }

    try {
        if ($null -ne $inputLines) {
            foreach ($line in $inputLines) { $process.StandardInput.WriteLine($line) }
            $process.StandardInput.Close()
        }
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        $timedOut = $false
        $killed = $false
        $pending = $process.StandardOutput.ReadLineAsync()
        while ($true) {
            if ($pending.Wait(25)) {
                $line = $pending.Result
                if ($null -eq $line) { break }
                $line
                $pending = $process.StandardOutput.ReadLineAsync()
                continue
            }
            $elapsed = $clock.Elapsed.TotalSeconds
            if (-not $timedOut -and $duration -gt 0 -and $elapsed -ge $duration) {
                $timedOut = $true
                if (Test-GnuOption -Context $Context -Key 'verbose') { Write-GnuWarning -Context $Context -Message "sending signal $($signal.Name) to command '$name'" }
                $null = Send-GnuSignal -Id $process.Id -Signal $signal
                $killed = $signal.Name -eq 'KILL'
            }
            elseif ($timedOut -and -not $killed -and $killAfter -gt 0 -and $elapsed -ge $duration + $killAfter) {
                if (Test-GnuOption -Context $Context -Key 'verbose') { Write-GnuWarning -Context $Context -Message "sending signal KILL to command '$name'" }
                Stop-GnuProcess -Process $process
                $killed = $true
                $signal = ConvertFrom-GnuSignal -Text 'KILL'
            }
        }
        $process.WaitForExit()
        if (-not $timedOut) { $Context.ExitCode = $process.ExitCode }
        elseif (Test-GnuOption -Context $Context -Key 'preserve-status') {
            $Context.ExitCode = $process.ExitCode
            if ((Test-GnuWindows) -or $process.ExitCode -lt 0) { $Context.ExitCode = 128 + $signal.Number }
        }
        elseif ($signal.Name -eq 'KILL') { $Context.ExitCode = 137 }
        else { $Context.ExitCode = 124 }
    }
    finally {
        if (-not $process.HasExited) { Stop-GnuProcess -Process $process }
        $process.Dispose()
    }
}
