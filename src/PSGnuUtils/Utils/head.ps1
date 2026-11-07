Register-GnuUtil @{
    Name            = 'head'
    Category        = 'Viewing file contents'
    Synopsis        = 'Output the first part of files.'
    Usage           = @('head [OPTION]... [FILE]...')
    Description     = @(
        'Print the first 10 lines of each FILE to standard output.',
        'With more than one FILE, precede each with a header giving the file name.',
        '',
        'With no FILE, or when FILE is -, read standard input.'
    )
    FileOperands    = $true
    NumericOption   = 'n'
    OpenErrorFormat = "cannot open '{0}' for reading: {1}"
    ReadErrorFormat = "error reading '{0}': {1}"
    Options         = @(
        @{ Short = 'c'; Long = 'bytes'; Key = 'count'; Arg = '[-]NUM'; Sets = @{ unit = 'bytes' }; Help = "print the first NUM bytes of each file; with the leading '-', print all but the last NUM bytes of each file" }
        @{ Short = 'n'; Long = 'lines'; Key = 'count'; Arg = '[-]NUM'; Sets = @{ unit = 'lines' }; Help = "print the first NUM lines instead of the first 10; with the leading '-', print all but the last NUM lines of each file" }
        @{ Short = 'q'; Long = 'quiet'; Key = 'headers'; Value = 'never'; Help = 'never print headers giving file names' }
        @{ Long = 'silent'; Key = 'headers'; Value = 'never'; Help = 'same as --quiet' }
        @{ Short = 'v'; Long = 'verbose'; Key = 'headers'; Value = 'always'; Help = 'always print headers giving file names' }
        @{ Short = 'z'; Long = 'zero-terminated'; Help = 'line delimiter is NUL, not newline' }
    )
    Notes           = @(
        'NUM may have a multiplier suffix:',
        'b 512, kB 1000, K 1024, MB 1000*1000, M 1024*1024,',
        'GB 1000*1000*1000, G 1024*1024*1024, and so on for T, P, E, Z, Y, R, Q.',
        'Binary prefixes can be used, too: KiB=K, MiB=M, and so on.',
        '',
        'PowerShell note: a PowerShell function cannot stop the command that feeds it; for',
        'endless producers use Select-Object -First N instead.'
    )
}

function Invoke-GnuHead {
    <#
    .SYNOPSIS
    GNU head: output the first part of files.

    .DESCRIPTION
    Prints the first 10 lines (or -n NUM lines, or -c NUM bytes) of each FILE. A leading '-'
    (-n -5) prints everything except the last NUM lines/bytes. head -5 is short for head -n 5.
    Pipeline input is processed as it arrives.
    Enable the GNU name with: Enable-GnuUtil head

    .EXAMPLE
    Invoke-GnuHead -n 3 notes.txt

    .EXAMPLE
    Get-Content big.log | Invoke-GnuHead -5
    #>
    begin {
        $ctx = Initialize-GnuUtil -Name 'head' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput
        if (-not $ctx.Done) { $head = New-GnuHeadTailState -Context $ctx -AllowSuffixSign '-' }
    }
    process {
        if ($ctx.Done) { return }
        if ($head.Stream) {
            foreach ($line in @(ConvertFrom-GnuPipelineItem -Context $ctx -InputObject $_)) {
                if ($head.Emitted -lt $head.Count) {
                    $head.Emitted++
                    $line
                }
            }
        }
        else {
            Add-GnuPipelineInput -Context $ctx -InputObject $_
        }
    }
    end {
        if (-not $ctx.Done) {
            if ($head.Stream) {
                foreach ($line in @(Complete-GnuPipelineInput -Context $ctx)) {
                    if ($head.Emitted -lt $head.Count) {
                        $head.Emitted++
                        $line
                    }
                }
            }
            else {
                Invoke-GnuHeadTailOperand -Context $ctx -State $head -Mode 'head'
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}
