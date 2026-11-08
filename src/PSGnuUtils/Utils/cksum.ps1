Register-GnuUtil @{
    Name         = 'cksum'
    Category     = 'Checksums'
    Synopsis     = 'Compute and verify file checksums.'
    Usage        = @('cksum [OPTION]... [FILE]...')
    Description  = @('Print or verify checksums.', 'By default use the 32 bit CRC algorithm.', '', 'With no FILE, or when FILE is -, read standard input.')
    FileOperands = $true
    Options      = @(
        @{ Short = 'a'; Long = 'algorithm'; Arg = 'TYPE'; Help = 'select the digest type to use.  See DIGEST below.' }
        @{ Short = 'c'; Long = 'check'; Help = 'read checksums from the FILEs and check them' }
        @{ Long = 'tag'; Help = 'create a BSD-style checksum (the default)' }
        @{ Long = 'untagged'; Help = 'create a reversed style checksum, without digest type' }
        @{ Short = 'z'; Long = 'zero'; Help = 'end each output line with NUL, not newline, and disable file name escaping' }
        @{ Long = 'ignore-missing'; Help = 'don''t fail or report status for missing files' }
        @{ Long = 'quiet'; Help = 'don''t print OK for each successfully verified file' }
        @{ Long = 'status'; Help = 'don''t output anything, status code shows success' }
        @{ Long = 'strict'; Help = 'exit non-zero for improperly formatted checksum lines' }
        @{ Short = 'w'; Long = 'warn'; Help = 'warn about improperly formatted checksum lines' }
    )
    Notes        = @(
        'DIGEST determines the digest algorithm and default output format:',
        '  sysv      (equivalent to sum -s)',
        '  bsd       (equivalent to sum -r)',
        '  crc       (equivalent to cksum)',
        '  md5       (equivalent to md5sum)',
        '  sha1      (equivalent to sha1sum)',
        '  sha224    (equivalent to sha224sum)',
        '  sha256    (equivalent to sha256sum)',
        '  sha384    (equivalent to sha384sum)',
        '  sha512    (equivalent to sha512sum)',
        '',
        'The check options (--ignore-missing, --quiet, --status, --strict, -w) apply to -c.',
        'PowerShell note: blake2b, sm3, --base64, --raw and --length are not supported.'
    )
}

function Invoke-GnuCksum {
    <#
    .SYNOPSIS
    GNU cksum: POSIX CRC checksums, or other digests with -a.

    .DESCRIPTION
    Prints "CRC SIZE NAME" (the POSIX cksum CRC-32) for every FILE. -a selects sysv, bsd,
    md5, sha1, sha224, sha256, sha384 or sha512; digests are printed in BSD tag format unless
    --untagged, and can be verified with -c.
    Enable the GNU name with: Enable-GnuAlias cksum

    .EXAMPLE
    Invoke-GnuCksum -a sha256 setup.exe
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'cksum' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuCksumAlgorithm -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

$script:GnuCrcTable = $null

function Get-GnuPosixCrc {
    <#
    .SYNOPSIS
    The POSIX cksum CRC (polynomial 0x04C11DB7, MSB first, length appended, complemented).
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)

    if ($null -eq $script:GnuCrcTable) {
        $table = New-Object long[] 256
        for ($i = 0; $i -lt 256; $i++) {
            $crc = [long]$i -shl 24
            for ($bit = 0; $bit -lt 8; $bit++) {
                if ($crc -band 0x80000000L) { $crc = (($crc -shl 1) -bxor 0x04C11DB7L) -band 0xFFFFFFFFL }
                else { $crc = ($crc -shl 1) -band 0xFFFFFFFFL }
            }
            $table[$i] = $crc
        }
        $script:GnuCrcTable = $table
    }
    $table = $script:GnuCrcTable
    $crc = [long]0
    foreach ($byte in $Bytes) { $crc = (($crc -shl 8) -band 0xFFFFFFFFL) -bxor $table[(($crc -shr 24) -bxor $byte) -band 0xFF] }
    $length = [long]$Bytes.Length
    while ($length -gt 0) {
        $crc = (($crc -shl 8) -band 0xFFFFFFFFL) -bxor $table[(($crc -shr 24) -bxor ($length -band 0xFF)) -band 0xFF]
        $length = $length -shr 8
    }
    (-bnot $crc) -band 0xFFFFFFFFL
}

function Invoke-GnuCksumAlgorithm {
    <#
    .SYNOPSIS
    Implementation of cksum.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $algorithm = [string](Get-GnuOptionValue -Context $Context -Key 'algorithm' -Default 'crc')
    $digests = @{ md5 = 'md5sum'; sha1 = 'sha1sum'; sha224 = 'sha224sum'; sha256 = 'sha256sum'; sha384 = 'sha384sum'; sha512 = 'sha512sum' }
    if (@('crc', 'sysv', 'bsd') -notcontains $algorithm -and -not $digests.ContainsKey($algorithm)) {
        Write-GnuUsageError -Context $Context -Message "invalid argument '$algorithm' for '--algorithm'`nValid arguments are: 'sysv', 'bsd', 'crc', 'md5', 'sha1', 'sha224', 'sha256', 'sha384', 'sha512'"
        return
    }
    $operands = @($Context.Operands)
    $given = $operands.Count
    if ($given -eq 0) { $operands = @('-') }

    if ($digests.ContainsKey($algorithm)) {
        $definition = $script:GnuChecksumAlgorithms[$digests[$algorithm]]
        if (Test-GnuOption -Context $Context -Key 'check') {
            Test-GnuChecksumList -Context $Context -Algorithm $definition -Operands $operands
            return
        }
        $zero = Test-GnuOption -Context $Context -Key 'zero'
        $records = foreach ($operand in $operands) {
            $hash = Get-GnuChecksumHex -Context $Context -Operand $operand -Algorithm $definition
            if ($null -eq $hash) { continue }
            if (Test-GnuOption -Context $Context -Key 'untagged') { "$hash  $operand" }
            else { "$($definition.Tag) ($operand) = $hash" }
        }
        ConvertTo-GnuRecordOutput -Record @($records) -Zero:$zero
        return
    }
    if (Test-GnuOption -Context $Context -Key 'check') {
        Write-GnuError -Context $Context -Message '--check is not supported with --algorithm={bsd,sysv,crc}'
        return
    }

    foreach ($operand in $operands) {
        $bytes = Get-GnuInputBytes -Context $Context -Operand $operand
        if ($null -eq $bytes) { continue }
        if ($algorithm -eq 'crc') { $line = "$(Get-GnuPosixCrc -Bytes $bytes) $($bytes.Length)" }
        else { $line = Get-GnuSumLine -Bytes $bytes -SysV:($algorithm -eq 'sysv') }
        if ($given -gt 0) { $line += " $operand" }
        $line
    }
}
