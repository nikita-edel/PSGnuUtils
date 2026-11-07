Register-GnuUtil @{
    Name        = 'tee'
    Category    = 'Shell helpers'
    Synopsis    = 'Read from standard input and write to standard output and files.'
    Usage       = @('tee [OPTION]... [FILE]...')
    Description = @('Copy standard input to each FILE, and also to standard output.')
    Options     = @(
        @{ Short = 'a'; Long = 'append'; Help = 'append to the given FILEs, do not overwrite' }
        @{ Short = 'i'; Long = 'ignore-interrupts'; Help = 'ignore interrupt signals (accepted, no effect in PowerShell)' }
        @{ Short = 'p'; Key = 'output-error'; Value = 'warn-nopipe'; Help = 'operate in a more appropriate MODE with pipes' }
        @{ Long = 'output-error'; Arg = 'MODE'; OptionalArg = $true; Help = 'set behavior on write error (accepted; errors are always reported)' }
    )
    Notes       = @(
        'PowerShell note: files are written as UTF-8 without BOM, with LF line endings.',
        'Lines are written as they arrive, so tee works with long-running pipelines.'
    )
}

function Invoke-GnuTee {
    <#
    .SYNOPSIS
    GNU tee: copy pipeline input to files and to the output.

    .DESCRIPTION
    Every input line is written to each FILE (UTF-8, LF line endings) and passed on to the
    pipeline. -a appends instead of overwriting. Lines are written as they arrive.
    Enable the GNU name with: Enable-GnuUtil tee (replaces the tee -> Tee-Object alias).

    .EXAMPLE
    Get-Process | Invoke-GnuTee processes.txt | Select-Object -First 5

    .EXAMPLE
    'one', 'two' | Invoke-GnuTee -a log1.txt log2.txt
    #>
    begin {
        $ctx = Initialize-GnuUtil -Name 'tee' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput
        $writers = New-Object 'System.Collections.Generic.List[System.IO.StreamWriter]'
        if (-not $ctx.Done) {
            $mode = [System.IO.FileMode]::Create
            if (Test-GnuOption -Context $ctx -Key 'append') { $mode = [System.IO.FileMode]::Append }
            foreach ($name in @($ctx.Operands)) {
                try {
                    $path = Resolve-GnuPath -Path $name
                    $stream = New-Object System.IO.FileStream -ArgumentList $path, $mode, ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::Read)
                    $writer = New-Object System.IO.StreamWriter -ArgumentList $stream, $script:GnuUtf8
                    $writer.NewLine = "`n"
                    $writer.AutoFlush = $true
                    $writers.Add($writer)
                }
                catch {
                    Write-GnuError -Context $ctx -Message "$($name): $(Get-GnuErrorReason -Exception $_.Exception)"
                }
            }
        }
    }
    process {
        if ($ctx.Done) { return }
        foreach ($line in @(ConvertFrom-GnuPipelineItem -Context $ctx -InputObject $_)) {
            foreach ($writer in $writers) { $writer.WriteLine($line) }
            $line
        }
    }
    end {
        if (-not $ctx.Done) {
            $remaining = @(Complete-GnuPipelineInput -Context $ctx)
            if (-not $ctx.ExpectingInput) { $remaining = @(Read-GnuStdinLine -Context $ctx) }
            foreach ($line in $remaining) {
                foreach ($writer in $writers) { $writer.WriteLine($line) }
                $line
            }
        }
        foreach ($writer in $writers) { $writer.Dispose() }
        Complete-GnuUtil -Context $ctx
    }
}
