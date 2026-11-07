Register-GnuUtil @{
    Name         = 'comm'
    Category     = 'Text processing'
    Synopsis     = 'Compare two sorted files line by line.'
    Usage        = @('comm [OPTION]... FILE1 FILE2')
    Description  = @(
        'Compare sorted files FILE1 and FILE2 line by line.',
        '',
        'When FILE1 or FILE2 (not both) is -, read standard input.',
        '',
        'With no options, produce three-column output.  Column one contains',
        'lines unique to FILE1, column two contains lines unique to FILE2,',
        'and column three contains lines common to both files.'
    )
    FileOperands = $true
    Options      = @(
        @{ Short = '1'; Key = 'hide1'; Help = 'suppress column 1 (lines unique to FILE1)' }
        @{ Short = '2'; Key = 'hide2'; Help = 'suppress column 2 (lines unique to FILE2)' }
        @{ Short = '3'; Key = 'hide3'; Help = 'suppress column 3 (lines that appear in both files)' }
        @{ Long = 'check-order'; Key = 'order'; Value = 'check'; Help = 'check that the input is correctly sorted, even if all input lines are pairable' }
        @{ Long = 'nocheck-order'; Key = 'order'; Value = 'none'; Help = 'do not check that the input is correctly sorted' }
        @{ Long = 'output-delimiter'; Arg = 'STR'; Help = 'separate columns with STR' }
        @{ Long = 'total'; Help = 'output a summary' }
        @{ Short = 'z'; Long = 'zero-terminated'; Help = 'line delimiter is NUL, not newline' }
    )
    Notes        = @('PowerShell note: lines are compared ordinally (like LC_ALL=C), not with locale collation.')
}

function Invoke-GnuComm {
    <#
    .SYNOPSIS
    GNU comm: compare two sorted files line by line.

    .DESCRIPTION
    Prints lines only in FILE1 (column 1), only in FILE2 (column 2, indented by one TAB) and in
    both (column 3, two TABs). -1 -2 -3 hide columns, --total adds counts. Input must be sorted
    ordinally; unsorted input is reported (exit code 1) unless --nocheck-order is given.
    Enable the GNU name with: Enable-GnuUtil comm

    .EXAMPLE
    Invoke-GnuComm -12 old.txt new.txt

    Lines present in both files.
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'comm' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuCommCompare -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function Invoke-GnuCommCompare {
    <#
    .SYNOPSIS
    Implementation of comm.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $operands = @($Context.Operands)
    if ($operands.Count -eq 0) { Write-GnuUsageError -Context $Context -Message 'missing operand'; return }
    if ($operands.Count -eq 1) { Write-GnuUsageError -Context $Context -Message "missing operand after '$($operands[0])'"; return }
    if ($operands.Count -gt 2) { Write-GnuUsageError -Context $Context -Message "extra operand '$($operands[2])'"; return }

    $zero = Test-GnuOption -Context $Context -Key 'zero-terminated'
    $files = @()
    foreach ($operand in $operands) {
        $errorsBefore = $Context.ErrorCount
        if ($zero) {
            $text = Get-GnuInputText -Context $Context -Operand $operand
            $records = @()
            if ($null -ne $text) { $records = @(Split-GnuRecord -Text $text -Separator "`0") }
        }
        else {
            $records = @(Get-GnuInputLine -Context $Context -Operand $operand)
        }
        if ($Context.ErrorCount -gt $errorsBefore) { return }
        $files += , $records
    }

    $delimiter = "`t"
    if (Test-GnuOption -Context $Context -Key 'output-delimiter') {
        $delimiter = [string](Get-GnuOptionValue -Context $Context -Key 'output-delimiter')
        if ($delimiter.Length -eq 0) { $delimiter = [string][char]0 }   # GNU: an empty delimiter means NUL
    }
    $show = @(
        -not (Test-GnuOption -Context $Context -Key 'hide1'),
        -not (Test-GnuOption -Context $Context -Key 'hide2'),
        -not (Test-GnuOption -Context $Context -Key 'hide3')
    )
    $prefix = @('', '', '')
    if ($show[0]) { $prefix[1] = $delimiter; $prefix[2] = $delimiter }
    if ($show[1]) { $prefix[2] += $delimiter }

    $orderMode = [string](Get-GnuOptionValue -Context $Context -Key 'order' -Default 'default')
    $unsorted = @($false, $false)
    $totals = @([long]0, [long]0, [long]0)
    $output = New-Object 'System.Collections.Generic.List[string]'
    $left = $files[0]
    $right = $files[1]
    $i = 0
    $j = 0

    while ($i -lt $left.Count -or $j -lt $right.Count) {
        $column = 0
        if ($i -ge $left.Count) { $column = 1 }
        elseif ($j -ge $right.Count) { $column = 0 }
        else {
            $order = [string]::CompareOrdinal($left[$i], $right[$j])
            if ($order -lt 0) { $column = 0 } elseif ($order -gt 0) { $column = 1 } else { $column = 2 }
        }

        # Order check: each file must be non-decreasing (only reported for unpairable lines unless --check-order).
        foreach ($side in @(0, 1)) {
            $lines = $files[$side]
            $index = $i
            if ($side -eq 1) { $index = $j }
            $consumes = ($column -eq $side) -or ($column -eq 2)
            if ($orderMode -ne 'none' -and $consumes -and $index -gt 0 -and -not $unsorted[$side] -and
                [string]::CompareOrdinal($lines[$index - 1], $lines[$index]) -gt 0 -and ($column -ne 2 -or $orderMode -eq 'check')) {
                $unsorted[$side] = $true
                Write-GnuError -Context $Context -Message "file $($side + 1) is not in sorted order"
                if ($orderMode -eq 'check') { return }
            }
        }

        $text = $null
        switch ($column) {
            0 { $text = $left[$i]; $i++ }
            1 { $text = $right[$j]; $j++ }
            2 { $text = $left[$i]; $i++; $j++ }
        }
        $totals[$column]++
        if ($show[$column]) { $output.Add($prefix[$column] + $text) }
    }

    if (Test-GnuOption -Context $Context -Key 'total') {
        $output.Add(($totals -join $delimiter) + $delimiter + 'total')
    }
    if ($unsorted[0] -or $unsorted[1]) {
        # GNU prints this after the output; the errors above already set the exit code.
        Write-GnuError -Context $Context -Message 'input is not in sorted order'
    }
    ConvertTo-GnuRecordOutput -Record $output.ToArray() -Zero:$zero
}
