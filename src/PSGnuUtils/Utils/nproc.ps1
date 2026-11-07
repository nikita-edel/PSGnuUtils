Register-GnuUtil @{
    Name        = 'nproc'
    Category    = 'User and system info'
    Synopsis    = 'Print the number of processing units available.'
    Usage       = @('nproc [OPTION]...')
    Description = @(
        'Print the number of processing units available to the current process,',
        'which may be less than the number of online processors.'
    )
    Options     = @(
        @{ Long = 'all'; Help = 'print the number of installed processors' }
        @{ Long = 'ignore'; Arg = 'N'; Help = 'if possible, exclude N processing units' }
    )
    Notes       = @(
        'The OMP_NUM_THREADS and OMP_THREAD_LIMIT environment variables are honored unless --all is given.',
        'PowerShell note: --all reports the same count as the runtime sees ([Environment]::ProcessorCount).'
    )
}

function Invoke-GnuNproc {
    <#
    .SYNOPSIS
    GNU nproc: print the number of processing units available.

    .DESCRIPTION
    Prints [Environment]::ProcessorCount, adjusted by OMP_NUM_THREADS / OMP_THREAD_LIMIT and
    --ignore=N. The result is never less than 1.
    Enable the GNU name with: Enable-GnuUtil nproc

    .EXAMPLE
    Invoke-GnuNproc --ignore=2

    6
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'nproc' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            $operands = @($ctx.Operands)
            $ignore = 0
            if (Test-GnuOption -Context $ctx -Key 'ignore') {
                $ignoreText = [string](Get-GnuOptionValue -Context $ctx -Key 'ignore')
                if ($ignoreText -notmatch '^\d+$') {
                    Write-GnuError -Context $ctx -Message "invalid number: '$ignoreText'"
                    $ctx.Done = $true
                }
                else {
                    $ignore = ConvertTo-GnuInt64 -Value (ConvertFrom-GnuSize -Text $ignoreText)
                }
            }

            if ($ctx.Done) {
                # invalid --ignore already reported
            }
            elseif ($operands.Count -gt 0) {
                Write-GnuUsageError -Context $ctx -Message "extra operand '$($operands[0])'"
            }
            else {
                $count = [long][System.Environment]::ProcessorCount
                if (-not (Test-GnuOption -Context $ctx -Key 'all')) {
                    if ([string]$env:OMP_NUM_THREADS -match '^\s*(\d+)') {
                        $requested = [long]$Matches[1]
                        if ($requested -gt 0) { $count = $requested }
                    }
                    if ([string]$env:OMP_THREAD_LIMIT -match '^\s*(\d+)\s*$') {
                        $limit = [long]$Matches[1]
                        if ($limit -gt 0 -and $limit -lt $count) { $count = $limit }
                    }
                }
                $count -= $ignore
                if ($count -lt 1) { $count = 1 }
                [string]$count
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}
