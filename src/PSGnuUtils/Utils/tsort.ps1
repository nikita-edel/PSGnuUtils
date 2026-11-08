Register-GnuUtil @{
    Name         = 'tsort'
    Category     = 'Text processing'
    Synopsis     = 'Perform topological sort.'
    Usage        = @('tsort [OPTION] [FILE]')
    Description  = @(
        'Write totally ordered list consistent with the partial ordering in FILE.',
        '',
        'With no FILE, or when FILE is -, read standard input.'
    )
    FileOperands = $true
    Notes        = @('The output order is the same as GNU tsort (items without an ordering in strcmp order).')
}

function Invoke-GnuTsort {
    <#
    .SYNOPSIS
    GNU tsort: topological sort of whitespace separated pairs "BEFORE AFTER".

    .DESCRIPTION
    Reads pairs of items and prints every item once, each before the items it must precede.
    Cycles are reported ("input contains a loop") and the remaining items are still printed.
    Enable the GNU name with: Enable-GnuAlias tsort

    .EXAMPLE
    'build test', 'test deploy', 'lint test' | Invoke-GnuTsort
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'tsort' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuTopologicalSort -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function Invoke-GnuTopologicalSort {
    <#
    .SYNOPSIS
    Implementation of tsort: a port of the GNU algorithm, so the output order matches GNU.

    .DESCRIPTION
    Items are visited in ordinal (strcmp) order, successors newest first. When no item is free,
    a loop is searched for, printed to the error stream and broken by removing one relation.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $operands = @($Context.Operands)
    if ($operands.Count -gt 1) { Write-GnuUsageError -Context $Context -Message "extra operand '$($operands[1])'"; return }
    $operand = '-'
    if ($operands.Count -eq 1) { $operand = $operands[0] }
    $text = Get-GnuInputText -Context $Context -Operand $operand
    if ($null -eq $text) { return }

    $tokens = @($text -split '\s+' | Where-Object { -not [string]::IsNullOrEmpty($_) })
    if ($tokens.Count % 2 -ne 0) {
        Write-GnuError -Context $Context -Message "$($operand): input contains an odd number of tokens"
        return
    }

    $items = New-Object 'System.Collections.Generic.Dictionary[string,hashtable]' -ArgumentList ([System.StringComparer]::Ordinal)
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        if (-not $items.ContainsKey($tokens[$i])) {
            $items[$tokens[$i]] = @{ Name = $tokens[$i]; Count = 0; Top = (New-Object 'System.Collections.Generic.List[hashtable]'); QLink = $null; Printed = $false }
        }
        if ($i % 2 -eq 1 -and $tokens[$i - 1] -cne $tokens[$i]) {
            # "a a" only declares the item.
            $items[$tokens[$i]].Count++
            $items[$tokens[$i - 1]].Top.Insert(0, $items[$tokens[$i]])
        }
    }
    $names = New-Object 'System.Collections.Generic.List[string]' -ArgumentList (, [string[]]@($items.Keys))
    $names.Sort([System.StringComparer]::Ordinal)
    $sorted = @(foreach ($name in $names) { $items[$name] })

    $remaining = $sorted.Count
    $loop = $null
    while ($remaining -gt 0) {
        $head = $null
        $tail = $null
        foreach ($item in $sorted) {
            if ($item.Count -ne 0 -or $item.Printed) { continue }
            if ($null -eq $head) { $head = $item } else { $tail.QLink = $item }
            $tail = $item
        }
        while ($null -ne $head) {
            $head.Name
            $head.Printed = $true
            $remaining--
            foreach ($successor in $head.Top) {
                $successor.Count--
                if ($successor.Count -eq 0) { $tail.QLink = $successor; $tail = $successor }
            }
            $head = $head.QLink
        }
        if ($remaining -eq 0) { break }

        Write-GnuError -Context $Context -Message "$($operand): input contains a loop:"
        do {
            foreach ($item in $sorted) {
                if ($item.Count -le 0) { continue }
                if ($null -eq $loop) { $loop = $item; continue }
                $found = $false
                for ($p = 0; $p -lt $item.Top.Count; $p++) {
                    if (-not [object]::ReferenceEquals($item.Top[$p], $loop)) { continue }
                    if ($null -eq $item.QLink) { $item.QLink = $loop; $loop = $item; break }
                    # Found a loop: print the path back to this item and remove the relation.
                    while ($null -ne $loop) {
                        $next = $loop.QLink
                        Write-GnuError -Context $Context -Message $loop.Name
                        if ([object]::ReferenceEquals($loop, $item)) {
                            $item.Top[$p].Count--
                            $item.Top.RemoveAt($p)
                            break
                        }
                        $loop.QLink = $null
                        $loop = $next
                    }
                    while ($null -ne $loop) { $next = $loop.QLink; $loop.QLink = $null; $loop = $next }
                    $found = $true
                    break
                }
                if ($found) { break }
            }
        } while ($null -ne $loop)
    }
}
