# Shared implementation of head and tail.

function New-GnuHeadTailState {
    <#
    .SYNOPSIS
    Parses the count options shared by head and tail.
    .PARAMETER AllowSuffixSign
    '-' for head (all but the last NUM), '+' for tail (starting at NUM).
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][ValidateSet('-', '+')][string]$AllowSuffixSign
    )

    $state = @{ Unit = 'lines'; Count = [long]10; Signed = $false; Stream = $false; Emitted = [long]0 }
    if (Test-GnuOption -Context $Context -Key 'count') {
        $state.Unit = [string](Get-GnuOptionValue -Context $Context -Key 'unit' -Default 'lines')
        $original = [string](Get-GnuOptionValue -Context $Context -Key 'count')
        $text = $original
        if ($text.StartsWith($AllowSuffixSign)) {
            $state.Signed = $true
            $text = $text.Substring(1)
        }
        elseif ($text.StartsWith('+') -or $text.StartsWith('-')) {
            $text = $text.Substring(1)
        }
        $value = ConvertFrom-GnuSize -Text $text
        if ($null -eq $value) {
            Write-GnuError -Context $Context -Message "invalid number of $($state.Unit): '$original'"
            $Context.Done = $true
            return $state
        }
        $state.Count = ConvertTo-GnuInt64 -Value $value
    }

    $state.Stream = (Test-GnuStdinOnly -Context $Context) -and $state.Unit -eq 'lines' -and -not $state.Signed -and
        -not (Test-GnuOption -Context $Context -Key 'zero-terminated') -and
        (Get-GnuOptionValue -Context $Context -Key 'headers' -Default 'auto') -ne 'always'
    $state
}

function Select-GnuHeadTailItem {
    <#
    .SYNOPSIS
    Selects lines/records/bytes from an array for head or tail.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items,
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][ValidateSet('head', 'tail')][string]$Mode
    )

    $total = [long]$Items.Count
    $first = [long]0
    $last = $total
    if ($Mode -eq 'head') {
        if ($State.Signed) { $last = [Math]::Max([long]0, $total - $State.Count) }
        else { $last = [Math]::Min($total, $State.Count) }
    }
    else {
        if ($State.Signed) { $first = [Math]::Max([long]0, $State.Count - 1) }
        else { $first = [Math]::Max([long]0, $total - $State.Count) }
    }
    if ($first -ge $last) { return }
    $Items[$first..($last - 1)]
}

function Invoke-GnuHeadTailOperand {
    <#
    .SYNOPSIS
    Processes every operand for head or tail, printing '==> NAME <==' headers when needed.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][ValidateSet('head', 'tail')][string]$Mode
    )

    $operands = @($Context.Operands)
    if ($operands.Count -eq 0) { $operands = @('-') }
    $headerMode = [string](Get-GnuOptionValue -Context $Context -Key 'headers' -Default 'auto')
    $showHeaders = $headerMode -eq 'always' -or ($headerMode -eq 'auto' -and $operands.Count -gt 1)
    $zero = Test-GnuOption -Context $Context -Key 'zero-terminated'
    $printedAny = $false

    foreach ($operand in $operands) {
        $errorsBefore = $Context.ErrorCount
        $output = @()
        if ($State.Unit -eq 'bytes') {
            $bytes = Get-GnuInputBytes -Context $Context -Operand $operand
            if ($null -ne $bytes) {
                $selected = [byte[]]@(Select-GnuHeadTailItem -Items ([object[]]$bytes) -State $State -Mode $Mode)
                $output = @(ConvertTo-GnuOutputLine -Text $script:GnuUtf8.GetString($selected))
            }
        }
        elseif ($zero) {
            $text = Get-GnuInputText -Context $Context -Operand $operand
            if ($null -ne $text) {
                $records = @(Split-GnuRecord -Text $text -Separator "`0")
                $output = @(ConvertTo-GnuRecordOutput -Record @(Select-GnuHeadTailItem -Items $records -State $State -Mode $Mode) -Zero)
            }
        }
        elseif ($Mode -eq 'head' -and -not $State.Signed) {
            $output = @(Get-GnuInputLine -Context $Context -Operand $operand -Limit ([Math]::Max([long]1, $State.Count)))
            if ($State.Count -eq 0) { $output = @() }
        }
        else {
            $lines = @(Get-GnuInputLine -Context $Context -Operand $operand)
            $output = @(Select-GnuHeadTailItem -Items $lines -State $State -Mode $Mode)
        }

        if ($Context.ErrorCount -gt $errorsBefore) { continue }
        if ($showHeaders) {
            if ($printedAny) { '' }
            "==> $(Get-GnuDisplayName -Operand $operand) <=="
        }
        $printedAny = $true
        $output
    }
}
