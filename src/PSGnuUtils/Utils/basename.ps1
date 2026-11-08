Register-GnuUtil @{
    Name        = 'basename'
    Category    = 'Paths and names'
    Synopsis    = 'Strip directory and suffix from file names.'
    Usage       = @('basename NAME [SUFFIX]', 'basename OPTION... NAME...')
    Description = @('Print NAME with any leading directory components removed.', 'If specified, also remove a trailing SUFFIX.')
    Options     = @(
        @{ Short = 'a'; Long = 'multiple'; Help = 'support multiple arguments and treat each as a NAME' }
        @{ Short = 's'; Long = 'suffix'; Arg = 'SUFFIX'; Help = 'remove a trailing SUFFIX; implies -a' }
        @{ Short = 'z'; Long = 'zero'; Help = 'end each output line with NUL, not newline' }
    )
    Notes       = @('PowerShell note: on Windows both / and \ separate directories.')
}

function Invoke-GnuBasename {
    <#
    .SYNOPSIS
    GNU basename: strip directory and suffix from file names.

    .DESCRIPTION
    Prints NAME without its leading directory components and, if given, without SUFFIX.
    On Windows both / and \ are directory separators.
    Enable the GNU name with: Enable-GnuAlias basename

    .EXAMPLE
    Invoke-GnuBasename /usr/bin/sort

    sort

    .EXAMPLE
    Invoke-GnuBasename -s .h include/stdio.h include/stdlib.h

    stdio
    stdlib
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'basename' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            $operands = @($ctx.Operands)
            $multiple = Test-GnuOption -Context $ctx -Key 'multiple'
            $suffix = ''
            if (Test-GnuOption -Context $ctx -Key 'suffix') {
                $suffix = [string](Get-GnuOptionValue -Context $ctx -Key 'suffix')
                $multiple = $true
            }

            $names = $operands
            if ($operands.Count -eq 0) {
                Write-GnuUsageError -Context $ctx -Message 'missing operand'
            }
            elseif (-not $multiple) {
                if ($operands.Count -gt 2) {
                    Write-GnuUsageError -Context $ctx -Message "extra operand '$($operands[2])'"
                }
                else {
                    $names = @($operands[0])
                    if ($operands.Count -eq 2) { $suffix = $operands[1] }
                }
            }

            if (-not $ctx.Done) {
                $results = foreach ($name in $names) { Get-GnuBaseName -Path $name -Suffix $suffix }
                ConvertTo-GnuRecordOutput -Record $results -Zero:(Test-GnuOption -Context $ctx -Key 'zero')
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}
