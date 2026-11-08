Register-GnuUtil @{
    Name         = 'echo'
    Category     = 'Shell helpers'
    Synopsis     = 'Display a line of text.'
    Usage        = @('echo [SHORT-OPTION]... [STRING]...', 'echo LONG-OPTION')
    Description  = @('Echo the STRING(s) to standard output.')
    RawArguments = $true
    Options      = @(
        @{ Short = 'n'; Help = 'do not output the trailing newline' }
        @{ Short = 'e'; Help = 'enable interpretation of backslash escapes' }
        @{ Short = 'E'; Help = 'disable interpretation of backslash escapes (default)' }
    )
    Notes        = @(
        'If -e is in effect, the following sequences are recognized:',
        '',
        '  \\      backslash',
        '  \a      alert (BEL)',
        '  \b      backspace',
        '  \c      produce no further output',
        '  \e      escape',
        '  \f      form feed',
        '  \n      new line',
        '  \r      carriage return',
        '  \t      horizontal tab',
        '  \v      vertical tab',
        '  \0NNN   byte with octal value NNN (1 to 3 digits)',
        '  \xHH    byte with hexadecimal value HH (1 to 2 digits)',
        '',
        'Options are only recognized before the first STRING, and only if every character is n, e or E.',
        'PowerShell note: the output is a stream of lines; -n cannot suppress the console newline.'
    )
}

function Invoke-GnuEcho {
    <#
    .SYNOPSIS
    GNU echo: display a line of text.

    .DESCRIPTION
    Joins the operands with spaces. Leading arguments made only of -n, -e and -E are options:
    -n suppresses the trailing newline, -e interprets backslash escapes (\n, \t, \x41, \0101, \c ...).
    Enable the GNU name with: Enable-GnuAlias echo (replaces the echo -> Write-Output alias).

    .EXAMPLE
    Invoke-GnuEcho -e 'a\tb\nc'

    a	b
    c
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'echo' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            $operands = @($ctx.Operands)
            $index = 0
            $newline = $true
            $escapes = $false
            while ($index -lt $operands.Count -and $operands[$index] -cmatch '^-[neE]+$') {
                foreach ($flag in $operands[$index].Substring(1).ToCharArray()) {
                    switch -CaseSensitive ([string]$flag) {
                        'n' { $newline = $false }
                        'e' { $escapes = $true }
                        'E' { $escapes = $false }
                    }
                }
                $index++
            }

            $text = ''
            if ($index -lt $operands.Count) { $text = $operands[$index..($operands.Count - 1)] -join ' ' }
            if ($escapes) {
                $converted = ConvertFrom-GnuEscape -Text $text
                $text = $converted.Text
                if ($converted.Stop) { $newline = $false }
            }
            if ($newline) { $text += "`n" }
            ConvertTo-GnuOutputLine -Text $text
        }
        Complete-GnuUtil -Context $ctx
    }
}
