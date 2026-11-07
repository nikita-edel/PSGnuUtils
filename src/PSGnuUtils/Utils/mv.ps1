Register-GnuUtil @{
    Name         = 'mv'
    Category     = 'File and directory operations'
    Synopsis     = 'Move (rename) files.'
    Usage        = @(
        'mv [OPTION]... [-T] SOURCE DEST',
        'mv [OPTION]... SOURCE... DIRECTORY',
        'mv [OPTION]... -t DIRECTORY SOURCE...'
    )
    Description  = @('Rename SOURCE to DEST, or move SOURCE(s) to DIRECTORY.')
    FileOperands = $true
    Options      = @(
        @{ Short = 'f'; Long = 'force'; Key = 'clobber'; Value = 'force'; Help = 'do not prompt before overwriting' }
        @{ Short = 'i'; Long = 'interactive'; Key = 'clobber'; Value = 'ask'; Help = 'prompt before overwrite' }
        @{ Short = 'n'; Long = 'no-clobber'; Key = 'clobber'; Value = 'no'; Help = 'do not overwrite an existing file' }
        @{ Long = 'strip-trailing-slashes'; Help = 'remove any trailing slashes from each SOURCE argument' }
        @{ Short = 't'; Long = 'target-directory'; Arg = 'DIRECTORY'; Help = 'move all SOURCE arguments into DIRECTORY' }
        @{ Short = 'T'; Long = 'no-target-directory'; Help = 'treat DEST as a normal file' }
        @{ Short = 'u'; Long = 'update'; Help = 'move only when the SOURCE file is newer than the destination file or when the destination file is missing' }
        @{ Short = 'v'; Long = 'verbose'; Help = 'explain what is being done' }
    )
    Notes        = @(
        'If you specify more than one of -i, -f, -n, only the final one takes effect.',
        'PowerShell notes: directories are moved across drives by copying and deleting. Backups (-b, -S) are not supported.'
    )
}

function Invoke-GnuMv {
    <#
    .SYNOPSIS
    GNU mv: move or rename files and directories.

    .DESCRIPTION
    Renames SOURCE to DEST, or moves every SOURCE into DIRECTORY. Existing destinations are
    replaced (-f, default), kept (-n), replaced after asking (-i) or only when older (-u). A
    directory replaces an existing empty directory only.
    Enable the GNU name with: Enable-GnuUtil mv (replaces the mv -> Move-Item alias).

    .EXAMPLE
    Invoke-GnuMv -v draft.txt final.txt

    renamed 'draft.txt' -> 'final.txt'
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'mv' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) { Invoke-GnuMove -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function Invoke-GnuMove {
    <#
    .SYNOPSIS
    Implementation of mv.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    if (Test-GnuOption -Context $Context -Key 'strip-trailing-slashes') {
        $Context.Operands = [string[]]@(foreach ($operand in $Context.Operands) { Remove-GnuTrailingSeparator -Path $operand })
    }
    $clobber = [string](Get-GnuOptionValue -Context $Context -Key 'clobber' -Default 'force')
    $update = Test-GnuOption -Context $Context -Key 'update'
    $verbose = Test-GnuOption -Context $Context -Key 'verbose'

    foreach ($pair in @(Get-GnuTransferPlan -Context $Context)) {
        $sourcePath = Resolve-GnuPath -Path $pair.Source
        $targetPath = Resolve-GnuPath -Path $pair.Target
        $source = Get-Item -LiteralPath $sourcePath -Force -ErrorAction SilentlyContinue
        if ($null -eq $source) {
            Write-GnuError -Context $Context -Message "cannot stat '$($pair.Source)': No such file or directory"
            continue
        }
        $sourceIsDirectory = $source -is [System.IO.DirectoryInfo] -and $null -eq (Get-GnuLinkTarget -Path $sourcePath)
        if (Test-GnuSamePath -Left $sourcePath -Right $targetPath) {
            Write-GnuError -Context $Context -Message "'$($pair.Source)' and '$($pair.Target)' are the same file"
            continue
        }
        if ($sourceIsDirectory -and (Test-GnuInsidePath -Path $targetPath -Ancestor $sourcePath)) {
            Write-GnuError -Context $Context -Message "cannot move '$($pair.Source)' to a subdirectory of itself, '$($pair.Target)'"
            continue
        }

        $target = Get-Item -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue
        if ($null -ne $target) {
            if ($clobber -eq 'no') { continue }
            if ($update -and $target.LastWriteTime -ge $source.LastWriteTime) { continue }
            if ($clobber -eq 'ask' -and -not (Read-GnuConfirmation -Context $Context -Question "overwrite '$($pair.Target)'?")) { continue }
            $targetIsDirectory = $target -is [System.IO.DirectoryInfo] -and $null -eq (Get-GnuLinkTarget -Path $targetPath)
            if ($sourceIsDirectory -and -not $targetIsDirectory) {
                Write-GnuError -Context $Context -Message "cannot overwrite non-directory '$($pair.Target)' with directory '$($pair.Source)'"
                continue
            }
            if (-not $sourceIsDirectory -and $targetIsDirectory) {
                Write-GnuError -Context $Context -Message "cannot overwrite directory '$($pair.Target)' with non-directory"
                continue
            }
            try {
                if ($targetIsDirectory) {
                    if (@([System.IO.Directory]::GetFileSystemEntries($targetPath)).Count -gt 0) {
                        Write-GnuError -Context $Context -Message "cannot move '$($pair.Source)' to '$($pair.Target)': Directory not empty"
                        continue
                    }
                    [System.IO.Directory]::Delete($targetPath, $false)
                }
                elseif ($target -is [System.IO.DirectoryInfo]) { [System.IO.Directory]::Delete($targetPath, $false) }
                else {
                    $target.Attributes = [System.IO.FileAttributes]::Normal
                    [System.IO.File]::Delete($targetPath)
                }
            }
            catch {
                Write-GnuError -Context $Context -Message "cannot remove '$($pair.Target)': $(Get-GnuErrorReason -Exception $_.Exception)"
                continue
            }
        }

        try {
            if ($sourceIsDirectory -and -not (Test-GnuSameVolume -Left $sourcePath -Right $targetPath)) {
                # Directory.Move cannot cross drives: copy, then delete the original.
                Copy-GnuDirectoryTree -Source $sourcePath -Destination $targetPath
                Remove-GnuTree -Path $sourcePath
            }
            elseif ($source -is [System.IO.DirectoryInfo]) {
                [System.IO.Directory]::Move($sourcePath, $targetPath)
            }
            else {
                [System.IO.File]::Move($sourcePath, $targetPath)
            }
            if ($verbose) { "renamed '$($pair.Source)' -> '$($pair.Target)'" }
        }
        catch {
            Write-GnuError -Context $Context -Message "cannot move '$($pair.Source)' to '$($pair.Target)': $(Get-GnuErrorReason -Exception $_.Exception)"
        }
    }
}
