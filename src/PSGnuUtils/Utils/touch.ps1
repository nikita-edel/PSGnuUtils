Register-GnuUtil @{
    Name         = 'touch'
    Category     = 'File and directory operations'
    Synopsis     = 'Change file timestamps.'
    Usage        = @('touch [OPTION]... FILE...')
    Description  = @(
        'Update the access and modification times of each FILE to the current time.',
        '',
        'A FILE argument that does not exist is created empty, unless -c or -h is supplied.',
        '',
        'A FILE argument string of - is handled specially and causes touch to',
        'change the times of the file associated with standard output.'
    )
    FileOperands = $true
    Options      = @(
        @{ Short = 'a'; Key = 'access'; Help = 'change only the access time' }
        @{ Short = 'c'; Long = 'no-create'; Help = 'do not create any files' }
        @{ Short = 'd'; Long = 'date'; Arg = 'STRING'; Help = 'parse STRING and use it instead of current time' }
        @{ Short = 'f'; Help = '(ignored)' }
        @{ Short = 'h'; Long = 'no-dereference'; Help = 'affect each symbolic link instead of any referenced file (useful only on systems that can change the timestamps of a symlink)' }
        @{ Short = 'm'; Key = 'modify'; Help = 'change only the modification time' }
        @{ Short = 'r'; Long = 'reference'; Arg = 'FILE'; Help = 'use this file''s times instead of current time' }
        @{ Short = 't'; Key = 'stamp'; Arg = 'STAMP'; Help = 'use [[CC]YY]MMDDhhmm[.ss] instead of current time' }
        @{ Long = 'time'; Arg = 'WORD'; Help = 'change the specified time: WORD is access, atime, or use: equivalent to -a; WORD is modify or mtime: equivalent to -m' }
    )
    Notes        = @(
        'PowerShell notes: -d understands @SECONDS, now/today/yesterday/tomorrow, ISO 8601 and other',
        'invariant-culture dates, and relative items such as "2 days ago" or "+3 hours" (not all of GNU''s grammar).',
        'The - operand (standard output) is ignored. -h does not create missing files; .NET sets the times of',
        'a link''s target.'
    )
}

function Invoke-GnuTouch {
    <#
    .SYNOPSIS
    GNU touch: change file timestamps, creating missing files.

    .DESCRIPTION
    Sets the access and modification time of every FILE to now, to -d DATE, -t STAMP or the
    times of -r FILE. Missing files are created empty unless -c (or -h) is given. -a / -m (or
    --time) change only one of the two times.
    Enable the GNU name with: Enable-GnuAlias touch

    .EXAMPLE
    Invoke-GnuTouch new.txt

    .EXAMPLE
    Invoke-GnuTouch -d '2 days ago' old.log
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'touch' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) { Invoke-GnuTouchFile -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function Invoke-GnuTouchFile {
    <#
    .SYNOPSIS
    Implementation of touch.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $operands = @($Context.Operands)
    if ($operands.Count -eq 0) {
        Write-GnuUsageError -Context $Context -Message 'missing file operand'
        return
    }

    $setAccess = Test-GnuOption -Context $Context -Key 'access'
    $setModify = Test-GnuOption -Context $Context -Key 'modify'
    if (Test-GnuOption -Context $Context -Key 'time') {
        $word = [string](Get-GnuOptionValue -Context $Context -Key 'time')
        switch -Regex ($word) {
            '^(access|atime|use)$' { $setAccess = $true }
            '^(modify|mtime)$' { $setModify = $true }
            default {
                Write-GnuUsageError -Context $Context -Message "invalid argument '$word' for '--time'`nValid arguments are: 'atime', 'access', 'use', 'mtime', 'modify'"
                return
            }
        }
    }
    if (-not $setAccess -and -not $setModify) {
        $setAccess = $true
        $setModify = $true
    }

    if ((Test-GnuOption -Context $Context -Key 'date') -and (Test-GnuOption -Context $Context -Key 'stamp')) {
        Write-GnuUsageError -Context $Context -Message 'cannot specify times from more than one source'
        return
    }

    $now = [datetime]::Now
    $accessTime = $now
    $modifyTime = $now
    if (Test-GnuOption -Context $Context -Key 'reference') {
        $referenceName = [string](Get-GnuOptionValue -Context $Context -Key 'reference')
        $reference = Get-Item -LiteralPath (Resolve-GnuPath -Path $referenceName) -Force -ErrorAction SilentlyContinue
        if ($null -eq $reference) {
            Write-GnuError -Context $Context -Message "failed to get attributes of '$referenceName': No such file or directory"
            return
        }
        $accessTime = $reference.LastAccessTime
        $modifyTime = $reference.LastWriteTime
    }
    if (Test-GnuOption -Context $Context -Key 'date') {
        $text = [string](Get-GnuOptionValue -Context $Context -Key 'date')
        # GNU: with -r, relative dates are relative to the reference file's modification time.
        $parsed = ConvertFrom-GnuDateString -Text $text -Now $modifyTime
        if ($null -eq $parsed) {
            Write-GnuError -Context $Context -Message "invalid date format '$text'"
            return
        }
        $accessTime = $parsed
        $modifyTime = $parsed
    }
    if (Test-GnuOption -Context $Context -Key 'stamp') {
        $stamp = [string](Get-GnuOptionValue -Context $Context -Key 'stamp')
        $parsed = ConvertFrom-GnuTouchStamp -Stamp $stamp
        if ($null -eq $parsed) {
            Write-GnuError -Context $Context -Message "invalid date format '$stamp'"
            return
        }
        $accessTime = $parsed
        $modifyTime = $parsed
    }

    $noCreate = (Test-GnuOption -Context $Context -Key 'no-create') -or (Test-GnuOption -Context $Context -Key 'no-dereference')
    foreach ($name in $operands) {
        if ($name -eq '-') { continue }
        $path = Resolve-GnuPath -Path $name
        if (-not [System.IO.File]::Exists($path) -and -not [System.IO.Directory]::Exists($path)) {
            if ($noCreate) { continue }
            try {
                $stream = New-Object System.IO.FileStream -ArgumentList $path, ([System.IO.FileMode]::OpenOrCreate), ([System.IO.FileAccess]::Write)
                $stream.Dispose()
            }
            catch {
                Write-GnuError -Context $Context -Message "cannot touch '$name': $(Get-GnuErrorReason -Exception $_.Exception)"
                continue
            }
        }

        try {
            $item = Get-Item -LiteralPath $path -Force
            if ($setAccess) { $item.LastAccessTime = $accessTime }
            if ($setModify) { $item.LastWriteTime = $modifyTime }
        }
        catch {
            Write-GnuError -Context $Context -Message "setting times of '$name': $(Get-GnuErrorReason -Exception $_.Exception)"
        }
    }
}
