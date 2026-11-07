Register-GnuUtil @{
    Name        = 'sleep'
    Category    = 'Shell helpers'
    Synopsis    = 'Delay for a specified amount of time.'
    Usage       = @('sleep NUMBER[SUFFIX]...', 'sleep OPTION')
    Description = @(
        'Pause for NUMBER seconds. SUFFIX may be ''s'' for seconds (the default),',
        '''m'' for minutes, ''h'' for hours or ''d'' for days. NUMBER need not be an',
        'integer. Given two or more arguments, pause for the amount of time',
        'specified by the sum of their values. ''infinity'' sleeps forever.'
    )
}

function Invoke-GnuSleep {
    <#
    .SYNOPSIS
    GNU sleep: delay for a specified amount of time.

    .DESCRIPTION
    Sleeps for the sum of all NUMBER[SUFFIX] operands (s, m, h, d; fractions allowed).
    The sleep can be interrupted with Ctrl+C.
    Enable the GNU name with: Enable-GnuUtil sleep (replaces the sleep -> Start-Sleep alias).

    .EXAMPLE
    Invoke-GnuSleep 1.5

    Waits one and a half seconds.

    .EXAMPLE
    Invoke-GnuSleep 1m 30s

    Waits 90 seconds.
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'sleep' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            $operands = @($ctx.Operands)
            $seconds = [double]0
            $infinite = $false
            $invalid = @()
            foreach ($operand in $operands) {
                $value = ConvertFrom-GnuSleepInterval -Text $operand
                if ($null -eq $value) { $invalid += $operand }
                elseif ([double]::IsPositiveInfinity($value)) { $infinite = $true }
                else { $seconds += $value }
            }

            if ($operands.Count -eq 0) {
                Write-GnuUsageError -Context $ctx -Message 'missing operand'
            }
            elseif ($invalid.Count -gt 0) {
                for ($i = 0; $i -lt $invalid.Count - 1; $i++) { Write-GnuError -Context $ctx -Message "invalid time interval '$($invalid[$i])'" }
                Write-GnuUsageError -Context $ctx -Message "invalid time interval '$($invalid[$invalid.Count - 1])'"
            }
            elseif ($infinite -or [double]::IsInfinity($seconds)) {
                while ($true) { Start-Sleep -Seconds 3600 }
            }
            else {
                $remaining = [Math]::Round($seconds * 1000)
                while ($remaining -gt 0) {
                    $chunk = [int][Math]::Min($remaining, [int]::MaxValue)
                    Start-Sleep -Milliseconds $chunk
                    $remaining -= $chunk
                }
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}

function ConvertFrom-GnuSleepInterval {
    <#
    .SYNOPSIS
    Parses NUMBER[smhd] (or inf/infinity) into seconds. Returns nothing if the text is invalid.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    if ($Text -notmatch '^(?<number>(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?|inf|infinity)(?<unit>[smhd]?)$') { return }
    $number = $Matches['number']
    if ($number -like 'inf*') { return [double]::PositiveInfinity }

    $value = [double]::Parse($number, [System.Globalization.CultureInfo]::InvariantCulture)
    switch ($Matches['unit']) {
        'm' { $value *= 60 }
        'h' { $value *= 3600 }
        'd' { $value *= 86400 }
    }
    $value
}
