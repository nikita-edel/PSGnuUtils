Register-GnuUtil @{
    Name         = 'kill'
    Category     = 'Running commands'
    Synopsis     = 'Send a signal to a process.'
    Usage        = @('kill [-s SIGNAL | -SIGNAL] PID...', 'kill -l [SIGNAL]...', 'kill -t [SIGNAL]...')
    Description  = @('Send signals to processes, or list signals.')
    RawArguments = $true
    Options      = @(
        @{ Short = 's'; Long = 'signal'; Arg = 'SIGNAL'; Help = 'specify the name or number of the signal to be sent' }
        @{ Short = 'l'; Long = 'list'; Help = 'list signal names, or convert signal names to/from numbers' }
        @{ Short = 't'; Long = 'table'; Help = 'print a table of signal information' }
    )
    Notes        = @(
        'SIGNAL may be a signal name like ''HUP'', or a signal number like ''1'',',
        'or the exit status of a process terminated by a signal.',
        'PID is an integer; if negative it identifies a process group.',
        '',
        'PowerShell note: numbers are those of Linux. On Windows every signal terminates the',
        'process (with its children) and signal 0 only checks that it exists. Process groups',
        '(negative PIDs) are not supported.'
    )
}

function Invoke-GnuKill {
    <#
    .SYNOPSIS
    GNU kill: send a signal to processes, or list signal names and numbers.

    .DESCRIPTION
    Sends TERM (or -s SIGNAL / -SIGNAL) to every PID. -l lists the signal names or converts
    between names and numbers, -t prints a table. On Windows the process is terminated.
    Enable the GNU name with: Enable-GnuUtil kill

    .EXAMPLE
    Invoke-GnuKill -9 1234

    .EXAMPLE
    Invoke-GnuKill -l 15
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'kill' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) { Invoke-GnuKillSignal -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function Invoke-GnuKillSignal {
    <#
    .SYNOPSIS
    Implementation of kill (its own argument parsing, because -SIGNAL and -NUMBER are options).
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $arguments = [string[]]@($Context.Operands)
    $mode = 'send'
    $signalText = 'TERM'
    $index = 0
    while ($index -lt $arguments.Length) {
        $argument = $arguments[$index]
        if ($argument -ceq '--') { $index++; break }
        if ($argument -ceq '-l' -or $argument -ceq '--list') { $mode = 'list' }
        elseif ($argument -ceq '-t' -or $argument -ceq '--table' -or $argument -ceq '-L') { $mode = 'table' }
        elseif ($argument -ceq '-s' -or $argument -ceq '--signal') {
            $index++
            if ($index -ge $arguments.Length) { Write-GnuUsageError -Context $Context -Message "option requires an argument -- 's'"; return }
            $signalText = $arguments[$index]
        }
        elseif ($argument -cmatch '^--signal=(.*)$') { $signalText = $Matches[1] }
        elseif ($argument -cmatch '^-s(.+)$') { $signalText = $Matches[1] }
        elseif ($argument -cmatch '^-(\w+)$' -and $mode -eq 'send') { $signalText = $Matches[1] }
        else { break }
        $index++
    }
    $rest = @()
    if ($index -lt $arguments.Length) { $rest = $arguments[$index..($arguments.Length - 1)] }

    if ($mode -ne 'send') {
        $names = @($script:GnuSignals.Keys)
        $width = ($names | Measure-Object -Property Length -Maximum).Maximum
        if ($rest.Count -eq 0) {
            foreach ($name in $names) {
                if ($mode -eq 'list') { $name }
                else { '{0,2} {1} {2}' -f $script:GnuSignals[$name][0], $name.PadRight($width), $script:GnuSignals[$name][1] }
            }
            return
        }
        foreach ($item in $rest) {
            $lookup = $item
            if ($item -match '^\d+$' -and [int]$item -gt 128) { $lookup = [string]([int]$item - 128) }
            $signal = ConvertFrom-GnuSignal -Text $lookup
            if ($null -eq $signal -or $signal.Number -eq 0) { Write-GnuError -Context $Context -Message "'$item': invalid signal"; continue }
            if ($mode -eq 'table') { '{0,2} {1} {2}' -f $signal.Number, $signal.Name.PadRight($width), $script:GnuSignals[$signal.Name][1] }
            elseif ($item -match '^\d+$') { $signal.Name }
            else { [string]$signal.Number }
        }
        return
    }

    $signal = ConvertFrom-GnuSignal -Text $signalText
    if ($null -eq $signal) { Write-GnuError -Context $Context -Message "'$signalText': invalid signal"; return }
    if ($rest.Count -eq 0) { Write-GnuUsageError -Context $Context -Message 'no process ID specified'; return }
    foreach ($item in $rest) {
        $id = 0
        if (-not [int]::TryParse($item, [ref]$id)) { Write-GnuError -Context $Context -Message "'$item': invalid process id"; continue }
        if ($id -le 0) { Write-GnuError -Context $Context -Message "'$item': process groups are not supported"; continue }
        $reason = Send-GnuSignal -Id $id -Signal $signal
        if ($null -ne $reason) { Write-GnuError -Context $Context -Message "'$item': $reason" }
    }
}
