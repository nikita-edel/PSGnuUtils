Register-GnuUtil @{
    Name         = 'ln'
    Category     = 'File and directory operations'
    Synopsis     = 'Make links between files.'
    Usage        = @(
        'ln [OPTION]... [-T] TARGET LINK_NAME',
        'ln [OPTION]... TARGET',
        'ln [OPTION]... TARGET... DIRECTORY',
        'ln [OPTION]... -t DIRECTORY TARGET...'
    )
    Description  = @(
        'In the 1st form, create a link to TARGET with the name LINK_NAME.',
        'In the 2nd form, create a link to TARGET in the current directory.',
        'In the 3rd and 4th forms, create links to each TARGET in DIRECTORY.',
        'Create hard links by default, symbolic links with --symbolic.',
        'By default, each destination (name of new link) should not already exist.',
        'When creating hard links, each TARGET must exist.  Symbolic links',
        'can hold arbitrary text; if later resolved, a relative link is',
        'interpreted in relation to its parent directory.'
    )
    FileOperands = $true
    Options      = @(
        @{ Short = 'f'; Long = 'force'; Key = 'replace'; Value = 'force'; Help = 'remove existing destination files' }
        @{ Short = 'i'; Long = 'interactive'; Key = 'replace'; Value = 'ask'; Help = 'prompt whether to remove destinations' }
        @{ Short = 'L'; Long = 'logical'; Key = 'follow'; Value = 'logical'; Help = 'dereference TARGETs that are symbolic links' }
        @{ Short = 'n'; Long = 'no-dereference'; Help = 'treat LINK_NAME as a normal file if it is a symbolic link to a directory' }
        @{ Short = 'P'; Long = 'physical'; Key = 'follow'; Value = 'physical'; Help = 'make hard links directly to symbolic links' }
        @{ Short = 'r'; Long = 'relative'; Help = 'with -s, create links relative to link location' }
        @{ Short = 's'; Long = 'symbolic'; Help = 'make symbolic links instead of hard links' }
        @{ Short = 't'; Long = 'target-directory'; Arg = 'DIRECTORY'; Help = 'specify the DIRECTORY in which to create the links' }
        @{ Short = 'T'; Long = 'no-target-directory'; Help = 'treat LINK_NAME as a normal file always' }
        @{ Short = 'v'; Long = 'verbose'; Help = 'print name of each linked file' }
    )
    Notes        = @(
        'PowerShell notes: symbolic links on Windows need admin rights or developer mode. -L and -P are',
        'accepted; hard links always point to the file the TARGET name resolves to. Backups (-b, -S) are not supported.'
    )
}

function Invoke-GnuLn {
    <#
    .SYNOPSIS
    GNU ln: make hard or symbolic links.

    .DESCRIPTION
    Creates a hard link (default) or symbolic link (-s) for every TARGET: named LINK_NAME, placed
    in DIRECTORY, or in the current directory. Existing destinations are an error unless -f
    replaces them or -i asks. -r stores a symbolic link target relative to the link.
    Enable the GNU name with: Enable-GnuUtil ln

    .EXAMPLE
    Invoke-GnuLn -s ../shared/config.json config.json

    .EXAMPLE
    Invoke-GnuLn data.bin backup.bin
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'ln' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) { New-GnuLnLink -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function New-GnuLnLink {
    <#
    .SYNOPSIS
    Implementation of ln.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $symbolic = Test-GnuOption -Context $Context -Key 'symbolic'
    $relative = Test-GnuOption -Context $Context -Key 'relative'
    if ($relative -and -not $symbolic) {
        Write-GnuUsageError -Context $Context -Message 'cannot do --relative without --symbolic'
        return
    }
    $replace = [string](Get-GnuOptionValue -Context $Context -Key 'replace' -Default 'no')
    $verbose = Test-GnuOption -Context $Context -Key 'verbose'
    $kind = 'hard link'
    if ($symbolic) { $kind = 'symbolic link' }

    $pairs = @(Get-GnuTransferPlan -Context $Context -AllowSingleOperand -NoDereferenceTarget:(Test-GnuOption -Context $Context -Key 'no-dereference'))
    foreach ($pair in $pairs) {
        $targetPath = Resolve-GnuPath -Path $pair.Source
        $linkPath = Resolve-GnuPath -Path $pair.Target
        $describe = "'$($pair.Target)'"
        if (-not $symbolic) { $describe = "'$($pair.Target)' => '$($pair.Source)'" }

        if (-not $symbolic) {
            if ([System.IO.Directory]::Exists($targetPath)) {
                Write-GnuError -Context $Context -Message "$($pair.Source): hard link not allowed for directory"
                continue
            }
            if (-not [System.IO.File]::Exists($targetPath)) {
                Write-GnuError -Context $Context -Message "failed to access '$($pair.Source)': No such file or directory"
                continue
            }
        }

        $existing = Get-Item -LiteralPath $linkPath -Force -ErrorAction SilentlyContinue
        if ($null -ne $existing) {
            if (-not $symbolic -and (Test-GnuSamePath -Left $targetPath -Right $linkPath)) {
                Write-GnuError -Context $Context -Message "'$($pair.Source)' and '$($pair.Target)' are the same file"
                continue
            }
            if ($replace -eq 'no') {
                Write-GnuError -Context $Context -Message "failed to create $kind $($describe): File exists"
                continue
            }
            if ($replace -eq 'ask' -and -not (Read-GnuConfirmation -Context $Context -Question "replace '$($pair.Target)'?")) { continue }
            $isLink = $null -ne (Get-GnuLinkTarget -Path $linkPath)
            if ($existing -is [System.IO.DirectoryInfo] -and -not $isLink) {
                Write-GnuError -Context $Context -Message "$($pair.Target): cannot overwrite directory"
                continue
            }
            if ($existing -is [System.IO.DirectoryInfo]) { [System.IO.Directory]::Delete($linkPath, $false) }
            else { [System.IO.File]::Delete($linkPath) }
        }

        try {
            if ($symbolic) {
                $stored = $pair.Source
                $linkDirectory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($linkPath))
                if ($relative) { $stored = Get-GnuRelativePath -From $linkDirectory -To $targetPath }
                # A relative link target is resolved from the link's directory, not from the current directory.
                $resolvedTarget = $stored
                if (-not [System.IO.Path]::IsPathRooted($stored)) { $resolvedTarget = [System.IO.Path]::Combine($linkDirectory, $stored) }
                New-GnuSymbolicLink -Path $linkPath -Target $stored -Directory:([System.IO.Directory]::Exists($resolvedTarget))
                if ($verbose) { "'$($pair.Target)' -> '$stored'" }
            }
            else {
                $null = New-Item -ItemType HardLink -Path ([System.Management.Automation.WildcardPattern]::Escape($linkPath)) -Value $targetPath -ErrorAction Stop
                if ($verbose) { "'$($pair.Target)' => '$($pair.Source)'" }
            }
        }
        catch {
            Write-GnuError -Context $Context -Message "failed to create $kind $($describe): $(Get-GnuErrorReason -Exception $_.Exception)"
        }
    }
}
