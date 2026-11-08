Register-GnuUtil @{
    Name         = 'join'
    Category     = 'Text processing'
    Synopsis     = 'Join lines of two files on a common field.'
    Usage        = @('join [OPTION]... FILE1 FILE2')
    Description  = @(
        'For each pair of input lines with identical join fields, write a line to',
        'standard output.  The default join field is the first, delimited by blanks.',
        '',
        'When FILE1 or FILE2 (not both) is -, read standard input.'
    )
    FileOperands = $true
    Options      = @(
        @{ Short = 'a'; Arg = 'FILENUM'; Multi = $true; Help = 'also print unpairable lines from file FILENUM, where FILENUM is 1 or 2, corresponding to FILE1 or FILE2' }
        @{ Short = 'e'; Arg = 'STRING'; Help = 'replace missing (empty) input fields with STRING; I.e., missing fields specified with ''-12jo'' options' }
        @{ Short = 'i'; Long = 'ignore-case'; Help = 'ignore differences in case when comparing fields' }
        @{ Short = 'j'; Arg = 'FIELD'; Help = 'equivalent to ''-1 FIELD -2 FIELD''' }
        @{ Short = 'o'; Arg = 'FORMAT'; Multi = $true; Help = 'obey FORMAT while constructing output line' }
        @{ Short = 't'; Arg = 'CHAR'; Help = 'use CHAR as input and output field separator' }
        @{ Short = 'v'; Arg = 'FILENUM'; Multi = $true; Help = 'like -a FILENUM, but suppress joined output lines' }
        @{ Short = '1'; Arg = 'FIELD'; Help = 'join on this FIELD of file 1' }
        @{ Short = '2'; Arg = 'FIELD'; Help = 'join on this FIELD of file 2' }
        @{ Long = 'check-order'; Key = 'order'; Value = 'check'; Help = 'check that the input is correctly sorted, even if all input lines are pairable' }
        @{ Long = 'nocheck-order'; Key = 'order'; Value = 'none'; Help = 'do not check that the input is correctly sorted' }
        @{ Long = 'header'; Help = 'treat the first line in each file as field headers, print them without trying to pair them' }
        @{ Short = 'z'; Long = 'zero-terminated'; Help = 'line delimiter is NUL, not newline' }
    )
    Notes        = @(
        'Unless -t CHAR is given, leading blanks separate fields and are ignored,',
        'else fields are separated by CHAR.  Any FIELD is a field number counted',
        'from 1.  FORMAT is one or more comma or blank separated specifications,',
        'each being ''FILENUM.FIELD'' or ''0''.  Default FORMAT outputs the join field,',
        'the remaining fields from FILE1, the remaining fields from FILE2, all',
        'separated by CHAR.  If FORMAT is the keyword ''auto'', then the first',
        'line of each file determines the number of fields output for each line.',
        '',
        'Important: FILE1 and FILE2 must be sorted on the join fields.',
        'E.g., use "sort -k 1b,1" if ''join'' has no options,',
        'or use "join -t ''''" if ''sort'' has no options.',
        '',
        'PowerShell note: fields are compared ordinally (as sort does in the C locale).'
    )
}

function Invoke-GnuJoin {
    <#
    .SYNOPSIS
    GNU join: join the lines of two sorted files on a common field.

    .DESCRIPTION
    Prints a line for each pair of lines whose join fields (first field, or -1 / -2 / -j)
    are equal. -a and -v print unpairable lines, -o selects output fields, -e fills
    missing ones, -t sets the separator. Inputs must be sorted on the join field.
    Enable the GNU name with: Enable-GnuAlias join

    .EXAMPLE
    Invoke-GnuJoin -t ',' -a 1 users.csv orders.csv
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'join' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuJoinFiles -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function ConvertFrom-GnuJoinField {
    <#
    .SYNOPSIS
    A 1-based field number, or $null after reporting it.
    #>
    param([Parameter(Mandatory)][hashtable]$Context, [Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    if ($Text -notmatch '^\d+$' -or [long]$Text -lt 1) { Write-GnuError -Context $Context -Message "invalid field number: '$Text'"; return $null }
    [int]$Text
}

function Split-GnuJoinLine {
    <#
    .SYNOPSIS
    The fields of a line: blank separated (leading blanks ignored), or split at the -t character.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Line, [AllowNull()][object]$Separator)
    if ($null -eq $Separator) { return , [string[]]@($Line -split '[ \t]+' | Where-Object { $_.Length -gt 0 }) }
    if ([string]::IsNullOrEmpty([string]$Separator)) { return , [string[]]@($Line) }
    , [string[]]$Line.Split([char][string]$Separator)
}

function Invoke-GnuJoinFiles {
    <#
    .SYNOPSIS
    Implementation of join (GNU's merge algorithm, including its order checks).
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $operands = @($Context.Operands)
    if ($operands.Count -eq 0) { Write-GnuUsageError -Context $Context -Message 'missing operand'; return }
    if ($operands.Count -eq 1) { Write-GnuUsageError -Context $Context -Message "missing operand after '$($operands[0])'"; return }
    if ($operands.Count -gt 2) { Write-GnuUsageError -Context $Context -Message "extra operand '$($operands[2])'"; return }

    $separator = $null
    if (Test-GnuOption -Context $Context -Key 't') {
        $separator = [string](Get-GnuOptionValue -Context $Context -Key 't')
        if ($separator.Length -gt 1 -and $separator -ne '\0') { Write-GnuError -Context $Context -Message "multi-character tab '$separator'"; return }
        if ($separator -eq '\0') { $separator = [string][char]0 }
    }
    $fields = @(1, 1)
    foreach ($entry in @(@('j', 0), @('1', 1), @('2', 2))) {
        if (-not (Test-GnuOption -Context $Context -Key $entry[0])) { continue }
        $number = ConvertFrom-GnuJoinField -Context $Context -Text ([string](Get-GnuOptionValue -Context $Context -Key $entry[0]))
        if ($null -eq $number) { return }
        if ($entry[1] -eq 0) { $fields = @($number, $number) } else { $fields[$entry[1] - 1] = $number }
    }
    $printUnpaired = @($false, $false)
    $printPaired = $true
    foreach ($key in @('a', 'v')) {
        foreach ($value in @(Get-GnuOptionValue -Context $Context -Key $key -Default @())) {
            if ($value -ne '1' -and $value -ne '2') { Write-GnuError -Context $Context -Message "invalid field number: '$value'"; return }
            $printUnpaired[[int]$value - 1] = $true
            if ($key -eq 'v') { $printPaired = $false }
        }
    }
    $format = $null
    $auto = $false
    if (Test-GnuOption -Context $Context -Key 'o') {
        $specs = New-Object 'System.Collections.Generic.List[object]'
        foreach ($text in @(Get-GnuOptionValue -Context $Context -Key 'o')) {
            if ($text -eq 'auto') { $auto = $true; continue }
            foreach ($item in @($text -split '[, \t]+' | Where-Object { $_.Length -gt 0 })) {
                if ($item -eq '0') { $specs.Add(@(0, 0)); continue }
                if ($item -match '^\d+\.\d+$' -and $item -notmatch '^[12]\.') { Write-GnuError -Context $Context -Message "invalid file number in field spec: '$item'"; return }
                if ($item -notmatch '^([12])\.(\d+)$') { Write-GnuError -Context $Context -Message "invalid field specifier: '$item'"; return }
                if ([int]$Matches[2] -lt 1) { Write-GnuError -Context $Context -Message "invalid field number: '$($Matches[2])'"; return }
                $specs.Add(@([int]$Matches[1], [int]$Matches[2]))
            }
        }
        if (-not $auto) { $format = $specs }
    }
    $empty = $null
    if (Test-GnuOption -Context $Context -Key 'e') { $empty = [string](Get-GnuOptionValue -Context $Context -Key 'e') }
    $ignoreCase = Test-GnuOption -Context $Context -Key 'ignore-case'
    $order = [string](Get-GnuOptionValue -Context $Context -Key 'order' -Default 'default')
    $zero = Test-GnuOption -Context $Context -Key 'zero-terminated'
    $outSeparator = ' '
    if ($null -ne $separator -and $separator.Length -gt 0) { $outSeparator = $separator }

    $files = @()
    foreach ($operand in $operands) {
        $text = Get-GnuInputText -Context $Context -Operand $operand
        if ($null -eq $text) { return }
        $delimiter = "`n"
        if ($zero) { $delimiter = "`0" }
        else { $text = $text.Replace("`r`n", "`n") }
        $files += , @(Split-GnuRecord -Text $text -Separator $delimiter)
    }

    $state = @{
        Context = $Context; Names = $operands; Lines = $files; Next = @(0, 0); Fields = $fields; Separator = $separator
        IgnoreCase = $ignoreCase; Order = $order; Warned = @($false, $false); Unpairable = $false; Previous = @($null, $null)
        Format = $format; Empty = $empty; OutSeparator = $outSeparator; Output = New-Object 'System.Collections.Generic.List[string]'
    }
    if (Test-GnuOption -Context $Context -Key 'header') {
        $headers = @($null, $null)
        for ($k = 0; $k -lt 2; $k++) { if ($files[$k].Count -gt 0) { $headers[$k] = Split-GnuJoinLine -Line $files[$k][0] -Separator $separator; $state.Next[$k] = 1 } }
        if ($null -ne $headers[0] -or $null -ne $headers[1]) { Add-GnuJoinOutput -State $state -Left $headers[0] -Right $headers[1] }
    }
    if ($auto) {
        $auto1 = 0; $auto2 = 0
        if ($files[0].Count -gt 0) { $auto1 = (Split-GnuJoinLine -Line $files[0][0] -Separator $separator).Count }
        if ($files[1].Count -gt 0) { $auto2 = (Split-GnuJoinLine -Line $files[1][0] -Separator $separator).Count }
        $specs = New-Object 'System.Collections.Generic.List[object]'
        $specs.Add(@(0, 0))
        for ($f = 1; $f -le $auto1; $f++) { if ($f -ne $fields[0]) { $specs.Add(@(1, $f)) } }
        for ($f = 1; $f -le $auto2; $f++) { if ($f -ne $fields[1]) { $specs.Add(@(2, $f)) } }
        $state.Format = $specs
    }

    $current = @((Read-GnuJoinLine -State $state -File 0), (Read-GnuJoinLine -State $state -File 1))
    while ($null -ne $current[0] -and $null -ne $current[1] -and -not $state.Context.Done) {
        $diff = Compare-GnuJoinKey -State $state -Left $current[0] -Right $current[1]
        if ($diff -lt 0) {
            if ($printUnpaired[0]) { Add-GnuJoinOutput -State $state -Left $current[0] -Right $null }
            $state.Unpairable = $true
            $current[0] = Read-GnuJoinLine -State $state -File 0
            continue
        }
        if ($diff -gt 0) {
            if ($printUnpaired[1]) { Add-GnuJoinOutput -State $state -Left $null -Right $current[1] }
            $state.Unpairable = $true
            $current[1] = Read-GnuJoinLine -State $state -File 1
            continue
        }
        # Equal keys: collect the run of equal lines in each file, print the cross product.
        $group1 = New-Object 'System.Collections.Generic.List[object]'
        $group1.Add($current[0])
        while ($null -ne ($next = Read-GnuJoinLine -State $state -File 0) -and (Compare-GnuJoinKey -State $state -Left $next -Right $current[1]) -eq 0) { $group1.Add($next) }
        $after1 = $next
        $group2 = New-Object 'System.Collections.Generic.List[object]'
        $group2.Add($current[1])
        while ($null -ne ($next = Read-GnuJoinLine -State $state -File 1) -and (Compare-GnuJoinKey -State $state -Left $current[0] -Right $next) -eq 0) { $group2.Add($next) }
        if ($state.Context.Done) { break }   # --check-order found unsorted input while reading the group
        if ($printPaired) { foreach ($left in $group1) { foreach ($right in $group2) { Add-GnuJoinOutput -State $state -Left $left -Right $right } } }
        $current = @($after1, $next)
    }
    if ($state.Context.Done) { ConvertTo-GnuRecordOutput -Record $state.Output.ToArray() -Zero:$zero; return }

    # The rest of each file: printed if wanted, and read anyway with --check-order.
    for ($k = 0; $k -lt 2; $k++) {
        if ($null -eq $current[$k] -or -not ($printUnpaired[$k] -or $order -eq 'check')) { continue }
        $line = $current[$k]
        while ($null -ne $line) {
            if ($printUnpaired[$k]) {
                if ($k -eq 0) { Add-GnuJoinOutput -State $state -Left $line -Right $null } else { Add-GnuJoinOutput -State $state -Left $null -Right $line }
            }
            $line = Read-GnuJoinLine -State $state -File $k
            if ($state.Context.Done) { break }
        }
    }
    ConvertTo-GnuRecordOutput -Record $state.Output.ToArray() -Zero:$zero
    if (-not $state.Context.Done -and ($state.Warned[0] -or $state.Warned[1])) { Write-GnuError -Context $Context -Message 'input is not in sorted order' }
}

function Read-GnuJoinLine {
    <#
    .SYNOPSIS
    The next line of a file as @{ Text; Fields; Number }, checking the sort order like GNU; $null at the end.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][int]$File)

    $index = $State.Next[$File]
    if ($index -ge $State.Lines[$File].Count) { return $null }
    $State.Next[$File] = $index + 1
    $text = $State.Lines[$File][$index]
    $line = @{ Text = $text; Fields = (Split-GnuJoinLine -Line $text -Separator $State.Separator); Number = $index + 1 }
    $previous = $State.Previous[$File]
    $State.Previous[$File] = $line
    if ($State.Order -eq 'none' -or $null -eq $previous -or $State.Warned[$File]) { return $line }
    if ($State.Order -eq 'default' -and -not $State.Unpairable) { return $line }
    $before = Get-GnuJoinKey -Line $previous -Field $State.Fields[$File]
    $now = Get-GnuJoinKey -Line $line -Field $State.Fields[$File]
    $comparison = [System.StringComparison]::Ordinal
    if ($State.IgnoreCase) { $comparison = [System.StringComparison]::OrdinalIgnoreCase }
    if ([string]::Compare($before, $now, $comparison) -gt 0) {
        $State.Warned[$File] = $true
        Write-GnuError -Context $State.Context -Message "$($State.Names[$File]):$($line.Number): is not sorted: $text"
        if ($State.Order -eq 'check') { $State.Context.Done = $true }
    }
    $line
}

function Get-GnuJoinKey {
    <#
    .SYNOPSIS
    The join field of a line ('' if the line has fewer fields).
    #>
    param([Parameter(Mandatory)][hashtable]$Line, [Parameter(Mandatory)][int]$Field)
    if ($Field -le $Line.Fields.Count) { return $Line.Fields[$Field - 1] }
    ''
}

function Compare-GnuJoinKey {
    <#
    .SYNOPSIS
    Compares the join field of a file-1 line with that of a file-2 line (ordinal, or ordinal ignoring case).
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][hashtable]$Left, [Parameter(Mandatory)][hashtable]$Right)
    $a = Get-GnuJoinKey -Line $Left -Field $State.Fields[0]
    $b = Get-GnuJoinKey -Line $Right -Field $State.Fields[1]
    if ($State.IgnoreCase) { return [string]::Compare($a, $b, [System.StringComparison]::OrdinalIgnoreCase) }
    [string]::CompareOrdinal($a, $b)
}

function Add-GnuJoinOutput {
    <#
    .SYNOPSIS
    Formats one output line from a file-1 and/or file-2 line (either may be $null for unpaired lines).
    #>
    param([Parameter(Mandatory)][hashtable]$State, [AllowNull()][object]$Left, [AllowNull()][object]$Right)

    $sides = @($Left, $Right)
    for ($k = 0; $k -lt 2; $k++) { if ($sides[$k] -is [array]) { $sides[$k] = @{ Fields = $sides[$k] } } }
    $parts = New-Object 'System.Collections.Generic.List[string]'
    if ($null -ne $State.Format) {
        foreach ($spec in $State.Format) {
            $value = $null
            if ($spec[0] -eq 0) {
                $k = 0
                if ($null -eq $sides[0]) { $k = 1 }
                if ($null -ne $sides[$k] -and $State.Fields[$k] -le $sides[$k].Fields.Count) { $value = $sides[$k].Fields[$State.Fields[$k] - 1] }
            }
            else {
                $side = $sides[$spec[0] - 1]
                if ($null -ne $side -and $spec[1] -le $side.Fields.Count) { $value = $side.Fields[$spec[1] - 1] }
            }
            if ([string]::IsNullOrEmpty($value) -and $null -ne $State.Empty) { $value = $State.Empty }
            $parts.Add([string]$value)
        }
    }
    else {
        $k = 0
        if ($null -eq $sides[0]) { $k = 1 }
        # A missing join field prints as empty (or the -e text), like GNU.
        $key = ''
        if ($State.Fields[$k] -le $sides[$k].Fields.Count) { $key = $sides[$k].Fields[$State.Fields[$k] - 1] }
        elseif ($null -ne $State.Empty) { $key = $State.Empty }
        $parts.Add($key)
        for ($side = 0; $side -lt 2; $side++) {
            if ($null -eq $sides[$side]) { continue }
            for ($f = 1; $f -le $sides[$side].Fields.Count; $f++) { if ($f -ne $State.Fields[$side]) { $parts.Add($sides[$side].Fields[$f - 1]) } }
        }
    }
    $State.Output.Add(($parts -join $State.OutSeparator))
}
