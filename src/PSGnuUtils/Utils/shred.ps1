Register-GnuUtil @{
    Name         = 'shred'
    Category     = 'File and directory operations'
    Synopsis     = 'Overwrite a file to hide its contents, and optionally delete it.'
    Usage        = @('shred [OPTION]... FILE...')
    Description  = @('Overwrite the specified FILE(s) repeatedly, in order to make it harder', 'for even very expensive hardware probing to recover the data.')
    FileOperands = $true
    Options      = @(
        @{ Short = 'f'; Long = 'force'; Help = 'change permissions to allow writing if necessary' }
        @{ Short = 'n'; Long = 'iterations'; Arg = 'N'; Help = 'overwrite N times instead of the default (3)' }
        @{ Long = 'random-source'; Arg = 'FILE'; Help = 'get random bytes from FILE' }
        @{ Short = 's'; Long = 'size'; Arg = 'N'; Help = 'shred this many bytes (suffixes like K, M, G accepted)' }
        @{ Short = 'u'; Key = 'remove'; Value = 'wipesync'; Help = 'deallocate and remove file after overwriting' }
        @{ Long = 'remove'; Arg = 'HOW'; OptionalArg = $true; Help = 'like -u but give control on HOW to delete;  See below' }
        @{ Short = 'v'; Long = 'verbose'; Help = 'show progress' }
        @{ Short = 'x'; Long = 'exact'; Help = 'do not round file sizes up to the next full block; this is the default for non-regular files' }
        @{ Short = 'z'; Long = 'zero'; Help = 'add a final overwrite with zeros to hide shredding' }
    )
    Notes        = @(
        'Delete FILE(s) if --remove (-u) is specified.  The default is not to remove',
        'the files because it is common to operate on device files like /dev/hda,',
        'and those files usually should not be removed.',
        'The optional HOW parameter indicates how to remove a directory entry:',
        '''unlink'' => use a standard unlink call.',
        '''wipe'' => also first obfuscate bytes in the name.',
        '''wipesync'' => also sync each obfuscated byte to the device.',
        'The default mode is ''wipesync'', but note it can be expensive.',
        '',
        'CAUTION: shred assumes the file system and hardware overwrite data in place.',
        'Although this is common, many platforms operate otherwise.  Also, backups',
        'and mirrors may contain unremovable copies that will let a shredded file',
        'be recovered later.  On SSDs and copy-on-write file systems (and NTFS with',
        'compression, encryption or shadow copies) shred cannot guarantee anything.',
        '',
        'PowerShell note: every pass writes random data (GNU mixes in fixed patterns);',
        '--random-source seeds the generator from FILE. Device files are not supported.'
    )
}

function Invoke-GnuShred {
    <#
    .SYNOPSIS
    GNU shred: overwrite files to hide their contents, optionally deleting them.

    .DESCRIPTION
    Overwrites each FILE 3 times (-n N) with random data, rounded up to 4 KiB blocks unless
    -x, plus a final pass of zeros with -z. -u renames the file to names of zeros and removes
    it. Not reliable on SSDs and copy-on-write file systems.
    Enable the GNU name with: Enable-GnuUtil shred

    .EXAMPLE
    Invoke-GnuShred -u -z secrets.txt
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'shred' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) { Invoke-GnuShredFile -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function Invoke-GnuShredFile {
    <#
    .SYNOPSIS
    Implementation of shred.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $operands = @($Context.Operands)
    if ($operands.Count -eq 0) { Write-GnuUsageError -Context $Context -Message 'missing file operand'; return }
    $passes = 3
    if (Test-GnuOption -Context $Context -Key 'iterations') {
        $text = [string](Get-GnuOptionValue -Context $Context -Key 'iterations')
        if ($text -notmatch '^\d+$') { Write-GnuError -Context $Context -Message "invalid number of passes: '$text'"; return }
        $passes = [int]$text
    }
    $size = $null
    if (Test-GnuOption -Context $Context -Key 'size') {
        $text = [string](Get-GnuOptionValue -Context $Context -Key 'size')
        $parsed = ConvertFrom-GnuSize -Text $text
        if ($null -eq $parsed) { Write-GnuError -Context $Context -Message "invalid file size: '$text'"; return }
        $size = ConvertTo-GnuInt64 -Value $parsed
    }
    $remove = $null
    if (Test-GnuOption -Context $Context -Key 'remove') {
        $remove = [string](Get-GnuOptionValue -Context $Context -Key 'remove')
        if ([string]::IsNullOrEmpty($remove)) { $remove = 'wipesync' }
        if (@('unlink', 'wipe', 'wipesync') -notcontains $remove) {
            Write-GnuUsageError -Context $Context -Message "invalid argument '$remove' for '--remove'`nValid arguments are:`n  - 'unlink'`n  - 'wipe'`n  - 'wipesync'"
            return
        }
    }
    $random = New-Object System.Random
    if (Test-GnuOption -Context $Context -Key 'random-source') {
        $sourceName = [string](Get-GnuOptionValue -Context $Context -Key 'random-source')
        $seedBytes = Get-GnuInputBytes -Context $Context -Operand $sourceName
        if ($null -eq $seedBytes) { return }
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        $random = New-Object System.Random -ArgumentList ([System.BitConverter]::ToInt32($hasher.ComputeHash([byte[]]$seedBytes), 0))
        $hasher.Dispose()
    }
    $report = Test-GnuOption -Context $Context -Key 'verbose'
    $zero = Test-GnuOption -Context $Context -Key 'zero'
    $exact = Test-GnuOption -Context $Context -Key 'exact'
    $total = $passes
    if ($zero) { $total++ }

    foreach ($operand in $operands) {
        if ($operand -eq '-') { Write-GnuError -Context $Context -Message '-: shredding standard output is not supported'; continue }
        $path = Resolve-GnuPath -Path $operand
        if ([System.IO.Directory]::Exists($path)) { Write-GnuError -Context $Context -Message "$($operand): failed to open for writing: Is a directory"; continue }
        if ((Test-GnuOption -Context $Context -Key 'force') -and [System.IO.File]::Exists($path)) {
            $attributes = [System.IO.File]::GetAttributes($path)
            if ($attributes -band [System.IO.FileAttributes]::ReadOnly) { [System.IO.File]::SetAttributes($path, $attributes -bxor [System.IO.FileAttributes]::ReadOnly) }
        }
        try { $stream = New-Object System.IO.FileStream -ArgumentList $path, 'Open', 'Write', 'None' }
        catch { Write-GnuError -Context $Context -Message "$($operand): failed to open for writing: $(Get-GnuErrorReason -Exception $_.Exception)"; continue }
        try {
            $length = $stream.Length
            if ($null -ne $size) { $length = $size }
            elseif (-not $exact -and $length % 4096 -ne 0) { $length += 4096 - ($length % 4096) }
            $buffer = New-Object byte[] 65536
            for ($pass = 1; $pass -le $total; $pass++) {
                $isZero = $zero -and $pass -eq $total
                if ($report) {
                    $label = '(random)'
                    if ($isZero) { $label = '(000000)' }
                    Write-GnuWarning -Context $Context -Message "$($operand): pass $pass/$total $label..."
                }
                $stream.Position = 0
                $left = $length
                while ($left -gt 0) {
                    $chunk = [int][Math]::Min([long]$buffer.Length, $left)
                    if ($isZero) { [System.Array]::Clear($buffer, 0, $chunk) } else { $random.NextBytes($buffer) }
                    $stream.Write($buffer, 0, $chunk)
                    $left -= $chunk
                }
                $stream.Flush($true)
            }
        }
        finally { $stream.Dispose() }
        if ($null -ne $remove) { Remove-GnuShreddedFile -Context $Context -Operand $operand -How $remove -Report:$report }
    }
}

function Remove-GnuShreddedFile {
    <#
    .SYNOPSIS
    Removes a shredded file; 'wipe' / 'wipesync' first rename it to ever shorter names of zeros.
    #>
    param([Parameter(Mandatory)][hashtable]$Context, [Parameter(Mandatory)][string]$Operand, [Parameter(Mandatory)][string]$How, [switch]$Report)

    if ($Report) { Write-GnuWarning -Context $Context -Message "$($Operand): removing" }
    $current = $Operand
    if ($How -ne 'unlink') {
        $directory = Get-GnuDirName -Path $Operand
        $prefix = ''
        if ($Operand -match '[\\/]') { $prefix = $directory.TrimEnd('/', '\') + $Operand.Substring($directory.TrimEnd('/', '\').Length, 1) }
        for ($length = (Get-GnuBaseName -Path $Operand).Length; $length -ge 1; $length--) {
            $candidate = $prefix + ('0' * $length)
            if ($candidate -eq $current -or [System.IO.File]::Exists((Resolve-GnuPath -Path $candidate))) { continue }
            try { [System.IO.File]::Move((Resolve-GnuPath -Path $current), (Resolve-GnuPath -Path $candidate)) }
            catch { break }
            if ($Report) { Write-GnuWarning -Context $Context -Message "$($current): renamed to $candidate" }
            $current = $candidate
        }
    }
    try { [System.IO.File]::Delete((Resolve-GnuPath -Path $current)) }
    catch { Write-GnuError -Context $Context -Message "$($Operand): failed to remove: $(Get-GnuErrorReason -Exception $_.Exception)"; return }
    if ($Report) { Write-GnuWarning -Context $Context -Message "$($Operand): removed" }
}
