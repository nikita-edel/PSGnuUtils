Register-GnuUtil @{
    Name        = 'uniq'
    Category    = 'Text processing'
    Synopsis    = 'Report or omit repeated lines.'
    Usage       = @('uniq [OPTION]... [INPUT [OUTPUT]]')
    Description = @(
        'Filter adjacent matching lines from INPUT (or standard input),',
        'writing to OUTPUT (or standard output).',
        '',
        'With no options, matching lines are merged to the first occurrence.'
    )
    Options     = @(
        @{ Short = 'c'; Long = 'count'; Help = 'prefix lines by the number of occurrences' }
        @{ Short = 'd'; Long = 'repeated'; Help = 'only print duplicate lines, one for each group' }
        @{ Short = 'D'; Key = 'all-repeated'; Value = 'none'; Help = 'print all duplicate lines' }
        @{ Long = 'all-repeated'; Arg = 'METHOD'; OptionalArg = $true; Help = 'like -D, but allow separating groups with an empty line; METHOD={none(default),prepend,separate}' }
        @{ Short = 'f'; Long = 'skip-fields'; Arg = 'N'; Help = 'avoid comparing the first N fields' }
        @{ Long = 'group'; Arg = 'METHOD'; OptionalArg = $true; Help = 'show all items, separating groups with an empty line; METHOD={separate(default),prepend,append,both}' }
        @{ Short = 'i'; Long = 'ignore-case'; Help = 'ignore differences in case when comparing' }
        @{ Short = 's'; Long = 'skip-chars'; Arg = 'N'; Help = 'avoid comparing the first N characters' }
        @{ Short = 'u'; Long = 'unique'; Help = 'only print unique lines' }
        @{ Short = 'z'; Long = 'zero-terminated'; Help = 'line delimiter is NUL, not newline' }
        @{ Short = 'w'; Long = 'check-chars'; Arg = 'N'; Help = 'compare no more than N characters in lines' }
    )
    Notes       = @(
        'A field is a run of blanks (usually spaces and/or TABs), then non-blank',
        'characters.  Fields are skipped before chars.',
        '',
        "Note: 'uniq' does not detect repeated lines unless they are adjacent.",
        "You may want to sort the input first, or use 'sort -u' without 'uniq'.",
        '',
        'PowerShell note: OUTPUT is written as UTF-8 without BOM with LF line endings.'
    )
}

function Invoke-GnuUniq {
    <#
    .SYNOPSIS
    GNU uniq: report or omit repeated adjacent lines.

    .DESCRIPTION
    Collapses runs of identical adjacent lines. -c counts, -d/-D show duplicates, -u unique lines,
    --group separates groups; -f/-s/-w/-i control what is compared. An OUTPUT operand writes to a
    file instead of the pipeline.
    Enable the GNU name with: Enable-GnuUtil uniq

    .EXAMPLE
    Get-Content words.txt | Sort-Object | Invoke-GnuUniq -c
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'uniq' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuUniqFilter -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function Get-GnuUniqKey {
    <#
    .SYNOPSIS
    The part of a line that uniq compares (after skipping fields and characters, limited to N chars).
    #>
    param([AllowEmptyString()][string]$Line, [long]$SkipFields, [long]$SkipChars, [long]$CheckChars, [bool]$IgnoreCase)

    $position = 0
    for ($field = 0; $field -lt $SkipFields -and $position -lt $Line.Length; $field++) {
        while ($position -lt $Line.Length -and ($Line[$position] -eq ' ' -or $Line[$position] -eq "`t")) { $position++ }
        while ($position -lt $Line.Length -and $Line[$position] -ne ' ' -and $Line[$position] -ne "`t") { $position++ }
    }
    $position = [Math]::Min([long]$Line.Length, $position + $SkipChars)
    $key = $Line.Substring([int]$position)
    if ($CheckChars -ge 0 -and $key.Length -gt $CheckChars) { $key = $key.Substring(0, [int]$CheckChars) }
    if ($IgnoreCase) { $key = $key.ToUpperInvariant() }
    $key
}

function Invoke-GnuUniqFilter {
    <#
    .SYNOPSIS
    Implementation of uniq.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $operands = @($Context.Operands)
    if ($operands.Count -gt 2) { Write-GnuUsageError -Context $Context -Message "extra operand '$($operands[2])'"; return }

    $numbers = @{ 'skip-fields' = [long]0; 'skip-chars' = [long]0; 'check-chars' = [long]-1 }
    foreach ($key in @($numbers.Keys)) {
        if (-not (Test-GnuOption -Context $Context -Key $key)) { continue }
        $text = [string](Get-GnuOptionValue -Context $Context -Key $key)
        if ($text -notmatch '^\d+$') {
            $what = 'number of bytes to compare'
            if ($key -eq 'skip-fields') { $what = 'number of fields to skip' }
            if ($key -eq 'skip-chars') { $what = 'number of bytes to skip' }
            Write-GnuUsageError -Context $Context -Message "$($text): invalid $what"
            return
        }
        $numbers[$key] = ConvertTo-GnuInt64 -Value (ConvertFrom-GnuSize -Text $text)
    }

    $count = Test-GnuOption -Context $Context -Key 'count'
    $repeated = Test-GnuOption -Context $Context -Key 'repeated'
    $unique = Test-GnuOption -Context $Context -Key 'unique'
    $allRepeated = $null
    if (Test-GnuOption -Context $Context -Key 'all-repeated') {
        $allRepeated = [string](Get-GnuOptionValue -Context $Context -Key 'all-repeated')
        if ([string]::IsNullOrEmpty($allRepeated)) { $allRepeated = 'none' }
        if (@('none', 'prepend', 'separate') -cnotcontains $allRepeated) {
            Write-GnuUsageError -Context $Context -Message "invalid argument '$allRepeated' for '--all-repeated'`nValid arguments are: 'none', 'prepend', 'separate'"
            return
        }
    }
    $group = $null
    if (Test-GnuOption -Context $Context -Key 'group') {
        $group = [string](Get-GnuOptionValue -Context $Context -Key 'group')
        if ([string]::IsNullOrEmpty($group)) { $group = 'separate' }
        if (@('separate', 'prepend', 'append', 'both') -cnotcontains $group) {
            Write-GnuUsageError -Context $Context -Message "invalid argument '$group' for '--group'`nValid arguments are: 'separate', 'prepend', 'append', 'both'"
            return
        }
        if ($count -or $repeated -or $unique -or $null -ne $allRepeated) {
            Write-GnuUsageError -Context $Context -Message '--group is mutually exclusive with -c/-d/-D/-u'
            return
        }
    }
    if ($count -and $null -ne $allRepeated) {
        Write-GnuUsageError -Context $Context -Message 'printing all duplicated lines and repeat counts is meaningless'
        return
    }

    $source = '-'
    if ($operands.Count -ge 1) { $source = $operands[0] }
    $zero = Test-GnuOption -Context $Context -Key 'zero-terminated'
    $lines = @()
    if ($zero) {
        $text = Get-GnuInputText -Context $Context -Operand $source
        if ($null -eq $text) { return }
        $lines = @(Split-GnuRecord -Text $text -Separator "`0")
    }
    else {
        $errorsBefore = $Context.ErrorCount
        $lines = @(Get-GnuInputLine -Context $Context -Operand $source)
        if ($Context.ErrorCount -gt $errorsBefore) { return }
    }

    # Build groups of adjacent equal lines.
    $groups = New-Object 'System.Collections.Generic.List[object]'
    $previousKey = $null
    foreach ($line in $lines) {
        $key = Get-GnuUniqKey -Line $line -SkipFields $numbers['skip-fields'] -SkipChars $numbers['skip-chars'] -CheckChars $numbers['check-chars'] -IgnoreCase (Test-GnuOption -Context $Context -Key 'ignore-case')
        if ($groups.Count -gt 0 -and [string]::Equals($key, $previousKey, [System.StringComparison]::Ordinal)) {
            $groups[$groups.Count - 1].Add($line)
        }
        else {
            $members = New-Object 'System.Collections.Generic.List[string]'
            $members.Add($line)
            $groups.Add($members)
        }
        $previousKey = $key
    }

    $output = New-Object 'System.Collections.Generic.List[string]'
    $printedGroup = $false
    for ($g = 0; $g -lt $groups.Count; $g++) {
        $members = $groups[$g]
        if ($null -ne $group) {
            # GNU: prepend/both put an empty line before every group, separate/append between groups,
            # and append/both one more after the last group.
            if ($group -eq 'prepend' -or $group -eq 'both' -or $g -gt 0) { $output.Add('') }
            foreach ($member in $members) { $output.Add($member) }
            if (($group -eq 'append' -or $group -eq 'both') -and $g -eq $groups.Count - 1) { $output.Add('') }
            continue
        }
        if ($null -ne $allRepeated) {
            if ($members.Count -lt 2) { continue }
            if ($allRepeated -eq 'prepend' -or ($allRepeated -eq 'separate' -and $printedGroup)) { $output.Add('') }
            foreach ($member in $members) { $output.Add($member) }
            $printedGroup = $true
            continue
        }
        if ($repeated -and $members.Count -lt 2) { continue }
        if ($unique -and $members.Count -gt 1) { continue }
        $line = $members[0]
        if ($count) { $line = ([string]$members.Count).PadLeft(7) + ' ' + $line }
        $output.Add($line)
    }

    if ($operands.Count -eq 2) {
        try {
            $separator = "`n"
            if ($zero) { $separator = "`0" }
            $content = ''
            if ($output.Count -gt 0) { $content = ($output -join $separator) + $separator }
            [System.IO.File]::WriteAllText((Resolve-GnuPath -Path $operands[1]), $content, $script:GnuUtf8)
        }
        catch {
            Write-GnuError -Context $Context -Message "$($operands[1]): $(Get-GnuErrorReason -Exception $_.Exception)"
        }
        return
    }
    ConvertTo-GnuRecordOutput -Record $output.ToArray() -Zero:$zero
}
