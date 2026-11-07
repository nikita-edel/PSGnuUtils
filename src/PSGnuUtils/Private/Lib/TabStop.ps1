# Tab stop lists shared by expand and unexpand (-t LIST).
#
# LIST is either a single size N (a stop every N columns) or increasing positions separated by commas
# or blanks. The last element may be prefixed with '/' (repeat every N after the last stop) or '+'
# (repeat every N starting at the last explicit stop), like GNU coreutils 8.28+.

function ConvertFrom-GnuTabStopList {
    <#
    .SYNOPSIS
    Parses -t values into @{ Stops = int[]; Repeat = int; Error = string }.
    .PARAMETER List
    Every -t value given (they are concatenated, like repeated GNU -t options).
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$List)

    $stops = New-Object 'System.Collections.Generic.List[int]'
    $repeat = 0
    $repeatAfterLast = $false
    $items = @(foreach ($value in $List) { $value -split '[,\s]+' | Where-Object { -not [string]::IsNullOrEmpty($_) } })
    for ($i = 0; $i -lt $items.Count; $i++) {
        $item = $items[$i]
        $prefix = ''
        if ($item -match '^[/+]') {
            $prefix = $item.Substring(0, 1)
            $item = $item.Substring(1)
            if ($i -ne $items.Count - 1) { return @{ Error = "'$prefix' specifier only allowed with the last value" } }
        }
        if ($item -notmatch '^\d+$') { return @{ Error = "tab size contains invalid character(s): '$($items[$i])'" } }
        $value = [int]$item
        if ($value -eq 0) { return @{ Error = 'tab size cannot be 0' } }
        if ($prefix) {
            $repeat = $value
            $repeatAfterLast = $prefix -eq '+'
            continue
        }
        if ($stops.Count -gt 0 -and $value -le $stops[$stops.Count - 1]) { return @{ Error = 'tab sizes must be ascending' } }
        $stops.Add($value)
    }

    if ($stops.Count -eq 0 -and $repeat -eq 0) { return @{ Stops = [int[]]@(); Repeat = 8; Error = $null } }
    if ($stops.Count -eq 1 -and $repeat -eq 0) { return @{ Stops = [int[]]@(); Repeat = $stops[0]; Error = $null } }
    if ($repeat -gt 0 -and -not $repeatAfterLast) {
        # '/N': stops at every multiple of N after the last explicit stop.
        return @{ Stops = $stops.ToArray(); Repeat = $repeat; RepeatFromZero = $true; Error = $null }
    }
    @{ Stops = $stops.ToArray(); Repeat = $repeat; RepeatFromZero = $false; Error = $null }
}

function Get-GnuNextTabStop {
    <#
    .SYNOPSIS
    The first tab stop after Column, or -1 if there is none (past the last explicit stop).
    #>
    param(
        [Parameter(Mandatory)][hashtable]$TabStops,
        [Parameter(Mandatory)][int]$Column
    )

    foreach ($stop in $TabStops.Stops) {
        if ($stop -gt $Column) { return $stop }
    }
    $size = $TabStops.Repeat
    if ($size -le 0) { return -1 }
    if (@($TabStops.Stops).Count -eq 0 -or ($TabStops.ContainsKey('RepeatFromZero') -and $TabStops.RepeatFromZero)) {
        return $Column + $size - ($Column % $size)
    }
    $last = $TabStops.Stops[$TabStops.Stops.Count - 1]
    $last + $size * ([Math]::Floor(($Column - $last) / $size) + 1)
}
