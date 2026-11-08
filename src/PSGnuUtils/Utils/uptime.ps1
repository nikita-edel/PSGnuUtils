Register-GnuUtil @{
    Name        = 'uptime'
    Category    = 'User and system info'
    Synopsis    = 'Tell how long the system has been running.'
    Usage       = @('uptime [OPTION]...')
    Description = @(
        'Print the current time, the length of time the system has been up,',
        'the number of users on the system, and the average number of jobs',
        'in the run queue over the last 1, 5 and 15 minutes.'
    )
    Options     = @(
        @{ Short = 'p'; Long = 'pretty'; Help = 'show uptime in pretty format (procps)' }
        @{ Short = 's'; Long = 'since'; Help = 'system up since, in yyyy-mm-dd HH:MM:SS format (procps)' }
    )
    Notes       = @(
        'PowerShell note: -p and -s come from the procps uptime. Windows has no load averages, so',
        'they are omitted there; users are the interactive sessions (explorer.exe processes).'
    )
}

function Invoke-GnuUptime {
    <#
    .SYNOPSIS
    GNU uptime: how long the system has been running.

    .DESCRIPTION
    Prints " HH:MM:SS  up D days HH:MM,  N users,  load average: A, B, C". -p prints
    "up 2 days, 3 hours, 4 minutes"; -s prints when the system booted.
    Enable the GNU name with: Enable-GnuAlias uptime

    .EXAMPLE
    Invoke-GnuUptime -p
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'uptime' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            $operands = @($ctx.Operands)
            if ($operands.Count -gt 0) { Write-GnuUsageError -Context $ctx -Message "extra operand '$($operands[0])'" }
            else {
                $now = Get-Date
                $up = Get-GnuUptime
                if (Test-GnuOption -Context $ctx -Key 'since') { $now.Add(-$up).ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture) }
                elseif (Test-GnuOption -Context $ctx -Key 'pretty') { Format-GnuUptimePretty -Uptime $up }
                else { Format-GnuUptimeLine -Now $now -Uptime $up -Users (Get-GnuUserCount) -Load (Get-GnuLoadAverage) }
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}

function Get-GnuUptime {
    <#
    .SYNOPSIS
    The time since boot (Environment.TickCount64, or the performance counter, which counts since boot on Windows).
    #>
    param([string]$Property = 'TickCount64')
    $tickCount = [System.Environment].GetProperty($Property)
    if ($null -ne $tickCount) { return [timespan]::FromMilliseconds([double]$tickCount.GetValue($null)) }
    [timespan]::FromSeconds([System.Diagnostics.Stopwatch]::GetTimestamp() / [double][System.Diagnostics.Stopwatch]::Frequency)
}

function Get-GnuUserCount {
    <#
    .SYNOPSIS
    Logged-in users: 'who' on Unix, interactive sessions (explorer.exe) on Windows.
    #>
    if (Test-GnuWindows) {
        return @(Get-Process -Name explorer -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SessionId -Unique).Count
    }
    $who = Get-Command -Name who -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $who) { return 0 }
    @(& $who 2>$null).Count
}

function Get-GnuLoadAverage {
    <#
    .SYNOPSIS
    The 1, 5 and 15 minute load averages (Linux /proc/loadavg, macOS sysctl), or nothing on Windows.
    #>
    param([string]$Path = '/proc/loadavg')
    if (Test-GnuWindows) { return }
    $text = $null
    if ([System.IO.File]::Exists($Path)) { $text = [System.IO.File]::ReadAllText($Path) }
    else {
        $sysctl = Get-Command -Name sysctl -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $sysctl) { $text = [string](& $sysctl -n vm.loadavg 2>$null) }
    }
    $numbers = @([regex]::Matches([string]$text, '\d+(\.\d+)?') | Select-Object -First 3 | ForEach-Object { [double]::Parse($_.Value, [System.Globalization.CultureInfo]::InvariantCulture) })
    if ($numbers.Count -eq 3) { return , [double[]]$numbers }
}

function Format-GnuUptimeLine {
    <#
    .SYNOPSIS
    The coreutils uptime line.
    #>
    param(
        [Parameter(Mandatory)][datetime]$Now,
        [Parameter(Mandatory)][timespan]$Uptime,
        [Parameter(Mandatory)][int]$Users,
        [AllowNull()][double[]]$Load
    )
    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $line = ' ' + $Now.ToString('HH:mm:ss', $invariant) + '  '
    $days = [int][Math]::Floor($Uptime.TotalDays)
    $clock = '{0,2}:{1:00}' -f $Uptime.Hours, $Uptime.Minutes
    if ($days -eq 1) { $line += "up 1 day $clock,  " }
    elseif ($days -gt 1) { $line += "up $days days $clock,  " }
    else { $line += "up  $clock,  " }
    if ($Users -eq 1) { $line += '1 user' } else { $line += "$Users users" }
    if ($null -ne $Load -and $Load.Count -eq 3) {
        $line += ',  load average: ' + (($Load | ForEach-Object { $_.ToString('0.00', $invariant) }) -join ', ')
    }
    $line
}

function Format-GnuUptimePretty {
    <#
    .SYNOPSIS
    The procps 'uptime -p' text.
    #>
    param([Parameter(Mandatory)][timespan]$Uptime)
    $parts = New-Object 'System.Collections.Generic.List[string]'
    $weeks = [int][Math]::Floor($Uptime.TotalDays / 7)
    $days = [int][Math]::Floor($Uptime.TotalDays) % 7
    foreach ($unit in @(@($weeks, 'week'), @($days, 'day'), @($Uptime.Hours, 'hour'), @($Uptime.Minutes, 'minute'))) {
        if ($unit[0] -eq 1) { $parts.Add("1 $($unit[1])") }
        elseif ($unit[0] -gt 1) { $parts.Add("$($unit[0]) $($unit[1])s") }
    }
    if ($parts.Count -eq 0) { return 'up 0 minutes' }
    'up ' + ($parts -join ', ')
}
