Register-GnuUtil @{
    Name         = 'rm'
    Category     = 'File and directory operations'
    Synopsis     = 'Remove files or directories.'
    Usage        = @('rm [OPTION]... [FILE]...')
    Description  = @('Remove (unlink) the FILE(s).')
    FileOperands = $true
    Options      = @(
        @{ Short = 'f'; Long = 'force'; Key = 'interactive'; Value = 'never'; Sets = @{ force = 1 }; Help = 'ignore nonexistent files and arguments, never prompt' }
        @{ Short = 'i'; Key = 'interactive'; Value = 'always'; Help = 'prompt before every removal' }
        @{ Short = 'I'; Key = 'interactive'; Value = 'once'; Help = 'prompt once before removing more than three files, or when removing recursively; less intrusive than -i, while still giving protection against most mistakes' }
        @{ Long = 'interactive'; Key = 'interactive-when'; Arg = 'WHEN'; OptionalArg = $true; Help = 'prompt according to WHEN: never, once (-I), or always (-i); without WHEN, prompt always' }
        @{ Long = 'one-file-system'; Help = 'when removing a hierarchy recursively, skip any directory that is on a file system different from that of the corresponding command line argument (accepted; links are never followed anyway)' }
        @{ Long = 'no-preserve-root'; Key = 'preserve-root'; Value = 'no'; Help = 'do not treat ''/'' specially' }
        @{ Long = 'preserve-root'; Arg = 'all'; OptionalArg = $true; Help = 'do not remove ''/'' (default); with ''all'', reject any command line argument on a separate device from its parent' }
        @{ Short = 'r'; Long = 'recursive'; Key = 'recursive'; Help = 'remove directories and their contents recursively' }
        @{ Short = 'R'; Key = 'recursive'; Help = 'same as -r' }
        @{ Short = 'd'; Long = 'dir'; Help = 'remove empty directories' }
        @{ Short = 'v'; Long = 'verbose'; Help = 'explain what is being done' }
    )
    Notes        = @(
        'By default, rm does not remove directories.  Use the --recursive (-r or -R)',
        'option to remove each listed directory, too, along with all of its contents.',
        '',
        'To remove a file whose name starts with a ''-'', for example ''-foo'',',
        'use one of these commands:',
        '  rm -- -foo',
        '',
        '  rm ./-foo',
        '',
        'Symbolic links and junctions are removed themselves; rm never descends into their targets.',
        '',
        'PowerShell notes: read-only files are removed (like GNU rm when standard input is not a terminal).',
        'File system objects from the pipeline (Get-ChildItem *.tmp | rm) are removed as extra FILE operands;',
        'other pipeline input is ignored. Drive roots such as C:\ are protected like ''/''.'
    )
}

function Invoke-GnuRm {
    <#
    .SYNOPSIS
    GNU rm: remove files or directories.

    .DESCRIPTION
    Removes every FILE. Directories need -r (recursive) or -d (empty only). -f ignores missing
    files and never prompts, -i prompts for every removal, -I once for large or recursive
    removals. Links and junctions are removed themselves, never followed. '/' and drive roots
    are refused unless --no-preserve-root is given, and '.' / '..' are always refused.
    File system objects piped in (Get-ChildItem *.tmp | Invoke-GnuRm) are removed too.
    Enable the GNU name with: Enable-GnuUtil rm (replaces the rm -> Remove-Item alias).

    .EXAMPLE
    Invoke-GnuRm -rf build

    .EXAMPLE
    Invoke-GnuRm -v *.tmp

    removed 'a.tmp'
    removed 'b.tmp'
    #>
    begin {
        $ctx = Initialize-GnuUtil -Name 'rm' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput
        $piped = New-Object 'System.Collections.Generic.List[string]'
    }
    process {
        if (-not $ctx.Done -and $_ -is [System.IO.FileSystemInfo]) { $piped.Add($_.FullName) }
    }
    end {
        if (-not $ctx.Done) { Invoke-GnuRemove -Context $ctx -Extra $piped.ToArray() }
        Complete-GnuUtil -Context $ctx
    }
}

function Read-GnuConfirmation {
    <#
    .SYNOPSIS
    Writes a GNU style prompt to standard error and returns $true if the answer starts with y or Y.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$Question
    )

    [System.Console]::Error.Write("$($Context.Name): $Question ")
    $answer = [System.Console]::In.ReadLine()
    $null -ne $answer -and $answer -match '^[yY]'
}

function Test-GnuRootPath {
    <#
    .SYNOPSIS
    $true if Path is a file system root ('/', 'C:\', '\\server\share\').
    #>
    param([Parameter(Mandatory)][string]$Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($full)
    -not [string]::IsNullOrEmpty($root) -and [string]::Equals($full.TrimEnd((Get-GnuPathSeparator)), $root.TrimEnd((Get-GnuPathSeparator)), [System.StringComparison]::OrdinalIgnoreCase)
}

function Invoke-GnuRemove {
    <#
    .SYNOPSIS
    Implementation of rm: validates options and removes every operand.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [AllowEmptyCollection()][string[]]$Extra = @()
    )

    $mode = [string](Get-GnuOptionValue -Context $Context -Key 'interactive' -Default 'default')
    if (Test-GnuOption -Context $Context -Key 'interactive-when') {
        $when = [string](Get-GnuOptionValue -Context $Context -Key 'interactive-when')
        switch -Regex ($when) {
            '^$|^(always|yes)$' { $mode = 'always' }
            '^(never|no|none)$' { $mode = 'never' }
            '^once$' { $mode = 'once' }
            default {
                Write-GnuUsageError -Context $Context -Message "invalid argument '$when' for '--interactive'`nValid arguments are: 'never', 'no', 'none', 'once', 'always', 'yes'"
                return
            }
        }
    }

    $settings = @{
        Mode      = $mode
        Force     = Test-GnuOption -Context $Context -Key 'force'
        Recursive = Test-GnuOption -Context $Context -Key 'recursive'
        Dirs      = Test-GnuOption -Context $Context -Key 'dir'
        Verbose   = Test-GnuOption -Context $Context -Key 'verbose'
        Preserve  = (Get-GnuOptionValue -Context $Context -Key 'preserve-root' -Default 'yes') -ne 'no'
        Output    = New-Object 'System.Collections.Generic.List[string]'   # -v messages (statuses use the pipeline)
    }

    $operands = @(@($Context.Operands) + @($Extra))
    if ($operands.Count -eq 0) {
        if (-not $settings.Force) { Write-GnuUsageError -Context $Context -Message 'missing operand' }
        return
    }

    if ($mode -eq 'once' -and ($operands.Count -gt 3 -or $settings.Recursive)) {
        $plural = ''
        if ($operands.Count -ne 1) { $plural = 's' }
        $how = ''
        if ($settings.Recursive) { $how = ' recursively' }
        if (-not (Read-GnuConfirmation -Context $Context -Question "remove $($operands.Count) argument$plural$($how)?")) { return }
    }

    foreach ($operand in $operands) {
        if ([string]::IsNullOrEmpty($operand)) {
            Write-GnuError -Context $Context -Message "cannot remove '': No such file or directory"
            continue
        }
        $leaf = Get-GnuBaseName -Path $operand
        if (($settings.Recursive -or $settings.Dirs) -and ($leaf -eq '.' -or $leaf -eq '..')) {
            Write-GnuError -Context $Context -Message "refusing to remove '.' or '..' directory: skipping '$operand'"
            continue
        }

        $path = Resolve-GnuPath -Path $operand
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            if (-not $settings.Force) { Write-GnuError -Context $Context -Message "cannot remove '$operand': No such file or directory" }
            continue
        }
        if ($settings.Preserve -and $settings.Recursive -and (Test-GnuRootPath -Path $path)) {
            Write-GnuError -Context $Context -Message "it is dangerous to operate recursively on '$operand'`nrm: use --no-preserve-root to override this failsafe"
            continue
        }
        $null = Remove-GnuRmItem -Context $Context -Item $item -Display $operand -Settings $settings
        foreach ($line in $settings.Output) { $line }
        $settings.Output.Clear()
    }
}

function Remove-GnuRmItem {
    <#
    .SYNOPSIS
    Removes one file, link or directory tree. Returns 'removed', 'skipped' or 'failed'.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][System.IO.FileSystemInfo]$Item,
        [Parameter(Mandatory)][string]$Display,
        [Parameter(Mandatory)][hashtable]$Settings
    )

    $path = $Item.FullName
    $isLink = $Item.LinkType -eq 'SymbolicLink' -or $Item.LinkType -eq 'Junction'
    $always = $Settings.Mode -eq 'always'

    try {
        if ($Item -is [System.IO.DirectoryInfo] -and -not $isLink) {
            $entries = @([System.IO.Directory]::GetFileSystemEntries($path))
            if (-not $Settings.Recursive) {
                if (-not $Settings.Dirs) {
                    Write-GnuError -Context $Context -Message "cannot remove '$Display': Is a directory"
                    return 'failed'
                }
                if ($entries.Count -gt 0) {
                    Write-GnuError -Context $Context -Message "cannot remove '$Display': Directory not empty"
                    return 'failed'
                }
            }

            if ($entries.Count -gt 0) {
                if ($always -and -not (Read-GnuConfirmation -Context $Context -Question "descend into directory '$Display'?")) { return 'skipped' }
                [System.Array]::Sort($entries, [System.StringComparer]::Ordinal)
                $kept = $false
                foreach ($entry in $entries) {
                    $child = Get-Item -LiteralPath $entry -Force
                    $childDisplay = $Display.TrimEnd((Get-GnuPathSeparator)) + '/' + $child.Name
                    $status = Remove-GnuRmItem -Context $Context -Item $child -Display $childDisplay -Settings $Settings
                    if ($status -ne 'removed') { $kept = $true }
                }
                if ($kept) { return 'skipped' }   # children were kept; GNU leaves the directory alone
            }

            if ($always -and -not (Read-GnuConfirmation -Context $Context -Question "remove directory '$Display'?")) { return 'skipped' }
            $Item.Attributes = [System.IO.FileAttributes]::Directory
            [System.IO.Directory]::Delete($path, $false)
            if ($Settings.Verbose) { $Settings.Output.Add("removed directory '$Display'") }
            return 'removed'
        }

        if ($always) {
            $kind = 'regular file'
            if ($isLink) { $kind = 'symbolic link' }
            elseif ($Item -is [System.IO.FileInfo] -and $Item.Length -eq 0) { $kind = 'regular empty file' }
            if (-not (Read-GnuConfirmation -Context $Context -Question "remove $kind '$Display'?")) { return 'skipped' }
        }

        if ($Item -is [System.IO.DirectoryInfo]) {
            # A link to a directory: delete the link only, never the target.
            [System.IO.Directory]::Delete($path, $false)
        }
        else {
            if (-not $isLink -and ($Item.Attributes -band [System.IO.FileAttributes]::ReadOnly)) { $Item.Attributes = [System.IO.FileAttributes]::Normal }
            [System.IO.File]::Delete($path)
        }
        if ($Settings.Verbose) { $Settings.Output.Add("removed '$Display'") }
        'removed'
    }
    catch {
        Write-GnuError -Context $Context -Message "cannot remove '$Display': $(Get-GnuErrorReason -Exception $_.Exception)"
        'failed'
    }
}
