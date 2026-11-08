Register-GnuUtil @{
    Name         = 'truncate'
    Category     = 'File and directory operations'
    Synopsis     = 'Shrink or extend the size of a file to the specified size.'
    Usage        = @('truncate OPTION... FILE...')
    Description  = @(
        'Shrink or extend the size of each FILE to the specified size.',
        '',
        'A FILE argument that does not exist is created.',
        '',
        'If a FILE is larger than the specified size, the extra data is lost.',
        'If a FILE is shorter, it is extended and the sparse extended part (hole)',
        'reads as zero bytes.'
    )
    FileOperands = $true
    Options      = @(
        @{ Short = 'c'; Long = 'no-create'; Help = 'do not create any files' }
        @{ Short = 'o'; Long = 'io-blocks'; Help = 'treat SIZE as number of IO blocks instead of bytes' }
        @{ Short = 'r'; Long = 'reference'; Arg = 'RFILE'; Help = 'base size on RFILE' }
        @{ Short = 's'; Long = 'size'; Arg = 'SIZE'; Help = 'set or adjust the file size by SIZE bytes' }
    )
    Notes        = @(
        'The SIZE argument is an integer and optional unit (example: 10K is 10*1024).',
        'Units are K,M,G,T,P,E,Z,Y,R,Q (powers of 1024) or KB,MB,... (powers of 1000).',
        'Binary prefixes can be used, too: KiB=K, MiB=M, and so on.',
        '',
        'SIZE may also be prefixed by one of the following modifying characters:',
        "'+' extend by, '-' reduce by, '<' at most, '>' at least,",
        "'/' round down to multiple of, '%' round up to multiple of.",
        '',
        'PowerShell note: an IO block (-o) is 4096 bytes.'
    )
}

function Invoke-GnuTruncate {
    <#
    .SYNOPSIS
    GNU truncate: shrink or extend files to a size.

    .DESCRIPTION
    Sets the size of every FILE to SIZE (-s) or to the size of RFILE (-r). Missing files are
    created unless -c is given. SIZE may be relative: +N, -N, <N, >N, /N, %N.
    Enable the GNU name with: Enable-GnuAlias truncate

    .EXAMPLE
    Invoke-GnuTruncate -s 0 app.log

    Empties app.log.

    .EXAMPLE
    Invoke-GnuTruncate -s 1G disk.img

    Creates a 1 GiB (sparse where supported) file.
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'truncate' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            Invoke-GnuTruncateFile -Context $ctx
        }
        Complete-GnuUtil -Context $ctx
    }
}

function Invoke-GnuTruncateFile {
    <#
    .SYNOPSIS
    Implementation of truncate (kept separate for readability).
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $hasSize = Test-GnuOption -Context $Context -Key 'size'
    $hasReference = Test-GnuOption -Context $Context -Key 'reference'
    $operands = @($Context.Operands)
    if (-not $hasSize -and -not $hasReference) {
        Write-GnuUsageError -Context $Context -Message "you must specify either '--size' or '--reference'"
        return
    }
    if ($operands.Count -eq 0) {
        Write-GnuUsageError -Context $Context -Message 'missing file operand'
        return
    }

    $operator = ''
    $amount = [decimal]0
    if ($hasSize) {
        $sizeText = [string](Get-GnuOptionValue -Context $Context -Key 'size')
        $numberText = $sizeText
        if ($sizeText.Length -gt 0 -and '+-<>/%'.IndexOf($sizeText[0]) -ge 0) {
            $operator = [string]$sizeText[0]
            $numberText = $sizeText.Substring(1)
        }
        $parsed = ConvertFrom-GnuSize -Text $numberText
        if ($null -eq $parsed) {
            Write-GnuError -Context $Context -Message "Invalid number: '$sizeText'"
            return
        }
        $amount = $parsed
        if (Test-GnuOption -Context $Context -Key 'io-blocks') { $amount = $amount * 4096 }
        if (($operator -eq '/' -or $operator -eq '%') -and $amount -eq 0) {
            Write-GnuError -Context $Context -Message 'division by zero'
            return
        }
    }

    $referenceSize = $null
    if ($hasReference) {
        $referenceName = [string](Get-GnuOptionValue -Context $Context -Key 'reference')
        $referencePath = Resolve-GnuPath -Path $referenceName
        if ([System.IO.File]::Exists($referencePath)) {
            $referenceSize = [decimal](New-Object System.IO.FileInfo -ArgumentList $referencePath).Length
        }
        elseif ([System.IO.Directory]::Exists($referencePath)) {
            $referenceSize = [decimal]0
        }
        else {
            Write-GnuError -Context $Context -Message "cannot stat '$referenceName': No such file or directory"
            return
        }
        if ($hasSize -and [string]::IsNullOrEmpty($operator)) {
            Write-GnuUsageError -Context $Context -Message "you must specify a relative '--size' with '--reference'"
            return
        }
    }

    foreach ($name in $operands) {
        $path = Resolve-GnuPath -Path $name
        if ([System.IO.Directory]::Exists($path)) {
            Write-GnuError -Context $Context -Message "cannot open '$name' for writing: Is a directory"
            continue
        }
        if (-not [System.IO.File]::Exists($path) -and (Test-GnuOption -Context $Context -Key 'no-create')) { continue }

        $stream = $null
        try {
            $stream = New-Object System.IO.FileStream -ArgumentList $path, ([System.IO.FileMode]::OpenOrCreate), ([System.IO.FileAccess]::Write)
            $current = [decimal]$stream.Length
            if ($null -ne $referenceSize) { $current = $referenceSize }

            $newSize = $current
            switch ($operator) {
                '' { if ($hasSize) { $newSize = $amount } }
                '+' { $newSize = $current + $amount }
                '-' { $newSize = [Math]::Max([decimal]0, $current - $amount) }
                '<' { $newSize = [Math]::Min($current, $amount) }
                '>' { $newSize = [Math]::Max($current, $amount) }
                '/' { $newSize = [Math]::Floor($current / $amount) * $amount }
                '%' { $newSize = [Math]::Ceiling($current / $amount) * $amount }
            }
            $stream.SetLength((ConvertTo-GnuInt64 -Value $newSize))
        }
        catch {
            Write-GnuError -Context $Context -Message "cannot open '$name' for writing: $(Get-GnuErrorReason -Exception $_.Exception)"
        }
        finally {
            if ($null -ne $stream) { $stream.Dispose() }
        }
    }
}
