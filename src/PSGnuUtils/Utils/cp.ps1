Register-GnuUtil @{
    Name         = 'cp'
    Category     = 'File and directory operations'
    Synopsis     = 'Copy files and directories.'
    Usage        = @(
        'cp [OPTION]... [-T] SOURCE DEST',
        'cp [OPTION]... SOURCE... DIRECTORY',
        'cp [OPTION]... -t DIRECTORY SOURCE...'
    )
    Description  = @('Copy SOURCE to DEST, or multiple SOURCE(s) to DIRECTORY.')
    FileOperands = $true
    Options      = @(
        @{ Short = 'a'; Long = 'archive'; Key = 'deref'; Value = 'never'; Sets = @{ recursive = 1; preserve = 'all' }; Help = 'same as -dR --preserve=all' }
        @{ Short = 'd'; Key = 'deref'; Value = 'never'; Sets = @{ 'preserve-links' = 1 }; Help = 'same as --no-dereference --preserve=links' }
        @{ Short = 'f'; Long = 'force'; Key = 'clobber'; Value = 'force'; Help = 'if an existing destination file cannot be opened, remove it and try again' }
        @{ Short = 'i'; Long = 'interactive'; Key = 'clobber'; Value = 'ask'; Help = 'prompt before overwrite (overrides a previous -n option)' }
        @{ Short = 'l'; Long = 'link'; Key = 'make'; Value = 'hard'; Help = 'hard link files instead of copying' }
        @{ Short = 'L'; Long = 'dereference'; Key = 'deref'; Value = 'always'; Help = 'always follow symbolic links in SOURCE' }
        @{ Short = 'n'; Long = 'no-clobber'; Key = 'clobber'; Value = 'no'; Help = 'do not overwrite an existing file (overrides a previous -i option)' }
        @{ Short = 'P'; Long = 'no-dereference'; Key = 'deref'; Value = 'never'; Help = 'never follow symbolic links in SOURCE' }
        @{ Short = 'p'; Key = 'preserve'; Value = 'mode,ownership,timestamps'; Help = 'same as --preserve=mode,ownership,timestamps' }
        @{ Long = 'preserve'; Arg = 'ATTR_LIST'; OptionalArg = $true; Help = 'preserve the specified attributes (default: mode,ownership,timestamps), if possible additional attributes: context, links, xattr, all' }
        @{ Long = 'no-preserve'; Arg = 'ATTR_LIST'; Help = "don't preserve the specified attributes" }
        @{ Short = 'R'; Key = 'recursive'; Help = 'copy directories recursively' }
        @{ Short = 'r'; Long = 'recursive'; Help = 'copy directories recursively' }
        @{ Short = 's'; Long = 'symbolic-link'; Key = 'make'; Value = 'symbolic'; Help = 'make symbolic links instead of copying' }
        @{ Short = 't'; Long = 'target-directory'; Arg = 'DIRECTORY'; Help = 'copy all SOURCE arguments into DIRECTORY' }
        @{ Short = 'T'; Long = 'no-target-directory'; Help = 'treat DEST as a normal file' }
        @{ Short = 'u'; Long = 'update'; Help = 'copy only when the SOURCE file is newer than the destination file or when the destination file is missing' }
        @{ Short = 'v'; Long = 'verbose'; Help = 'explain what is being done' }
    )
    Notes        = @(
        'By default, sparse SOURCE files are detected by a crude heuristic and the',
        'corresponding DEST file is made sparse as well.',
        '',
        'PowerShell notes: "timestamps" and "mode" (file attributes on Windows, permissions on Unix) can be',
        'preserved; ownership, context and xattr are accepted and ignored. Without -L, -r copies symbolic',
        'links and junctions as links. Backups (-b, -S) and --parents are not supported.'
    )
}

function Invoke-GnuCp {
    <#
    .SYNOPSIS
    GNU cp: copy files and directories.

    .DESCRIPTION
    Copies SOURCE to DEST or every SOURCE into DIRECTORY. -r copies directory trees (links are
    copied as links unless -L), -p / --preserve keeps timestamps and attributes, -n / -i / -u
    control overwriting, -l / -s create links instead of copies, -v reports every copy.
    Enable the GNU name with: Enable-GnuUtil cp (replaces the cp -> Copy-Item alias).

    .EXAMPLE
    Invoke-GnuCp -rv src backup

    .EXAMPLE
    Invoke-GnuCp -p *.cfg /etc/myapp/
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'cp' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) { Invoke-GnuCopy -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function Invoke-GnuCopy {
    <#
    .SYNOPSIS
    Implementation of cp: validates options and copies every planned pair.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $recursive = Test-GnuOption -Context $Context -Key 'recursive'
    $preserveList = @()
    if (Test-GnuOption -Context $Context -Key 'preserve') {
        $value = [string](Get-GnuOptionValue -Context $Context -Key 'preserve')
        if ([string]::IsNullOrEmpty($value)) { $value = 'mode,ownership,timestamps' }
        $preserveList = @($value.Split(','))
    }
    foreach ($attribute in $preserveList) {
        if (@('mode', 'ownership', 'timestamps', 'links', 'context', 'xattr', 'all') -notcontains $attribute) {
            Write-GnuUsageError -Context $Context -Message "invalid argument '$attribute' for '--preserve'"
            return
        }
    }
    $removed = @()
    if (Test-GnuOption -Context $Context -Key 'no-preserve') { $removed = @(([string](Get-GnuOptionValue -Context $Context -Key 'no-preserve')).Split(',')) }
    $wants = {
        param($Name)
        ($preserveList -contains $Name -or $preserveList -contains 'all') -and $removed -notcontains $Name -and $removed -notcontains 'all'
    }

    $default = 'always'
    if ($recursive) { $default = 'never' }
    $settings = @{
        Recursive  = $recursive
        Clobber    = [string](Get-GnuOptionValue -Context $Context -Key 'clobber' -Default 'overwrite')
        Update     = Test-GnuOption -Context $Context -Key 'update'
        Verbose    = Test-GnuOption -Context $Context -Key 'verbose'
        Make       = [string](Get-GnuOptionValue -Context $Context -Key 'make' -Default 'copy')
        Follow     = ([string](Get-GnuOptionValue -Context $Context -Key 'deref' -Default $default)) -eq 'always'
        Timestamps = & $wants 'timestamps'
        Mode       = & $wants 'mode'
        Output     = New-Object 'System.Collections.Generic.List[string]'
    }

    foreach ($pair in @(Get-GnuTransferPlan -Context $Context)) {
        $sourcePath = Resolve-GnuPath -Path $pair.Source
        $targetPath = Resolve-GnuPath -Path $pair.Target
        $source = Get-Item -LiteralPath $sourcePath -Force -ErrorAction SilentlyContinue
        if ($null -eq $source) {
            Write-GnuError -Context $Context -Message "cannot stat '$($pair.Source)': No such file or directory"
            continue
        }
        $isDirectory = $source -is [System.IO.DirectoryInfo] -and ($settings.Follow -or $null -eq (Get-GnuLinkTarget -Path $sourcePath))
        if ($isDirectory -and -not $recursive) {
            Write-GnuError -Context $Context -Message "-r not specified; omitting directory '$($pair.Source)'"
            continue
        }
        if ($isDirectory -and (Test-GnuInsidePath -Path $targetPath -Ancestor $sourcePath)) {
            Write-GnuError -Context $Context -Message "cannot copy a directory, '$($pair.Source)', into itself, '$($pair.Target)'"
            continue
        }
        Copy-GnuCpItem -Context $Context -Source $source -SourceDisplay $pair.Source -TargetPath $targetPath -TargetDisplay $pair.Target -Settings $settings
        foreach ($line in $settings.Output) { $line }
        $settings.Output.Clear()
    }
}

function Copy-GnuCpItem {
    <#
    .SYNOPSIS
    Copies one file, link or directory tree (recursively), reporting GNU style errors.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][System.IO.FileSystemInfo]$Source,
        [Parameter(Mandatory)][string]$SourceDisplay,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$TargetDisplay,
        [Parameter(Mandatory)][hashtable]$Settings
    )

    $linkTarget = Get-GnuLinkTarget -Path $Source.FullName
    $target = Get-Item -LiteralPath $TargetPath -Force -ErrorAction SilentlyContinue
    try {
        if ($null -ne $linkTarget -and -not $Settings.Follow) {
            if ($null -ne $target) {
                if ($Settings.Clobber -eq 'no') { return }
                if ($target -is [System.IO.DirectoryInfo]) { [System.IO.Directory]::Delete($TargetPath, $false) } else { [System.IO.File]::Delete($TargetPath) }
            }
            if ($Source.LinkType -eq 'Junction') {
                $null = New-Item -ItemType Junction -Path ([System.Management.Automation.WildcardPattern]::Escape($TargetPath)) -Value $linkTarget -ErrorAction Stop
            }
            else {
                New-GnuSymbolicLink -Path $TargetPath -Target $linkTarget -Directory:($Source -is [System.IO.DirectoryInfo])
            }
            if ($Settings.Verbose) { $Settings.Output.Add("'$SourceDisplay' -> '$TargetDisplay'") }
            return
        }

        if ($Source -is [System.IO.DirectoryInfo]) {
            if ($null -ne $target -and $target -isnot [System.IO.DirectoryInfo]) {
                Write-GnuError -Context $Context -Message "cannot overwrite non-directory '$TargetDisplay' with directory '$SourceDisplay'"
                return
            }
            if ($null -eq $target) {
                $null = [System.IO.Directory]::CreateDirectory($TargetPath)
                if ($Settings.Verbose) { $Settings.Output.Add("'$SourceDisplay' -> '$TargetDisplay'") }
            }
            $entries = @([System.IO.Directory]::GetFileSystemEntries($Source.FullName))
            [System.Array]::Sort($entries, [System.StringComparer]::Ordinal)
            foreach ($entry in $entries) {
                $child = Get-Item -LiteralPath $entry -Force
                Copy-GnuCpItem -Context $Context -Source $child -SourceDisplay (Join-GnuDisplayPath -Directory $SourceDisplay -Leaf $child.Name) `
                    -TargetPath ([System.IO.Path]::Combine($TargetPath, $child.Name)) -TargetDisplay (Join-GnuDisplayPath -Directory $TargetDisplay -Leaf $child.Name) -Settings $Settings
            }
            if ($Settings.Mode) { [System.IO.File]::SetAttributes($TargetPath, $Source.Attributes) }
            if ($Settings.Timestamps) {
                [System.IO.Directory]::SetLastWriteTime($TargetPath, $Source.LastWriteTime)
                [System.IO.Directory]::SetLastAccessTime($TargetPath, $Source.LastAccessTime)
            }
            return
        }

        $sourceFile = $Source.FullName
        if ($null -ne $target) {
            if (Test-GnuSamePath -Left $sourceFile -Right $TargetPath) {
                Write-GnuError -Context $Context -Message "'$SourceDisplay' and '$TargetDisplay' are the same file"
                return
            }
            if ($target -is [System.IO.DirectoryInfo] -and $null -eq (Get-GnuLinkTarget -Path $TargetPath)) {
                Write-GnuError -Context $Context -Message "cannot overwrite directory '$TargetDisplay' with non-directory"
                return
            }
            if ($Settings.Clobber -eq 'no') { return }
            if ($Settings.Update -and $target.LastWriteTime -ge $Source.LastWriteTime) { return }
            if ($Settings.Clobber -eq 'ask' -and -not (Read-GnuConfirmation -Context $Context -Question "overwrite '$TargetDisplay'?")) { return }
        }

        switch ($Settings.Make) {
            'hard' {
                if ($null -ne $target) { [System.IO.File]::Delete($TargetPath) }
                $null = New-Item -ItemType HardLink -Path ([System.Management.Automation.WildcardPattern]::Escape($TargetPath)) -Value $sourceFile -ErrorAction Stop
            }
            'symbolic' {
                if ($null -ne $target) { [System.IO.File]::Delete($TargetPath) }
                New-GnuSymbolicLink -Path $TargetPath -Target $sourceFile
            }
            default {
                try {
                    [System.IO.File]::Copy($sourceFile, $TargetPath, $true)
                }
                catch {
                    # GNU -f: remove a destination that cannot be opened and try again.
                    if ($Settings.Clobber -ne 'force' -or $null -eq $target) { throw }
                    $target.Attributes = [System.IO.FileAttributes]::Normal
                    [System.IO.File]::Delete($TargetPath)
                    [System.IO.File]::Copy($sourceFile, $TargetPath, $true)
                }
                # File.Copy keeps the attributes (like GNU keeps the mode bits) and, on Windows, the modification
                # time; GNU cp keeps the times only with --preserve=timestamps.
                $now = [datetime]::Now
                if ($Settings.Timestamps) {
                    [System.IO.File]::SetLastWriteTime($TargetPath, $Source.LastWriteTime)
                    [System.IO.File]::SetLastAccessTime($TargetPath, $Source.LastAccessTime)
                }
                else {
                    [System.IO.File]::SetLastWriteTime($TargetPath, $now)
                    [System.IO.File]::SetLastAccessTime($TargetPath, $now)
                }
            }
        }
        if ($Settings.Verbose) { $Settings.Output.Add("'$SourceDisplay' -> '$TargetDisplay'") }
    }
    catch {
        Write-GnuError -Context $Context -Message "cannot create regular file '$TargetDisplay': $(Get-GnuErrorReason -Exception $_.Exception)"
    }
}
