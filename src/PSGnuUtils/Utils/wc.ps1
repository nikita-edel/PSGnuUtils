Register-GnuUtil @{
    Name         = 'wc'
    Category     = 'Text processing'
    Synopsis     = 'Print newline, word, and byte counts for each file.'
    Usage        = @('wc [OPTION]... [FILE]...', 'wc [OPTION]... --files0-from=F')
    Description  = @(
        'Print newline, word, and byte counts for each FILE, and a total line if',
        'more than one FILE is specified.  A word is a nonempty sequence of non white',
        'space delimited by white space characters or by start or end of input.',
        '',
        'With no FILE, or when FILE is -, read standard input.',
        '',
        'The options below may be used to select which counts are printed, always in',
        'the following order: newline, word, character, byte, maximum line length.'
    )
    FileOperands = $true
    Options      = @(
        @{ Short = 'c'; Long = 'bytes'; Help = 'print the byte counts' }
        @{ Short = 'm'; Long = 'chars'; Help = 'print the character counts' }
        @{ Short = 'l'; Long = 'lines'; Help = 'print the newline counts' }
        @{ Long = 'files0-from'; Arg = 'F'; Help = 'read input from the files specified by NUL-terminated names in file F; If F is - then read names from standard input' }
        @{ Short = 'L'; Long = 'max-line-length'; Help = 'print the maximum display width' }
        @{ Short = 'w'; Long = 'words'; Help = 'print the word counts' }
        @{ Long = 'total'; Arg = 'WHEN'; Help = 'when to print a line with total counts; WHEN can be: auto, always, only, never' }
    )
    Notes        = @('PowerShell note: pipeline input counts as UTF-8 text with a LF after every line.')
}

function Invoke-GnuWc {
    <#
    .SYNOPSIS
    GNU wc: print newline, word, character and byte counts.

    .DESCRIPTION
    Counts lines (newline characters), words, characters, bytes and the maximum line width of
    each FILE ('-' or no FILE = pipeline input) and prints a total line for several files.
    Enable the GNU name with: Enable-GnuAlias wc

    .EXAMPLE
    Invoke-GnuWc -l *.ps1

    .EXAMPLE
    Get-ChildItem | Invoke-GnuWc -l

    Counts the files in the current directory.
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'wc' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuWordCount -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function Measure-GnuText {
    <#
    .SYNOPSIS
    Computes the wc counts of one input.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)

    $text = $script:GnuUtf8.GetString($Bytes)
    $maxWidth = 0
    foreach ($line in [regex]::Split($text, "[`r`n`f]")) {
        $width = 0
        foreach ($char in $line.ToCharArray()) {
            if ($char -eq "`t") { $width += 8 - ($width % 8) }
            elseif ([char]::IsLowSurrogate($char)) { continue }
            elseif ([int]$char -ge 32) { $width++ }
        }
        if ($width -gt $maxWidth) { $maxWidth = $width }
    }

    @{
        lines             = [long]($text.Length - $text.Replace("`n", '').Length)
        words             = [long][regex]::Matches($text, '\S+').Count
        chars             = [long]($text.Length - [regex]::Matches($text, '[\uDC00-\uDFFF]').Count)
        bytes             = [long]$Bytes.Length
        'max-line-length' = [long]$maxWidth
    }
}

function Invoke-GnuWordCount {
    <#
    .SYNOPSIS
    Implementation of wc.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $total = [string](Get-GnuOptionValue -Context $Context -Key 'total' -Default 'auto')
    if (@('auto', 'always', 'only', 'never') -notcontains $total) {
        Write-GnuUsageError -Context $Context -Message "invalid argument '$total' for '--total'`nValid arguments are: 'auto', 'always', 'only', 'never'"
        return
    }

    $keys = @(@('lines', 'words', 'chars', 'bytes', 'max-line-length') | Where-Object { Test-GnuOption -Context $Context -Key $_ })
    if ($keys.Count -eq 0) { $keys = @('lines', 'words', 'bytes') }

    $operands = @($Context.Operands)
    $showNames = $true
    if (Test-GnuOption -Context $Context -Key 'files0-from') {
        if ($operands.Count -gt 0) {
            Write-GnuUsageError -Context $Context -Message "extra operand '$($operands[0])'`nfile operands cannot be combined with --files0-from"
            return
        }
        $listName = [string](Get-GnuOptionValue -Context $Context -Key 'files0-from')
        $listText = Get-GnuInputText -Context $Context -Operand $listName
        if ($null -eq $listText) { return }
        $operands = @(Split-GnuRecord -Text $listText -Separator "`0")
    }
    elseif ($operands.Count -eq 0) {
        $operands = @('-')
        $showNames = $false
    }

    $results = New-Object 'System.Collections.Generic.List[hashtable]'
    $minimumWidth = 1
    $regularTotal = [long]0
    foreach ($operand in $operands) {
        $bytes = Get-GnuInputBytes -Context $Context -Operand $operand
        if ($null -eq $bytes) { continue }
        if ($operand -eq '-') { $minimumWidth = 7 } else { $regularTotal += $bytes.Length }
        $results.Add(@{ Name = $operand; Counts = (Measure-GnuText -Bytes $bytes) })
    }

    $width = 1
    if ($total -ne 'only' -and -not ($keys.Count -eq 1 -and $operands.Count -eq 1)) {
        $width = [Math]::Max($minimumWidth, ([string]$regularTotal).Length)
    }

    $sum = @{}
    foreach ($key in $keys) { $sum[$key] = [long]0 }
    foreach ($result in $results) {
        foreach ($key in $keys) {
            if ($key -eq 'max-line-length') { $sum[$key] = [Math]::Max($sum[$key], $result.Counts[$key]) }
            else { $sum[$key] += $result.Counts[$key] }
        }
        if ($total -ne 'only') {
            $line = ($keys | ForEach-Object { ([string]$result.Counts[$_]).PadLeft($width) }) -join ' '
            if ($showNames) { $line += " $($result.Name)" }
            $line
        }
    }

    $printTotal = $total -eq 'always' -or $total -eq 'only' -or ($total -eq 'auto' -and $operands.Count -gt 1)
    if ($printTotal) {
        $line = ($keys | ForEach-Object { ([string]$sum[$_]).PadLeft($width) }) -join ' '
        if ($total -ne 'only') { $line += ' total' }
        $line
    }
}
