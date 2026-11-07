Register-GnuUtil @{
    Name            = 'tac'
    Category        = 'Viewing file contents'
    Synopsis        = 'Concatenate and print files in reverse.'
    Usage           = @('tac [OPTION]... [FILE]...')
    Description     = @('Write each FILE to standard output, last line first.', '', 'With no FILE, or when FILE is -, read standard input.')
    FileOperands    = $true
    OpenErrorFormat = "failed to open '{0}' for reading: {1}"
    ReadErrorFormat = "{0}: read error: {1}"
    Options         = @(
        @{ Short = 'b'; Long = 'before'; Help = 'attach the separator before instead of after' }
        @{ Short = 'r'; Long = 'regex'; Help = 'interpret the separator as a regular expression' }
        @{ Short = 's'; Long = 'separator'; Arg = 'STRING'; Help = 'use STRING as the separator instead of newline' }
    )
    Notes           = @('PowerShell note: -r uses .NET regular expression syntax.')
}

function Invoke-GnuTac {
    <#
    .SYNOPSIS
    GNU tac: print files in reverse (last line first).

    .DESCRIPTION
    Reverses the records of each FILE. Records end with a newline by default, or with any
    STRING (-s) or regular expression (-r -s). With -b the separator starts a record.
    Like GNU tac, a final line without a newline is joined to the next one.
    Enable the GNU name with: Enable-GnuUtil tac

    .EXAMPLE
    Invoke-GnuTac app.log

    .EXAMPLE
    1..3 | Invoke-GnuTac

    3
    2
    1
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'tac' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) {
            $separator = "`n"
            if (Test-GnuOption -Context $ctx -Key 'separator') { $separator = [string](Get-GnuOptionValue -Context $ctx -Key 'separator') }
            if ($separator -eq '') {
                Write-GnuError -Context $ctx -Message 'separator cannot be empty'
            }
            else {
                $pattern = [regex]::Escape($separator)
                if (Test-GnuOption -Context $ctx -Key 'regex') { $pattern = $separator }
                $before = Test-GnuOption -Context $ctx -Key 'before'

                $operands = @($ctx.Operands)
                if ($operands.Count -eq 0) { $operands = @('-') }
                $output = New-Object System.Text.StringBuilder
                foreach ($operand in $operands) {
                    $text = Get-GnuInputText -Context $ctx -Operand $operand
                    if ($null -eq $text) { continue }
                    [void]$output.Append((ConvertTo-GnuReversedRecord -Text $text -Pattern $pattern -Before:$before))
                }
                ConvertTo-GnuOutputLine -Text $output.ToString()
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}

function ConvertTo-GnuReversedRecord {
    <#
    .SYNOPSIS
    Reverses the separator-delimited records of a text (tac semantics).
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Pattern,
        [switch]$Before
    )

    if ($Text -eq '') { return '' }
    $records = New-Object 'System.Collections.Generic.List[string]'
    $start = 0
    foreach ($match in [regex]::Matches($Text, $Pattern)) {
        if ($match.Length -eq 0) { continue }
        if ($Before) {
            if ($match.Index -gt $start) { $records.Add($Text.Substring($start, $match.Index - $start)) }
            $start = $match.Index
        }
        else {
            $end = $match.Index + $match.Length
            $records.Add($Text.Substring($start, $end - $start))
            $start = $end
        }
    }
    if ($start -lt $Text.Length) { $records.Add($Text.Substring($start)) }
    $records.Reverse()
    -join $records
}
