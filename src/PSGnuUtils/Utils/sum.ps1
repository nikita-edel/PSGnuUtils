Register-GnuUtil @{
    Name         = 'sum'
    Category     = 'Checksums'
    Synopsis     = 'Checksum and count the blocks in a file.'
    Usage        = @('sum [OPTION]... [FILE]...')
    Description  = @('Print or check BSD (16-bit) checksums.', '', 'With no FILE, or when FILE is -, read standard input.')
    FileOperands = $true
    Options      = @(
        @{ Short = 'r'; Key = 'algorithm'; Value = 'bsd'; Help = 'use BSD sum algorithm (the default), use 1K blocks' }
        @{ Short = 's'; Long = 'sysv'; Key = 'algorithm'; Value = 'sysv'; Help = 'use System V sum algorithm, use 512 bytes blocks' }
    )
}

function Invoke-GnuSum {
    <#
    .SYNOPSIS
    GNU sum: BSD or System V checksums and block counts.

    .DESCRIPTION
    Prints the 16-bit BSD checksum and the number of 1K blocks of every FILE (default, -r), or
    the System V checksum and 512-byte blocks (-s). File names are shown for several files
    (BSD) or whenever files are given (System V).
    Enable the GNU name with: Enable-GnuAlias sum

    .EXAMPLE
    Invoke-GnuSum -s data.bin
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'sum' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) {
            $sysv = (Get-GnuOptionValue -Context $ctx -Key 'algorithm' -Default 'bsd') -eq 'sysv'
            $operands = @($ctx.Operands)
            $given = $operands.Count
            if ($given -eq 0) { $operands = @('-') }
            foreach ($operand in $operands) {
                $bytes = Get-GnuInputBytes -Context $ctx -Operand $operand
                if ($null -eq $bytes) { continue }
                $line = Get-GnuSumLine -Bytes $bytes -SysV:$sysv
                # GNU prints the name for any file with -s, but only for several files with -r.
                if (($sysv -and $given -gt 0) -or $given -gt 1) { $line += " $operand" }
                $line
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}

function Get-GnuSumLine {
    <#
    .SYNOPSIS
    "CHECKSUM BLOCKS" as printed by sum -r (BSD) or sum -s (System V), without the file name.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes, [switch]$SysV)

    if ($SysV) {
        $total = [long]0
        foreach ($byte in $Bytes) { $total = ($total + $byte) -band 0xFFFFFFFFL }
        $folded = ($total -band 0xFFFF) + (($total -shr 16) -band 0xFFFF)
        return "$(($folded -band 0xFFFF) + ($folded -shr 16)) $([long][Math]::Ceiling($Bytes.Length / 512))"
    }
    $checksum = 0
    foreach ($byte in $Bytes) { $checksum = (($checksum -shr 1) + (($checksum -band 1) -shl 15) + $byte) -band 0xFFFF }
    ([string]$checksum).PadLeft(5, '0') + ' ' + ([string][long][Math]::Ceiling($Bytes.Length / 1024)).PadLeft(5)
}
