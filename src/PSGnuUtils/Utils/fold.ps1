Register-GnuUtil @{
    Name          = 'fold'
    Category      = 'Viewing file contents'
    Synopsis      = 'Wrap each input line to fit in specified width.'
    Usage         = @('fold [OPTION]... [FILE]...')
    Description   = @('Wrap input lines in each FILE, writing to standard output.', '', 'With no FILE, or when FILE is -, read standard input.')
    FileOperands  = $true
    NumericOption = 'w'
    Options       = @(
        @{ Short = 'b'; Long = 'bytes'; Help = 'count bytes rather than columns' }
        @{ Short = 's'; Long = 'spaces'; Help = 'break at spaces' }
        @{ Short = 'w'; Long = 'width'; Arg = 'WIDTH'; Help = 'use WIDTH columns instead of 80' }
    )
    Notes         = @('PowerShell note: -b counts characters (UTF-16 code units), not UTF-8 bytes.')
}

function Invoke-GnuFold {
    <#
    .SYNOPSIS
    GNU fold: wrap each input line to fit in a width.

    .DESCRIPTION
    Breaks lines longer than WIDTH (default 80) columns. Tabs advance to the next multiple of 8,
    backspace moves one column back, carriage return goes to column 0 (unless -b). With -s
    lines are broken after the last blank that fits. fold -20 is short for fold -w 20.
    Enable the GNU name with: Enable-GnuUtil fold

    .EXAMPLE
    Get-Content README.md | Invoke-GnuFold -s -w 60
    #>
    begin {
        $ctx = Initialize-GnuUtil -Name 'fold' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput
        if (-not $ctx.Done) {
            $width = 80
            if (Test-GnuOption -Context $ctx -Key 'width') {
                $text = [string](Get-GnuOptionValue -Context $ctx -Key 'width')
                if ($text -notmatch '^\d+$' -or [decimal]$text -lt 1 -or [decimal]$text -gt [int]::MaxValue) {
                    Write-GnuError -Context $ctx -Message "invalid number of columns: '$text'"
                    $ctx.Done = $true
                }
                else {
                    $width = [int]$text
                }
            }
            $fold = @{ Width = $width; Bytes = (Test-GnuOption -Context $ctx -Key 'bytes'); Spaces = (Test-GnuOption -Context $ctx -Key 'spaces') }
            $stream = Test-GnuStdinOnly -Context $ctx
        }
    }
    process {
        if ($ctx.Done) { return }
        if ($stream) {
            foreach ($line in @(ConvertFrom-GnuPipelineItem -Context $ctx -InputObject $_)) { Split-GnuFoldLine -Line $line @fold }
        }
        else {
            Add-GnuPipelineInput -Context $ctx -InputObject $_
        }
    }
    end {
        if (-not $ctx.Done) {
            if ($stream) {
                foreach ($line in @(Complete-GnuPipelineInput -Context $ctx)) { Split-GnuFoldLine -Line $line @fold }
            }
            else {
                $operands = @($ctx.Operands)
                if ($operands.Count -eq 0) { $operands = @('-') }
                foreach ($operand in $operands) {
                    foreach ($line in @(Get-GnuInputLine -Context $ctx -Operand $operand)) { Split-GnuFoldLine -Line $line @fold }
                }
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}

function Get-GnuFoldColumn {
    <#
    .SYNOPSIS
    The column after printing Char at Column (GNU fold's adjust_column).
    #>
    param([int]$Column, [char]$Char, [bool]$Bytes)

    if ($Bytes) { return $Column + 1 }
    switch ([int]$Char) {
        8 { if ($Column -gt 0) { return $Column - 1 } else { return 0 } }
        13 { return 0 }
        9 { return $Column + 8 - ($Column % 8) }
    }
    $Column + 1
}

function Split-GnuFoldLine {
    <#
    .SYNOPSIS
    Folds one input line into output lines.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Line,
        [int]$Width,
        [bool]$Bytes,
        [bool]$Spaces
    )

    $buffer = New-Object System.Text.StringBuilder
    $column = 0
    $index = 0
    while ($index -lt $Line.Length) {
        $char = $Line[$index]
        $next = Get-GnuFoldColumn -Column $column -Char $char -Bytes $Bytes
        if ($next -gt $Width -and $buffer.Length -gt 0) {
            if ($Spaces) {
                $text = $buffer.ToString()
                $blank = $text.LastIndexOfAny([char[]]@(' ', "`t"))
                if ($blank -ge 0) {
                    $text.Substring(0, $blank + 1)
                    $rest = $text.Substring($blank + 1)
                    [void]$buffer.Clear().Append($rest)
                    $column = 0
                    foreach ($restChar in $rest.ToCharArray()) { $column = Get-GnuFoldColumn -Column $column -Char $restChar -Bytes $Bytes }
                    continue
                }
            }
            $buffer.ToString()
            [void]$buffer.Clear()
            $column = 0
            continue
        }
        [void]$buffer.Append($char)
        $column = $next
        $index++
    }
    $buffer.ToString()
}
