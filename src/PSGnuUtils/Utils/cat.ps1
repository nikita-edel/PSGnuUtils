Register-GnuUtil @{
    Name         = 'cat'
    Category     = 'Viewing file contents'
    Synopsis     = 'Concatenate files and print on the standard output.'
    Usage        = @('cat [OPTION]... [FILE]...')
    Description  = @('Concatenate FILE(s) to standard output.', '', 'With no FILE, or when FILE is -, read standard input.')
    FileOperands = $true
    Options      = @(
        @{ Short = 'A'; Long = 'show-all'; Sets = @{ 'show-nonprinting' = 1; 'show-ends' = 1; 'show-tabs' = 1 }; Help = 'equivalent to -vET' }
        @{ Short = 'b'; Long = 'number-nonblank'; Help = 'number nonempty output lines, overrides -n' }
        @{ Short = 'e'; Sets = @{ 'show-nonprinting' = 1; 'show-ends' = 1 }; Help = 'equivalent to -vE' }
        @{ Short = 'E'; Long = 'show-ends'; Help = 'display $ at end of each line' }
        @{ Short = 'n'; Long = 'number'; Help = 'number all output lines' }
        @{ Short = 's'; Long = 'squeeze-blank'; Help = 'suppress repeated empty output lines' }
        @{ Short = 't'; Sets = @{ 'show-nonprinting' = 1; 'show-tabs' = 1 }; Help = 'equivalent to -vT' }
        @{ Short = 'T'; Long = 'show-tabs'; Help = 'display TAB characters as ^I' }
        @{ Short = 'u'; Help = '(ignored)' }
        @{ Short = 'v'; Long = 'show-nonprinting'; Help = 'use ^ and M- notation, except for LFD and TAB' }
    )
    Notes        = @('PowerShell note: pipeline input is read as text lines; files are read as UTF-8.')
}

function Invoke-GnuCat {
    <#
    .SYNOPSIS
    GNU cat: concatenate files and print them.

    .DESCRIPTION
    Prints every FILE ('-' or no FILE = pipeline input) as text lines. Supports numbering
    (-n, -b), squeezing blank lines (-s) and making invisible characters visible (-A, -v, -E, -T).
    Pipeline input is processed line by line as it arrives.
    Enable the GNU name with: Enable-GnuUtil cat (replaces the cat -> Get-Content alias).

    .EXAMPLE
    Invoke-GnuCat -n notes.txt

    .EXAMPLE
    Get-Content file.txt | Invoke-GnuCat -A

    Shows tabs as ^I, line ends as $ and control characters in ^X notation.
    #>
    begin {
        $ctx = Initialize-GnuUtil -Name 'cat' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput
        if (-not $ctx.Done) {
            $cat = New-GnuCatState -Context $ctx
            $stream = Test-GnuStdinOnly -Context $ctx
        }
    }
    process {
        if ($ctx.Done) { return }
        if ($stream) {
            foreach ($line in @(ConvertFrom-GnuPipelineItem -Context $ctx -InputObject $_)) { Format-GnuCatLine -State $cat -Line $line -Terminated $true }
        }
        else {
            Add-GnuPipelineInput -Context $ctx -InputObject $_
        }
    }
    end {
        if (-not $ctx.Done) {
            if ($stream) {
                foreach ($line in @(Complete-GnuPipelineInput -Context $ctx)) { Format-GnuCatLine -State $cat -Line $line -Terminated $true }
            }
            else {
                $operands = @($ctx.Operands)
                if ($operands.Count -eq 0) { $operands = @('-') }
                foreach ($operand in $operands) {
                    if ($cat.Raw -and $operand -ne '-') {
                        # Raw mode keeps CR characters and knows whether the last line was terminated.
                        $text = Get-GnuInputText -Context $ctx -Operand $operand
                        if ($null -eq $text -or [string]::IsNullOrEmpty($text)) { continue }
                        $segments = $text.Split([char]10)
                        $terminated = $text.EndsWith("`n", [System.StringComparison]::Ordinal)
                        $count = $segments.Length
                        if ($terminated) { $count-- }
                        for ($i = 0; $i -lt $count; $i++) {
                            Format-GnuCatLine -State $cat -Line $segments[$i] -Terminated (($i -lt $count - 1) -or $terminated)
                        }
                    }
                    else {
                        foreach ($line in @(Get-GnuInputLine -Context $ctx -Operand $operand)) { Format-GnuCatLine -State $cat -Line $line -Terminated $true }
                    }
                }
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}

function New-GnuCatState {
    <#
    .SYNOPSIS
    Formatting state of one cat invocation (line counter and squeeze tracking carry across files).
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $state = @{
        NumberAll       = Test-GnuOption -Context $Context -Key 'number'
        NumberNonBlank  = Test-GnuOption -Context $Context -Key 'number-nonblank'
        Squeeze         = Test-GnuOption -Context $Context -Key 'squeeze-blank'
        ShowEnds        = Test-GnuOption -Context $Context -Key 'show-ends'
        ShowTabs        = Test-GnuOption -Context $Context -Key 'show-tabs'
        ShowNonprinting = Test-GnuOption -Context $Context -Key 'show-nonprinting'
        Number          = [long]0
        PreviousBlank   = $false
        Raw             = $false
    }
    $state.Raw = $state.ShowEnds -or $state.ShowNonprinting
    $state
}

function Format-GnuCatLine {
    <#
    .SYNOPSIS
    Formats one cat line, or returns nothing if it is squeezed away.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Line,
        [Parameter(Mandatory)][bool]$Terminated
    )

    $blank = $Line.Length -eq 0
    if ($State.Squeeze -and $blank -and $State.PreviousBlank) { return }
    $State.PreviousBlank = $blank

    $text = $Line
    if ($State.ShowNonprinting -or $State.ShowTabs) {
        $text = ConvertTo-GnuVisibleText -Text $text -Nonprinting:$State.ShowNonprinting -Tabs:$State.ShowTabs
    }
    if ($State.ShowEnds -and $Terminated) { $text += '$' }

    if ($State.NumberNonBlank) {
        if (-not $blank) {
            $State.Number++
            $text = $State.Number.ToString([System.Globalization.CultureInfo]::InvariantCulture).PadLeft(6) + "`t" + $text
        }
    }
    elseif ($State.NumberAll) {
        $State.Number++
        $text = $State.Number.ToString([System.Globalization.CultureInfo]::InvariantCulture).PadLeft(6) + "`t" + $text
    }
    $text
}

function ConvertTo-GnuVisibleText {
    <#
    .SYNOPSIS
    cat -v / -T rendering: ^X for control characters, ^? for DEL, M- notation for bytes >= 128, ^I for TAB (with -T).
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [switch]$Nonprinting,
        [switch]$Tabs
    )

    $builder = New-Object System.Text.StringBuilder
    $i = 0
    while ($i -lt $Text.Length) {
        $char = $Text[$i]
        $code = [int]$char
        $i++
        if ($code -eq 9) {
            if ($Tabs) { [void]$builder.Append('^I') } else { [void]$builder.Append($char) }
            continue
        }
        if (-not $Nonprinting) { [void]$builder.Append($char); continue }

        if ($code -lt 32) { [void]$builder.Append('^').Append([char]($code + 64)); continue }
        if ($code -eq 127) { [void]$builder.Append('^?'); continue }
        if ($code -lt 128) { [void]$builder.Append($char); continue }

        $chunk = [string]$char
        if ([char]::IsHighSurrogate($char) -and $i -lt $Text.Length -and [char]::IsLowSurrogate($Text[$i])) {
            $chunk += $Text[$i]
            $i++
        }
        foreach ($byte in $script:GnuUtf8.GetBytes($chunk)) {
            $low = $byte - 128
            if ($low -lt 32) { [void]$builder.Append('M-^').Append([char]($low + 64)) }
            elseif ($low -eq 127) { [void]$builder.Append('M-^?') }
            else { [void]$builder.Append('M-').Append([char]$low) }
        }
    }
    $builder.ToString()
}
