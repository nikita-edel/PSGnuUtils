Register-GnuUtil @{
    Name            = 'tail'
    Category        = 'Viewing file contents'
    Synopsis        = 'Output the last part of files.'
    Usage           = @('tail [OPTION]... [FILE]...')
    Description     = @(
        'Print the last 10 lines of each FILE to standard output.',
        'With more than one FILE, precede each with a header giving the file name.',
        '',
        'With no FILE, or when FILE is -, read standard input.'
    )
    FileOperands    = $true
    NumericOption   = 'n'
    OpenErrorFormat = "cannot open '{0}' for reading: {1}"
    ReadErrorFormat = "error reading '{0}': {1}"
    Options         = @(
        @{ Short = 'c'; Long = 'bytes'; Key = 'count'; Arg = '[+]NUM'; Sets = @{ unit = 'bytes' }; Help = 'output the last NUM bytes; or use -c +NUM to output starting with byte NUM of each file' }
        @{ Short = 'n'; Long = 'lines'; Key = 'count'; Arg = '[+]NUM'; Sets = @{ unit = 'lines' }; Help = 'output the last NUM lines, instead of the last 10; or use -n +NUM to skip NUM-1 lines at the start' }
        @{ Short = 'q'; Long = 'quiet'; Key = 'headers'; Value = 'never'; Help = 'never output headers giving file names' }
        @{ Long = 'silent'; Key = 'headers'; Value = 'never'; Help = 'same as --quiet' }
        @{ Short = 'v'; Long = 'verbose'; Key = 'headers'; Value = 'always'; Help = 'always output headers giving file names' }
        @{ Short = 'z'; Long = 'zero-terminated'; Help = 'line delimiter is NUL, not newline' }
    )
    Notes           = @(
        'NUM may have a multiplier suffix:',
        'b 512, kB 1000, K 1024, MB 1000*1000, M 1024*1024,',
        'GB 1000*1000*1000, G 1024*1024*1024, and so on for T, P, E, Z, Y, R, Q.',
        'Binary prefixes can be used, too: KiB=K, MiB=M, and so on.',
        '',
        'PowerShell note: --follow (-f/-F) is planned (see docs/PLAN.md); use Get-Content -Wait meanwhile.'
    )
}

function Invoke-GnuTail {
    <#
    .SYNOPSIS
    GNU tail: output the last part of files.

    .DESCRIPTION
    Prints the last 10 lines (or -n NUM lines, or -c NUM bytes) of each FILE. -n +NUM starts
    at line NUM instead. tail -5 is short for tail -n 5.
    Enable the GNU name with: Enable-GnuUtil tail

    .EXAMPLE
    Invoke-GnuTail -n 20 app.log

    .EXAMPLE
    Get-Content data.csv | Invoke-GnuTail -n +2

    Everything except the header line.
    #>
    begin {
        $ctx = Initialize-GnuUtil -Name 'tail' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput
        if (-not $ctx.Done) { $tail = New-GnuHeadTailState -Context $ctx -AllowSuffixSign '+' }
    }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) {
            Invoke-GnuHeadTailOperand -Context $ctx -State $tail -Mode 'tail'
        }
        Complete-GnuUtil -Context $ctx
    }
}
