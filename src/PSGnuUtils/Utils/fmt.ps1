Register-GnuUtil @{
    Name          = 'fmt'
    Category      = 'Text processing'
    Synopsis      = 'Simple optimal text formatter.'
    Usage         = @('fmt [-WIDTH] [OPTION]... [FILE]...')
    Description   = @(
        'Reformat each paragraph in the FILE(s), writing to standard output.',
        'The option -WIDTH is an abbreviated form of --width=DIGITS.',
        '',
        'With no FILE, or when FILE is -, read standard input.'
    )
    FileOperands  = $true
    NumericOption = 'w'
    Options       = @(
        @{ Short = 'c'; Long = 'crown-margin'; Help = 'preserve indentation of first two lines' }
        @{ Short = 'p'; Long = 'prefix'; Arg = 'STRING'; Help = 'reformat only lines beginning with STRING, reattaching the prefix to reformatted lines' }
        @{ Short = 's'; Long = 'split-only'; Help = 'split long lines, but do not refill' }
        @{ Short = 't'; Long = 'tagged-paragraph'; Help = 'indentation of first line different from second' }
        @{ Short = 'u'; Long = 'uniform-spacing'; Help = 'one space between words, two after sentences' }
        @{ Short = 'w'; Long = 'width'; Arg = 'WIDTH'; Help = 'maximum line width (default of 75 columns)' }
        @{ Short = 'g'; Long = 'goal'; Arg = 'WIDTH'; Help = 'goal width (default of 93% of width)' }
    )
    Notes         = @(
        'PowerShell note: CRLF line endings are read as LF. Paragraphs of more than 1000 words',
        'or 5000 characters are formatted as a whole (GNU formats them in parts).'
    )
}

function Invoke-GnuFmt {
    <#
    .SYNOPSIS
    GNU fmt: fill and join lines into paragraphs of a given width, with GNU's optimal line breaks.

    .DESCRIPTION
    Reformats each paragraph to at most 75 columns (-w WIDTH, -WIDTH), aiming at 93% of the width
    (-g GOAL), with the line-breaking cost model of GNU fmt (sentence ends, short and ragged
    lines). -s only splits, -u normalizes spacing, -c / -t keep first-line indents, -p STRING
    formats only lines with that prefix.
    Enable the GNU name with: Enable-GnuAlias fmt

    .EXAMPLE
    Get-Content README.txt | Invoke-GnuFmt -w 60
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'fmt' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuFmtFile -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function Invoke-GnuFmtFile {
    <#
    .SYNOPSIS
    Implementation of fmt: options, then every FILE.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $maxWidth = 75
    $widthGiven = Test-GnuOption -Context $Context -Key 'width'
    if ($widthGiven) {
        $text = [string](Get-GnuOptionValue -Context $Context -Key 'width')
        if ($text -notmatch '^\d+$') { Write-GnuError -Context $Context -Message "invalid width: '$text'"; return }
        if ([long]$text -gt 2500) { Write-GnuError -Context $Context -Message "invalid width: '$text': Numerical result out of range"; return }
        $maxWidth = [int]$text
    }
    if (Test-GnuOption -Context $Context -Key 'goal') {
        $text = [string](Get-GnuOptionValue -Context $Context -Key 'goal')
        if ($text -notmatch '^\d+$') { Write-GnuError -Context $Context -Message "invalid width: '$text'"; return }
        if ([long]$text -gt $maxWidth) { Write-GnuError -Context $Context -Message "invalid width: '$text': Numerical result out of range"; return }
        $goalWidth = [int]$text
        if (-not $widthGiven) { $maxWidth = $goalWidth + 10 }
    }
    else { $goalWidth = [int][Math]::Floor($maxWidth * 187 / 200) }

    $prefix = ''
    $leadSpace = 0
    $fullLength = 0
    if (Test-GnuOption -Context $Context -Key 'prefix') {
        $raw = [string](Get-GnuOptionValue -Context $Context -Key 'prefix')
        while ($leadSpace -lt $raw.Length -and $raw[$leadSpace] -eq ' ') { $leadSpace++ }
        $raw = $raw.Substring($leadSpace)
        $fullLength = $raw.Length
        $prefix = $raw.TrimEnd(' ')
    }
    $settings = @{
        MaxWidth = $maxWidth; GoalWidth = $goalWidth; Prefix = $prefix; PrefixLead = $leadSpace; PrefixFull = $fullLength
        Crown = Test-GnuOption -Context $Context -Key 'crown-margin'; Tagged = Test-GnuOption -Context $Context -Key 'tagged-paragraph'
        Split = Test-GnuOption -Context $Context -Key 'split-only'; Uniform = Test-GnuOption -Context $Context -Key 'uniform-spacing'
    }
    $operands = @($Context.Operands)
    if ($operands.Count -eq 0) { $operands = @('-') }
    foreach ($operand in $operands) {
        $text = Get-GnuInputText -Context $Context -Operand $operand
        if ($null -eq $text) { continue }
        ConvertTo-GnuOutputLine -Text (Format-GnuFmtText -Text $text.Replace("`r`n", "`n") -Settings $settings)
    }
}

function Format-GnuFmtText {
    <#
    .SYNOPSIS
    A port of GNU fmt.c (get_paragraph, get_line, fmt_paragraph, put_paragraph) for one input text.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [Parameter(Mandatory)][hashtable]$Settings)

    $s = @{
        Text = $Text; Pos = 0; Out = (New-Object System.Text.StringBuilder); Settings = $Settings
        InColumn = 0; OutColumn = 0; NextPrefixIndent = 0; PrefixIndent = 0; FirstIndent = 0; OtherIndent = 0
        Tabs = $false; LastLineLength = 0; Words = $null; NextChar = -1
    }
    $s.NextChar = Get-GnuFmtPrefix -S $s
    while (Get-GnuFmtParagraph -S $s) {
        Optimize-GnuFmtParagraph -S $s
        Write-GnuFmtParagraph -S $s
    }
    $s.Out.ToString()
}

function Read-GnuFmtChar {
    <#
    .SYNOPSIS
    getc(): the next character code, or -1 at the end.
    #>
    param([Parameter(Mandatory)][hashtable]$S)
    if ($S.Pos -ge $S.Text.Length) { return -1 }
    $S.Pos++
    [int]$S.Text[$S.Pos - 1]
}

function Get-GnuFmtSpace {
    <#
    .SYNOPSIS
    get_space(): skips blanks from C, keeping InColumn; returns the first non-blank character.
    #>
    param([Parameter(Mandatory)][hashtable]$S, [Parameter(Mandatory)][int]$C)
    while ($true) {
        if ($C -eq 32) { $S.InColumn++ }
        elseif ($C -eq 9) { $S.Tabs = $true; $S.InColumn = ([Math]::Floor($S.InColumn / 8) + 1) * 8 }
        else { return $C }
        $C = Read-GnuFmtChar -S $S
    }
}

function Get-GnuFmtPrefix {
    <#
    .SYNOPSIS
    get_prefix(): reads the indentation and prefix of a line; returns the first character after them.
    #>
    param([Parameter(Mandatory)][hashtable]$S)
    $S.InColumn = 0
    $c = Get-GnuFmtSpace -S $S -C (Read-GnuFmtChar -S $S)
    $prefix = $S.Settings.Prefix
    if ($prefix.Length -eq 0) {
        $S.NextPrefixIndent = [Math]::Min($S.Settings.PrefixLead, $S.InColumn)
        return $c
    }
    $S.NextPrefixIndent = $S.InColumn
    foreach ($char in $prefix.ToCharArray()) {
        if ($c -ne [int]$char) { return $c }
        $S.InColumn++
        $c = Read-GnuFmtChar -S $S
    }
    Get-GnuFmtSpace -S $S -C $c
}

function Write-GnuFmtSpace {
    <#
    .SYNOPSIS
    put_space(): SPACE columns of blanks, as tabs where the input used tabs.
    #>
    param([Parameter(Mandatory)][hashtable]$S, [Parameter(Mandatory)][int]$Space)
    $target = $S.OutColumn + $Space
    if ($S.Tabs) {
        $tabTarget = [Math]::Floor($target / 8) * 8
        if ($S.OutColumn + 1 -lt $tabTarget) {
            while ($S.OutColumn -lt $tabTarget) {
                [void]$S.Out.Append("`t")
                $S.OutColumn = ([Math]::Floor($S.OutColumn / 8) + 1) * 8
            }
        }
    }
    while ($S.OutColumn -lt $target) { [void]$S.Out.Append(' '); $S.OutColumn++ }
}

function Copy-GnuFmtRest {
    <#
    .SYNOPSIS
    copy_rest(): copies a line that is not part of a paragraph; returns the newline or -1 that ends it.
    #>
    param([Parameter(Mandatory)][hashtable]$S, [Parameter(Mandatory)][int]$C)
    $S.OutColumn = 0
    $prefix = $S.Settings.Prefix
    if ($S.InColumn -gt $S.NextPrefixIndent -or ($C -ne 10 -and $C -ne -1)) {
        Write-GnuFmtSpace -S $S -Space $S.NextPrefixIndent
        $k = 0
        while ($S.OutColumn -ne $S.InColumn -and $k -lt $prefix.Length) { [void]$S.Out.Append($prefix[$k]); $k++; $S.OutColumn++ }
        if ($C -ne -1 -and $C -ne 10) { Write-GnuFmtSpace -S $S -Space ($S.InColumn - $S.OutColumn) }
        if ($C -eq -1 -and $S.InColumn -ge $S.NextPrefixIndent + $prefix.Length) { [void]$S.Out.Append("`n") }
    }
    while ($C -ne 10 -and $C -ne -1) {
        [void]$S.Out.Append([char]$C)
        $C = Read-GnuFmtChar -S $S
    }
    $C
}

function Test-GnuFmtSameParagraph {
    <#
    .SYNOPSIS
    same_paragraph(): could the line starting with C belong to the current paragraph?
    #>
    param([Parameter(Mandatory)][hashtable]$S, [Parameter(Mandatory)][int]$C)
    $S.NextPrefixIndent -eq $S.PrefixIndent -and $S.InColumn -ge $S.NextPrefixIndent + $S.Settings.PrefixFull -and $C -ne 10 -and $C -ne -1
}

function Set-GnuFmtOtherIndent {
    <#
    .SYNOPSIS
    set_other_indent(): the indentation of the lines after the first.
    #>
    param([Parameter(Mandatory)][hashtable]$S, [Parameter(Mandatory)][bool]$Same)
    if ($S.Settings.Split) { $S.OtherIndent = $S.FirstIndent }
    elseif ($S.Settings.Crown) {
        if ($Same) { $S.OtherIndent = $S.InColumn } else { $S.OtherIndent = $S.FirstIndent }
    }
    elseif ($S.Settings.Tagged) {
        if ($Same -and $S.InColumn -ne $S.FirstIndent) { $S.OtherIndent = $S.InColumn }
        elseif ($S.OtherIndent -eq $S.FirstIndent) {
            if ($S.FirstIndent -eq 0) { $S.OtherIndent = 3 } else { $S.OtherIndent = 0 }
        }
    }
    else { $S.OtherIndent = $S.FirstIndent }
}

function Get-GnuFmtParagraph {
    <#
    .SYNOPSIS
    get_paragraph(): copies blank and non-prefixed lines, then reads one paragraph into words. $false at the end.
    #>
    param([Parameter(Mandatory)][hashtable]$S)

    $S.LastLineLength = 0
    $c = $S.NextChar
    while ($c -eq 10 -or $c -eq -1 -or $S.NextPrefixIndent -lt $S.Settings.PrefixLead -or $S.InColumn -lt $S.NextPrefixIndent + $S.Settings.PrefixFull) {
        $c = Copy-GnuFmtRest -S $S -C $c
        if ($c -eq -1) { $S.NextChar = -1; return $false }
        [void]$S.Out.Append("`n")
        $c = Get-GnuFmtPrefix -S $S
    }
    $S.PrefixIndent = $S.NextPrefixIndent
    $S.FirstIndent = $S.InColumn
    $S.Words = New-Object 'System.Collections.Generic.List[hashtable]'
    $c = Read-GnuFmtLine -S $S -C $c
    Set-GnuFmtOtherIndent -S $S -Same (Test-GnuFmtSameParagraph -S $S -C $c)

    if ($S.Settings.Split) { }
    elseif ($S.Settings.Crown) {
        if (Test-GnuFmtSameParagraph -S $S -C $c) {
            do { $c = Read-GnuFmtLine -S $S -C $c } while ((Test-GnuFmtSameParagraph -S $S -C $c) -and $S.InColumn -eq $S.OtherIndent)
        }
    }
    elseif ($S.Settings.Tagged) {
        if ((Test-GnuFmtSameParagraph -S $S -C $c) -and $S.InColumn -ne $S.FirstIndent) {
            do { $c = Read-GnuFmtLine -S $S -C $c } while ((Test-GnuFmtSameParagraph -S $S -C $c) -and $S.InColumn -eq $S.OtherIndent)
        }
    }
    else {
        while ((Test-GnuFmtSameParagraph -S $S -C $c) -and $S.InColumn -eq $S.OtherIndent) { $c = Read-GnuFmtLine -S $S -C $c }
    }
    $last = $S.Words[$S.Words.Count - 1]
    $last.Period = $true
    $last.Final = $true
    $S.NextChar = $c
    $true
}

function Read-GnuFmtLine {
    <#
    .SYNOPSIS
    get_line(): splits one line into words (with punctuation and sentence-end flags); returns the next line's first character.
    #>
    param([Parameter(Mandatory)][hashtable]$S, [Parameter(Mandatory)][int]$C)

    do {
        $builder = New-Object System.Text.StringBuilder
        do {
            [void]$builder.Append([char]$C)
            $C = Read-GnuFmtChar -S $S
        } while ($C -ne -1 -and -not [char]::IsWhiteSpace([char]$C))
        $text = $builder.ToString()
        $S.InColumn += $text.Length
        $close = $text.Length - 1
        while ($close -gt 0 -and ")]'`"".IndexOf($text[$close]) -ge 0) { $close-- }
        $word = @{
            Text = $text; Length = $text.Length; Space = 0; Final = $false; LineLength = 0; BestCost = [long]0; NextBreak = 0
            Paren = "(['``""".IndexOf($text[0]) -ge 0
            Punct = [char]::IsPunctuation($text[$text.Length - 1]) -or [char]::IsSymbol($text[$text.Length - 1])
            Period = '.?!'.IndexOf($text[$close]) -ge 0
        }
        $start = $S.InColumn
        $C = Get-GnuFmtSpace -S $S -C $C
        $word.Space = $S.InColumn - $start
        $word.Final = ($C -eq -1) -or ($word.Period -and ($C -eq 10 -or $word.Space -gt 1))
        if ($C -eq 10 -or $C -eq -1 -or $S.Settings.Uniform) {
            if ($word.Final) { $word.Space = 2 } else { $word.Space = 1 }
        }
        $S.Words.Add($word)
    } while ($C -ne 10 -and $C -ne -1)
    Get-GnuFmtPrefix -S $S
}

function Get-GnuFmtBaseCost {
    <#
    .SYNOPSIS
    base_cost(): the cost of starting a line with word Index (sentence, punctuation, widow and orphan rules).
    #>
    param([Parameter(Mandatory)][hashtable]$S, [Parameter(Mandatory)][int]$Index)
    $words = $S.Words
    $cost = [long]4900   # LINE_COST = 70^2
    if ($Index -gt 0) {
        $previous = $words[$Index - 1]
        if ($previous.Period) {
            if ($previous.Final) { $cost -= 2500 } else { $cost += 360000 }   # SENTENCE_BONUS, NOBREAK_COST
        }
        elseif ($previous.Punct) { $cost -= 1600 }   # PUNCT_BONUS
        elseif ($Index -gt 1 -and $words[$Index - 2].Final) {
            $cost += [long][Math]::Floor(40000 / ($previous.Length + 2))   # WIDOW_COST = EQUIV(200) / (n + 2)
        }
    }
    $word = $words[$Index]
    if ($word.Paren) { $cost -= 1600 }   # PAREN_BONUS
    elseif ($word.Final) {
        $cost += [long][Math]::Floor(22500 / ($word.Length + 2))   # ORPHAN_COST = EQUIV(150) / (n + 2)
    }
    $cost
}

function Get-GnuFmtLineCost {
    <#
    .SYNOPSIS
    line_cost(): the cost of a line of length Length followed by word Next.
    #>
    param([Parameter(Mandatory)][hashtable]$S, [Parameter(Mandatory)][int]$Next, [Parameter(Mandatory)][long]$Length)
    $count = $S.Words.Count
    if ($Next -eq $count) { return [long]0 }
    $n = [long]($S.Settings.GoalWidth - $Length)
    $cost = (10 * $n) * (10 * $n)   # SHORT_COST
    if ($S.Words[$Next].NextBreak -ne $count) {
        $n = $Length - $S.Words[$Next].LineLength
        $cost += [long][Math]::Floor(((10 * $n) * (10 * $n)) / 2)   # RAGGED_COST
    }
    $cost
}

function Optimize-GnuFmtParagraph {
    <#
    .SYNOPSIS
    fmt_paragraph(): chooses the line breaks with the lowest total cost (dynamic programming from the end).
    #>
    param([Parameter(Mandatory)][hashtable]$S)

    $words = $S.Words
    $count = $words.Count
    $maxWidth = $S.Settings.MaxWidth
    $bestCosts = New-Object long[] ($count + 1)
    for ($start = $count - 1; $start -ge 0; $start--) {
        $best = [long]::MaxValue
        if ($start -eq 0) { $length = [long]$S.FirstIndent } else { $length = [long]$S.OtherIndent }
        $w = $start
        $length += $words[$w].Length
        do {
            $w++
            $cost = (Get-GnuFmtLineCost -S $S -Next $w -Length $length) + $bestCosts[$w]
            if ($cost -lt $best) {
                $best = $cost
                $words[$start].NextBreak = $w
                $words[$start].LineLength = $length
            }
            if ($w -eq $count) { break }
            $length += $words[$w - 1].Space + $words[$w].Length
        } while ($length -lt $maxWidth)
        $bestCosts[$start] = $best + (Get-GnuFmtBaseCost -S $S -Index $start)
    }
}

function Write-GnuFmtParagraph {
    <#
    .SYNOPSIS
    put_paragraph() / put_line(): writes the lines with prefix and indentation.
    #>
    param([Parameter(Mandatory)][hashtable]$S)
    $words = $S.Words
    $index = 0
    $indent = $S.FirstIndent
    while ($index -lt $words.Count) {
        $S.OutColumn = 0
        Write-GnuFmtSpace -S $S -Space $S.PrefixIndent
        [void]$S.Out.Append($S.Settings.Prefix)
        $S.OutColumn += $S.Settings.Prefix.Length
        Write-GnuFmtSpace -S $S -Space ($indent - $S.OutColumn)
        $end = $words[$index].NextBreak
        for ($w = $index; $w -lt $end; $w++) {
            [void]$S.Out.Append($words[$w].Text)
            $S.OutColumn += $words[$w].Length
            if ($w -lt $end - 1) { Write-GnuFmtSpace -S $S -Space $words[$w].Space }
        }
        $S.LastLineLength = $S.OutColumn
        [void]$S.Out.Append("`n")
        $index = $end
        $indent = $S.OtherIndent
    }
}
