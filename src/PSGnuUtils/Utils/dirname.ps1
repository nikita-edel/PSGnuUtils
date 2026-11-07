Register-GnuUtil @{
    Name        = 'dirname'
    Category    = 'Paths and names'
    Synopsis    = 'Strip last component from file name.'
    Usage       = @('dirname [OPTION] NAME...')
    Description = @(
        'Output each NAME with its last non-slash component and trailing slashes',
        "removed; if NAME contains no /'s, output '.' (meaning the current directory)."
    )
    Options     = @(
        @{ Short = 'z'; Long = 'zero'; Help = 'end each output line with NUL, not newline' }
    )
    Notes       = @('PowerShell note: on Windows both / and \ separate directories; C:\foo gives C:\.')
}

function Invoke-GnuDirname {
    <#
    .SYNOPSIS
    GNU dirname: strip the last component from file names.

    .DESCRIPTION
    Prints each NAME without its last component. Names without a directory part give '.'.
    On Windows both / and \ are directory separators.
    Enable the GNU name with: Enable-GnuUtil dirname

    .EXAMPLE
    Invoke-GnuDirname /usr/bin/

    /usr

    .EXAMPLE
    Invoke-GnuDirname dir1/str dir2/str stdio.h

    dir1
    dir2
    .
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'dirname' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            $operands = @($ctx.Operands)
            if ($operands.Count -eq 0) {
                Write-GnuUsageError -Context $ctx -Message 'missing operand'
            }
            else {
                $results = foreach ($name in $operands) { Get-GnuDirName -Path $name }
                ConvertTo-GnuRecordOutput -Record $results -Zero:(Test-GnuOption -Context $ctx -Key 'zero')
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}
