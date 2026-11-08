Register-GnuUtil @{
    Name          = 'unexpand'
    Category      = 'Text processing'
    Synopsis      = 'Convert spaces to tabs.'
    Usage         = @('unexpand [OPTION]... [FILE]...')
    Description   = @('Convert blanks in each FILE to tabs, writing to standard output.', '', 'With no FILE, or when FILE is -, read standard input.')
    FileOperands  = $true
    NumericOption = 't'
    Options       = @(
        @{ Short = 'a'; Long = 'all'; Help = 'convert all blanks, instead of just initial blanks' }
        @{ Long = 'first-only'; Help = 'convert only leading sequences of blanks (overrides -a)' }
        @{ Short = 't'; Long = 'tabs'; Arg = 'LIST'; Multi = $true; Help = 'use comma separated list of tab positions. The last specified position can be prefixed with ''/'' to specify a tab size to use after the last explicitly specified tab stop.  Also a prefix of ''+'' can be used to align remaining tab stops relative to the last specified tab stop instead of the first column (implies -a)' }
    )
    Notes         = @('-t N (or -N) sets tabs N characters apart, instead of the default of 8.')
}

function Invoke-GnuUnexpand {
    <#
    .SYNOPSIS
    GNU unexpand: convert spaces to tabs.

    .DESCRIPTION
    Replaces runs of blanks that reach a tab stop with tabs (every 8 columns by default, -t N or
    a list of positions). Only leading blanks are converted unless -a (or -t) is given;
    --first-only restores the leading-only behaviour.
    Enable the GNU name with: Enable-GnuAlias unexpand

    .EXAMPLE
    Get-Content source.txt | Invoke-GnuUnexpand -t 4
    #>
    begin {
        $ctx = Initialize-GnuUtil -Name 'unexpand' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput
        if (-not $ctx.Done) {
            $tabs = ConvertFrom-GnuTabStopList -List ([string[]]@(Get-GnuOptionValue -Context $ctx -Key 'tabs' -Default @()))
            if ($tabs.Error) { Write-GnuUsageError -Context $ctx -Message $tabs.Error }
            $all = (Test-GnuOption -Context $ctx -Key 'all') -or (Test-GnuOption -Context $ctx -Key 'tabs')
            if (Test-GnuOption -Context $ctx -Key 'first-only') { $all = $false }
            $stream = Test-GnuStdinOnly -Context $ctx
        }
    }
    process {
        if ($ctx.Done) { return }
        if ($stream) {
            foreach ($line in @(ConvertFrom-GnuPipelineItem -Context $ctx -InputObject $_)) { ConvertTo-GnuUnexpandedLine -Line $line -TabStops $tabs -All:$all }
        }
        else {
            Add-GnuPipelineInput -Context $ctx -InputObject $_
        }
    }
    end {
        if (-not $ctx.Done) {
            $lines = @()
            if ($stream) { $lines = @(Complete-GnuPipelineInput -Context $ctx) }
            else {
                $operands = @($ctx.Operands)
                if ($operands.Count -eq 0) { $operands = @('-') }
                $lines = @(foreach ($operand in $operands) { Get-GnuInputLine -Context $ctx -Operand $operand })
            }
            foreach ($line in $lines) { ConvertTo-GnuUnexpandedLine -Line $line -TabStops $tabs -All:$all }
        }
        Complete-GnuUtil -Context $ctx
    }
}

function ConvertTo-GnuUnexpandedLine {
    <#
    .SYNOPSIS
    Converts the blanks of one line to tabs, following GNU unexpand's pending-blank algorithm.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Line,
        [Parameter(Mandatory)][hashtable]$TabStops,
        [switch]$All
    )

    if ($Line.IndexOf(' ', [System.StringComparison]::Ordinal) -lt 0 -and $Line.IndexOf("`t", [System.StringComparison]::Ordinal) -lt 0) { return $Line }
    $builder = New-Object System.Text.StringBuilder
    $pending = New-Object System.Text.StringBuilder
    $convert = $true
    $column = 0
    $oneBlankBeforeTabStop = $false
    $previousBlank = $true
    foreach ($char in $Line.ToCharArray()) {
        if ($convert) {
            $blank = $char -eq ' ' -or $char -eq "`t"
            if ($blank) {
                $next = Get-GnuNextTabStop -TabStops $TabStops -Column $column
                if ($next -lt 0) { $convert = $false }   # past the last tab stop
                if ($convert) {
                    if ($char -eq "`t") {
                        $column = $next
                        if ($pending.Length -gt 0) { $pending[0] = "`t" }
                    }
                    else {
                        $column++
                        if (-not ($previousBlank -and $column -eq $next)) {
                            # It is not yet known whether the pending blanks will become a tab.
                            if ($column -eq $next) { $oneBlankBeforeTabStop = $true }
                            [void]$pending.Append($char)
                            $previousBlank = $true
                            continue
                        }
                        # The blanks reach a tab stop: replace them by a tab (or two).
                        if ($pending.Length -eq 0) { [void]$pending.Append(' ') }
                        $pending[0] = "`t"
                        $char = [char]"`t"
                    }
                    # Drop the pending blanks, unless it was a single blank just before the previous tab stop.
                    if ($oneBlankBeforeTabStop) { $pending.Length = 1 } else { $pending.Length = 0 }
                }
            }
            elseif ([int]$char -eq 8) {
                if ($column -gt 0) { $column-- }
            }
            else {
                $column++
            }
            Add-GnuUnexpandPending -Builder $builder -Pending $pending -OneBlankBeforeTabStop $oneBlankBeforeTabStop
            $oneBlankBeforeTabStop = $false
            $previousBlank = $blank
            $convert = $convert -and ($All -or $blank)
        }
        [void]$builder.Append($char)
    }
    Add-GnuUnexpandPending -Builder $builder -Pending $pending -OneBlankBeforeTabStop $oneBlankBeforeTabStop
    $builder.ToString()
}

function Add-GnuUnexpandPending {
    <#
    .SYNOPSIS
    Writes and clears the pending blanks of unexpand.
    #>
    param(
        [Parameter(Mandatory)][System.Text.StringBuilder]$Builder,
        [Parameter(Mandatory)][System.Text.StringBuilder]$Pending,
        [Parameter(Mandatory)][bool]$OneBlankBeforeTabStop
    )

    if ($Pending.Length -eq 0) { return }
    if ($Pending.Length -gt 1 -and $OneBlankBeforeTabStop) { $Pending[0] = "`t" }
    [void]$Builder.Append($Pending.ToString())
    $Pending.Length = 0
}
