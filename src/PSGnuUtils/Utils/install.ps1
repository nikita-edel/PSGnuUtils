Register-GnuUtil @{
    Name         = 'install'
    Category     = 'File and directory operations'
    Synopsis     = 'Copy files and set attributes.'
    Usage        = @(
        'install [OPTION]... [-T] SOURCE DEST',
        'install [OPTION]... SOURCE... DIRECTORY',
        'install [OPTION]... -t DIRECTORY SOURCE...',
        'install [OPTION]... -d DIRECTORY...'
    )
    Description  = @(
        'This install program copies files (often just compiled) into destination',
        'locations you choose.  If you want to download and install a ready-to-use',
        'package on a GNU/Linux system, you should instead be using a package manager.',
        '',
        'In the first three forms, copy SOURCE to DEST or multiple SOURCE(s) to',
        'the existing DIRECTORY, while setting permission modes and owner/group.',
        'In the 4th form, create all components of the given DIRECTORY(ies).'
    )
    FileOperands = $true
    Options      = @(
        @{ Short = 'c'; Help = '(ignored)' }
        @{ Short = 'C'; Long = 'compare'; Help = 'compare content of source and destination files, and if no change to content, ownership, and permissions, do not modify the destination at all' }
        @{ Short = 'd'; Long = 'directory'; Help = 'treat all arguments as directory names; create all components of the specified directories' }
        @{ Short = 'D'; Help = 'create all leading components of DEST except the last, or all components of --target-directory, then copy SOURCE to DEST' }
        @{ Short = 'g'; Long = 'group'; Arg = 'GROUP'; Help = 'set group ownership, instead of process'' current group' }
        @{ Short = 'm'; Long = 'mode'; Arg = 'MODE'; Help = 'set permission mode (as in chmod), instead of rwxr-xr-x' }
        @{ Short = 'o'; Long = 'owner'; Arg = 'OWNER'; Help = 'set ownership (super-user only)' }
        @{ Short = 'p'; Long = 'preserve-timestamps'; Help = 'apply access/modification times of SOURCE files to corresponding destination files' }
        @{ Short = 't'; Long = 'target-directory'; Arg = 'DIRECTORY'; Help = 'copy all SOURCE arguments into DIRECTORY' }
        @{ Short = 'T'; Long = 'no-target-directory'; Help = 'treat DEST as a normal file' }
        @{ Short = 'v'; Long = 'verbose'; Help = 'print the name of each directory as it is created' }
    )
    Notes        = @(
        'PowerShell note: only octal modes; modes, -o and -g apply on Unix only (-o / -g run',
        'chown / chgrp). No backups (-b, -S) and no stripping (-s).'
    )
}

function Invoke-GnuInstall {
    <#
    .SYNOPSIS
    GNU install: copy files and set their mode, or create directories.

    .DESCRIPTION
    Copies SOURCE to DEST (or into DIRECTORY / -t DIRECTORY), creating leading directories with
    -D; -d creates directories. -m sets the mode (Unix), -p keeps timestamps, -C skips
    identical files, -v reports every action.
    Enable the GNU name with: Enable-GnuUtil install

    .EXAMPLE
    Invoke-GnuInstall -D -m 755 build/tool ~/.local/bin/tool
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'install' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) { Invoke-GnuInstallFile -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function New-GnuInstallDirectory {
    <#
    .SYNOPSIS
    Creates a directory and its missing parents, reporting each one with -v. Returns $false on failure.
    #>
    param([Parameter(Mandatory)][hashtable]$Context, [Parameter(Mandatory)][string]$Path, [switch]$Report, [Nullable[int]]$Mode)

    $missing = New-Object 'System.Collections.Generic.List[string]'
    $current = Remove-GnuTrailingSeparator -Path $Path
    while (-not (Test-Path -LiteralPath (Resolve-GnuPath -Path $current))) {
        $missing.Insert(0, $current)
        $parent = Get-GnuDirName -Path $current
        if ($parent -eq $current -or $parent -eq '.') { break }
        $current = $parent
    }
    foreach ($directory in $missing) {
        try { $null = [System.IO.Directory]::CreateDirectory((Resolve-GnuPath -Path $directory)) }
        catch {
            Write-GnuError -Context $Context -Message "cannot create directory '$directory': $(Get-GnuErrorReason -Exception $_.Exception)"
            return $false
        }
        if ($Report) { Write-GnuWarning -Context $Context -Message "creating directory '$directory'" }
        if ($null -ne $Mode) { $null = Set-GnuUnixMode -Path (Resolve-GnuPath -Path $directory) -Mode $Mode }
    }
    $true
}

function Test-GnuSameContent {
    <#
    .SYNOPSIS
    $true if two files have the same bytes.
    #>
    param([Parameter(Mandatory)][string]$Left, [Parameter(Mandatory)][string]$Right)
    if ((New-Object System.IO.FileInfo -ArgumentList $Left).Length -ne (New-Object System.IO.FileInfo -ArgumentList $Right).Length) { return $false }
    $a = [System.IO.File]::ReadAllBytes($Left)
    $b = [System.IO.File]::ReadAllBytes($Right)
    for ($i = 0; $i -lt $a.Length; $i++) { if ($a[$i] -ne $b[$i]) { return $false } }
    $true
}

function Invoke-GnuInstallFile {
    <#
    .SYNOPSIS
    Implementation of install.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $operands = @($Context.Operands)
    $report = Test-GnuOption -Context $Context -Key 'verbose'
    $mode = $null
    if (Test-GnuOption -Context $Context -Key 'mode') {
        $modeText = [string](Get-GnuOptionValue -Context $Context -Key 'mode')
        if ($modeText -notmatch '^[0-7]{1,4}$') { Write-GnuError -Context $Context -Message "invalid mode '$modeText' (only octal modes are supported)"; return }
        $mode = [System.Convert]::ToInt32($modeText, 8)
    }

    if (Test-GnuOption -Context $Context -Key 'directory') {
        if ($operands.Count -eq 0) { Write-GnuUsageError -Context $Context -Message 'missing file operand'; return }
        foreach ($directory in $operands) { $null = New-GnuInstallDirectory -Context $Context -Path $directory -Report:$report -Mode $mode }
        return
    }

    $targetDirectory = $null
    if (Test-GnuOption -Context $Context -Key 'target-directory') { $targetDirectory = [string](Get-GnuOptionValue -Context $Context -Key 'target-directory') }
    $noTarget = Test-GnuOption -Context $Context -Key 'no-target-directory'
    if ($null -ne $targetDirectory -and $noTarget) { Write-GnuUsageError -Context $Context -Message 'cannot combine --target-directory (-t) and --no-target-directory (-T)'; return }
    if ($operands.Count -eq 0) { Write-GnuUsageError -Context $Context -Message 'missing file operand'; return }
    if ($null -eq $targetDirectory -and $operands.Count -eq 1) { Write-GnuUsageError -Context $Context -Message "missing destination file operand after '$($operands[0])'"; return }

    $pairs = New-Object 'System.Collections.Generic.List[object]'
    $leading = Test-GnuOption -Context $Context -Key 'D'
    if ($null -ne $targetDirectory) {
        if ($leading -and -not (New-GnuInstallDirectory -Context $Context -Path $targetDirectory -Report:$report)) { return }
        foreach ($source in $operands) { $pairs.Add(@($source, (Join-GnuDisplayPath -Directory $targetDirectory -Leaf (Get-GnuBaseName -Path $source)))) }
    }
    else {
        $destination = $operands[$operands.Count - 1]
        $sources = @($operands[0..($operands.Count - 2)])
        $isDirectory = [System.IO.Directory]::Exists((Resolve-GnuPath -Path $destination))
        if ($noTarget -and $sources.Count -gt 1) { Write-GnuUsageError -Context $Context -Message "extra operand '$destination'"; return }
        if ($sources.Count -gt 1 -and -not $isDirectory) { Write-GnuError -Context $Context -Message "target '$destination' is not a directory"; return }
        if ($isDirectory -and -not $noTarget) {
            foreach ($source in $sources) { $pairs.Add(@($source, (Join-GnuDisplayPath -Directory $destination -Leaf (Get-GnuBaseName -Path $source)))) }
        }
        else {
            if ($leading -and -not (New-GnuInstallDirectory -Context $Context -Path (Get-GnuDirName -Path $destination) -Report:$report)) { return }
            $pairs.Add(@($sources[0], $destination))
        }
    }

    foreach ($pair in $pairs) {
        $source = $pair[0]
        $target = $pair[1]
        $sourcePath = Resolve-GnuPath -Path $source
        $targetPath = Resolve-GnuPath -Path $target
        if (-not [System.IO.File]::Exists($sourcePath)) {
            if ([System.IO.Directory]::Exists($sourcePath)) { Write-GnuError -Context $Context -Message "omitting directory '$source'" }
            else { Write-GnuError -Context $Context -Message "cannot stat '$source': No such file or directory" }
            continue
        }
        if ([System.IO.Directory]::Exists($targetPath)) { Write-GnuError -Context $Context -Message "cannot overwrite directory '$target' with non-directory"; continue }
        if (Test-GnuSamePath -Left $sourcePath -Right $targetPath) { Write-GnuError -Context $Context -Message "'$source' and '$target' are the same file"; continue }
        if ((Test-GnuOption -Context $Context -Key 'compare') -and [System.IO.File]::Exists($targetPath) -and (Test-GnuSameContent -Left $sourcePath -Right $targetPath)) { continue }
        try {
            [System.IO.File]::Copy($sourcePath, $targetPath, $true)
            if (Test-GnuOption -Context $Context -Key 'preserve-timestamps') {
                [System.IO.File]::SetLastWriteTimeUtc($targetPath, [System.IO.File]::GetLastWriteTimeUtc($sourcePath))
                [System.IO.File]::SetLastAccessTimeUtc($targetPath, [System.IO.File]::GetLastAccessTimeUtc($sourcePath))
            }
        }
        catch {
            Write-GnuError -Context $Context -Message "cannot create regular file '$target': $(Get-GnuErrorReason -Exception $_.Exception)"
            continue
        }
        if ($report) { "'$source' -> '$target'" }
        $fileMode = 493   # 0755
        if ($null -ne $mode) { $fileMode = $mode }
        $null = Set-GnuUnixMode -Path $targetPath -Mode $fileMode
        foreach ($owner in @(@('owner', 'chown'), @('group', 'chgrp'))) {
            if (-not (Test-GnuOption -Context $Context -Key $owner[0])) { continue }
            $value = [string](Get-GnuOptionValue -Context $Context -Key $owner[0])
            if (Test-GnuWindows) { Write-GnuWarning -Context $Context -Message "--$($owner[0]) is ignored on Windows"; continue }
            $process = Start-Process -FilePath $owner[1] -ArgumentList @($value, $targetPath) -NoNewWindow -Wait -PassThru
            if ($process.ExitCode -ne 0) { Write-GnuError -Context $Context -Message "cannot change $($owner[0]) of '$target' to '$value'" }
        }
    }
}
