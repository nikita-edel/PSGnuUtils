Register-GnuUtil @{
    Name        = 'mktemp'
    Category    = 'File and directory operations'
    Synopsis    = 'Create a temporary file or directory.'
    Usage       = @('mktemp [OPTION]... [TEMPLATE]')
    Description = @(
        'Create a temporary file or directory, safely, and print its name.',
        'TEMPLATE must contain at least 3 consecutive ''X''s in last component.',
        'If TEMPLATE is not specified, use tmp.XXXXXXXXXX, and --tmpdir is implied.',
        'Files are created u+rw, and directories u+rwx, minus umask restrictions.'
    )
    Options     = @(
        @{ Short = 'd'; Long = 'directory'; Help = 'create a directory, not a file' }
        @{ Short = 'u'; Long = 'dry-run'; Help = 'do not create anything; merely print a name (unsafe)' }
        @{ Short = 'q'; Long = 'quiet'; Help = 'suppress diagnostics about file/dir-creation failure' }
        @{ Long = 'suffix'; Arg = 'SUFF'; Help = 'append SUFF to TEMPLATE; SUFF must not contain a slash' }
        # GNU: -p always takes DIR; only the long form has an optional argument.
        @{ Short = 'p'; Key = 'tmpdir'; Arg = 'DIR'; Help = 'same as --tmpdir=DIR' }
        @{ Long = 'tmpdir'; Arg = 'DIR'; OptionalArg = $true; Help = 'interpret TEMPLATE relative to DIR; if DIR is not specified, use $TMPDIR if set, else the system temp directory' }
        @{ Short = 't'; Help = 'interpret TEMPLATE as a single file name component, relative to a directory: $TMPDIR, if set; else the directory specified via -p; else the system temp directory [deprecated]' }
    )
    Notes       = @('PowerShell note: the system temp directory is [System.IO.Path]::GetTempPath() (e.g. %TEMP% on Windows, /tmp on Linux).')
}

function Invoke-GnuMktemp {
    <#
    .SYNOPSIS
    GNU mktemp: create a temporary file or directory and print its name.

    .DESCRIPTION
    Replaces the trailing X's of TEMPLATE (default tmp.XXXXXXXXXX in the temp directory) with
    random letters and digits, creates the file (or directory with -d) and prints its path.
    Enable the GNU name with: Enable-GnuAlias mktemp

    .EXAMPLE
    $file = Invoke-GnuMktemp

    .EXAMPLE
    Invoke-GnuMktemp -d --tmpdir build.XXXXXX
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'mktemp' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            New-GnuTemporaryItem -Context $ctx
        }
        Complete-GnuUtil -Context $ctx
    }
}

function Get-GnuTempDirectory {
    <#
    .SYNOPSIS
    $TMPDIR if set, else the system temp directory, without a trailing separator.
    #>
    $directory = [string]$env:TMPDIR
    if (-not $directory) { $directory = [System.IO.Path]::GetTempPath() }
    $trimmed = $directory.TrimEnd((Get-GnuPathSeparator))
    if ([string]::IsNullOrEmpty($trimmed) -or $trimmed -match '^[A-Za-z]:$') { return $directory }
    $trimmed
}

function New-GnuTemporaryItem {
    <#
    .SYNOPSIS
    Implementation of mktemp.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $operands = @($Context.Operands)
    if ($operands.Count -gt 1) {
        Write-GnuUsageError -Context $Context -Message "too many templates"
        return
    }

    $quiet = Test-GnuOption -Context $Context -Key 'quiet'
    $makeDirectory = Test-GnuOption -Context $Context -Key 'directory'
    $template = 'tmp.XXXXXXXXXX'
    $useTempDirectory = $true
    if ($operands.Count -eq 1) {
        $template = $operands[0]
        $useTempDirectory = (Test-GnuOption -Context $Context -Key 'tmpdir') -or (Test-GnuOption -Context $Context -Key 't')
    }

    $suffix = ''
    if (Test-GnuOption -Context $Context -Key 'suffix') {
        $suffix = [string](Get-GnuOptionValue -Context $Context -Key 'suffix')
        if ($suffix.IndexOfAny((Get-GnuPathSeparator)) -ge 0) {
            Write-GnuError -Context $Context -Message "invalid suffix '$suffix', contains directory separator"
            return
        }
    }
    elseif ($template -match '^(.*X{3,})([^X]*)$' -and $Matches[2].IndexOfAny((Get-GnuPathSeparator)) -lt 0) {
        # GNU: text after the last run of X's is an implicit suffix.
        $template = $Matches[1]
        $suffix = $Matches[2]
    }

    $xCount = $template.Length - $template.TrimEnd('X').Length
    if ($xCount -lt 3) {
        Write-GnuError -Context $Context -Message "too few X's in template '$($template + $suffix)'"
        return
    }

    $directory = ''
    if ($useTempDirectory) {
        if ([System.IO.Path]::IsPathRooted($template)) {
            Write-GnuError -Context $Context -Message "invalid template, '$template'; with --tmpdir, it may not be absolute"
            return
        }
        $directory = Get-GnuTempDirectory
        if ((Test-GnuOption -Context $Context -Key 'tmpdir') -and (Get-GnuOptionValue -Context $Context -Key 'tmpdir')) {
            $directory = [string](Get-GnuOptionValue -Context $Context -Key 'tmpdir')
        }
    }

    $stem = $template.Substring(0, $template.Length - $xCount)
    $dryRun = Test-GnuOption -Context $Context -Key 'dry-run'
    $lastError = $null
    for ($attempt = 0; $attempt -lt 100; $attempt++) {
        $name = $stem + (New-GnuRandomText -Length $xCount) + $suffix
        $display = $name
        if ($directory) { $display = [System.IO.Path]::Combine($directory, $name) }
        $path = Resolve-GnuPath -Path $display

        # Directories and dry runs need an explicit check; for files, CreateNew detects collisions atomically.
        $taken = [System.IO.File]::Exists($path) -or [System.IO.Directory]::Exists($path)
        if ($taken -and ($makeDirectory -or $dryRun -or [System.IO.Directory]::Exists($path))) { continue }
        if ($dryRun) { return $display }

        try {
            if ($makeDirectory) {
                $parent = Get-GnuParentPath -Path $path
                if ($parent -and -not [System.IO.Directory]::Exists($parent)) { throw (New-Object System.IO.DirectoryNotFoundException $parent) }
                $null = [System.IO.Directory]::CreateDirectory($path)
                $null = Set-GnuUnixMode -Path $path -Mode 448     # 0700
            }
            else {
                $stream = New-Object System.IO.FileStream -ArgumentList $path, ([System.IO.FileMode]::CreateNew), ([System.IO.FileAccess]::Write)
                $stream.Dispose()
                $null = Set-GnuUnixMode -Path $path -Mode 384     # 0600
            }
            return $display
        }
        catch {
            $lastError = $_.Exception
            if ([System.IO.File]::Exists($path)) {
                # The name was taken: not an error, try another one.
                $lastError = $null
                continue
            }
            break
        }
    }

    $kind = 'file'
    if ($makeDirectory) { $kind = 'directory' }
    $reason = 'File exists'
    if ($null -ne $lastError) { $reason = Get-GnuErrorReason -Exception $lastError }
    if ($quiet) {
        $Context.ExitCode = 1
    }
    else {
        Write-GnuError -Context $Context -Message "failed to create $kind via template '$($template + $suffix)': $reason"
    }
}

function New-GnuRandomText {
    <#
    .SYNOPSIS
    Length random characters from [A-Za-z0-9], from a cryptographic random number generator.
    #>
    param([Parameter(Mandatory)][int]$Length)

    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    $bytes = New-Object byte[] $Length
    $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $random.GetBytes($bytes) }
    finally { $random.Dispose() }
    -join @(foreach ($byte in $bytes) { $alphabet[$byte % $alphabet.Length] })
}
