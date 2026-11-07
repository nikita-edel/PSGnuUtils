Register-GnuUtil @{
    Name          = 'expand'
    Category      = 'Text processing'
    Synopsis      = 'Convert tabs to spaces.'
    Usage         = @('expand [OPTION]... [FILE]...')
    Description   = @('Convert tabs in each FILE to spaces, writing to standard output.', '', 'With no FILE, or when FILE is -, read standard input.')
    FileOperands  = $true
    NumericOption = 't'
    Options       = @(
        @{ Short = 'i'; Long = 'initial'; Help = 'do not convert tabs after non blanks' }
        @{ Short = 't'; Long = 'tabs'; Arg = 'LIST'; Multi = $true; Help = 'use comma separated list of tab positions. The last specified position can be prefixed with ''/'' to specify a tab size to use after the last explicitly specified tab stop.  Also a prefix of ''+'' can be used to align remaining tab stops relative to the last specified tab stop instead of the first column' }
    )
    Notes         = @('-t N (or -N) sets tabs N characters apart, instead of the default of 8.')
}

function Invoke-GnuExpand {
    <#
    .SYNOPSIS
    GNU expand: convert tabs to spaces.

    .DESCRIPTION
    Replaces every tab with spaces up to the next tab stop (every 8 columns by default, -t N or a
    list of positions). -i only converts tabs before the first non-blank character.
    Enable the GNU name with: Enable-GnuUtil expand

    .EXAMPLE
    Get-Content Makefile | Invoke-GnuExpand -t 4
    #>
    begin {
        $ctx = Initialize-GnuUtil -Name 'expand' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput
        if (-not $ctx.Done) {
            $tabs = ConvertFrom-GnuTabStopList -List ([string[]]@(Get-GnuOptionValue -Context $ctx -Key 'tabs' -Default @()))
            if ($tabs.Error) { Write-GnuUsageError -Context $ctx -Message $tabs.Error }
            $initial = Test-GnuOption -Context $ctx -Key 'initial'
            $stream = Test-GnuStdinOnly -Context $ctx
        }
    }
    process {
        if ($ctx.Done) { return }
        if ($stream) {
            foreach ($line in @(ConvertFrom-GnuPipelineItem -Context $ctx -InputObject $_)) { ConvertTo-GnuExpandedLine -Line $line -TabStops $tabs -Initial:$initial }
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
            foreach ($line in $lines) { ConvertTo-GnuExpandedLine -Line $line -TabStops $tabs -Initial:$initial }
        }
        Complete-GnuUtil -Context $ctx
    }
}

function ConvertTo-GnuExpandedLine {
    <#
    .SYNOPSIS
    Expands the tabs of one line.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Line,
        [Parameter(Mandatory)][hashtable]$TabStops,
        [switch]$Initial
    )

    if ($Line.IndexOf("`t", [System.StringComparison]::Ordinal) -lt 0) { return $Line }
    $builder = New-Object System.Text.StringBuilder
    $column = 0
    $leading = $true
    foreach ($char in $Line.ToCharArray()) {
        if ($char -eq "`t" -and (-not $Initial -or $leading)) {
            $next = Get-GnuNextTabStop -TabStops $TabStops -Column $column
            if ($next -lt 0) { $next = $column + 1 }   # GNU: past the last stop a tab becomes one space
            [void]$builder.Append(' ', $next - $column)
            $column = $next
            continue
        }
        if ($char -ne ' ' -and $char -ne "`t") { $leading = $false }
        if ([int]$char -eq 8) { if ($column -gt 0) { $column-- } }
        else { $column++ }
        [void]$builder.Append($char)
    }
    $builder.ToString()
}
