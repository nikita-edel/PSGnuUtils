Register-GnuUtil @{
    Name        = 'which'
    Category    = 'Searching and comparing'
    Synopsis    = 'Show the full path of (shell) commands.'
    Usage       = @('which [options] [--] COMMAND [...]')
    Description = @('Write the full path of COMMAND(s) to standard output.')
    Options     = @(
        @{ Short = 'a'; Long = 'all'; Help = 'Print all matches in PATH, not just the first' }
        @{ Long = 'skip-dot'; Help = 'Skip directories in PATH that start with a dot.' }
        @{ Long = 'skip-tilde'; Help = 'Skip directories in PATH that start with a tilde (or your home directory).' }
        @{ Long = 'show-dot'; Help = "Don't expand a dot to current directory in output." }
        @{ Long = 'show-tilde'; Help = 'Output a tilde for HOME directory for non-root.' }
    )
    Notes       = @(
        'PowerShell notes: only programs and scripts in PATH are found (not aliases or functions; use',
        'Get-Command for those). On Windows a COMMAND without extension is looked up with every PATHEXT extension.'
    )
}

function Invoke-GnuWhich {
    <#
    .SYNOPSIS
    GNU which: show the full path of commands found in PATH.

    .DESCRIPTION
    Searches every directory of PATH for an executable named COMMAND (on Windows also COMMAND plus
    each PATHEXT extension) and prints the first match, or every match with -a. Names that contain a
    directory separator are checked directly. Exit code 1 if any COMMAND was not found.
    Enable the GNU name with: Enable-GnuAlias which

    .EXAMPLE
    Invoke-GnuWhich git

    C:\Program Files\Git\cmd\git.exe
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'which' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) { Invoke-GnuWhichSearch -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function Test-GnuExecutable {
    <#
    .SYNOPSIS
    $true if Path is an existing file that can be run: on Windows by extension, on Unix by an execute bit.
    #>
    param([Parameter(Mandatory)][string]$Path, [AllowEmptyCollection()][string[]]$Extensions = @())

    if (-not [System.IO.File]::Exists($Path)) { return $false }
    if (Test-GnuWindows) {
        $extension = [System.IO.Path]::GetExtension($Path)
        foreach ($candidate in $Extensions) { if ([string]::Equals($extension, $candidate, [System.StringComparison]::OrdinalIgnoreCase)) { return $true } }
        return $false
    }
    $mode = Get-GnuUnixFileMode -Path $Path
    if ($null -eq $mode) { return $true }   # runtime cannot read modes: trust the file system
    ($mode -band 73) -ne 0                  # 0111: any execute bit
}

function Invoke-GnuWhichSearch {
    <#
    .SYNOPSIS
    Implementation of which.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $commands = @($Context.Operands)
    if ($commands.Count -eq 0) {
        Write-GnuUsageError -Context $Context -Message 'missing operand'
        return
    }

    $all = Test-GnuOption -Context $Context -Key 'all'
    $pathText = [string]$env:PATH
    $directories = @($pathText.Split([System.IO.Path]::PathSeparator) | Where-Object { -not [string]::IsNullOrEmpty($_) })
    $homeDirectory = [string]$env:HOME
    if (-not $homeDirectory) { $homeDirectory = [string]$env:USERPROFILE }
    if (Test-GnuOption -Context $Context -Key 'skip-dot') { $directories = @($directories | Where-Object { -not $_.StartsWith('.', [System.StringComparison]::Ordinal) }) }
    if (Test-GnuOption -Context $Context -Key 'skip-tilde') {
        $directories = @($directories | Where-Object { -not $_.StartsWith('~', [System.StringComparison]::Ordinal) -and -not ($homeDirectory -and $_.StartsWith($homeDirectory, [System.StringComparison]::OrdinalIgnoreCase)) })
    }

    $extensions = @()
    if (Test-GnuWindows) {
        $pathExt = [string]$env:PATHEXT
        if (-not $pathExt) { $pathExt = '.COM;.EXE;.BAT;.CMD' }
        $extensions = @($pathExt.Split(';') | Where-Object { -not [string]::IsNullOrEmpty($_) })
    }

    foreach ($command in $commands) {
        $names = @($command)
        if ((Test-GnuWindows) -and [string]::IsNullOrEmpty([System.IO.Path]::GetExtension($command))) { $names = @(foreach ($extension in $extensions) { $command + $extension }) }

        $found = New-Object 'System.Collections.Generic.List[string]'
        if ($command.IndexOfAny((Get-GnuPathSeparator)) -ge 0) {
            foreach ($name in $names) {
                $path = Resolve-GnuPath -Path $name
                if (Test-GnuExecutable -Path $path -Extensions $extensions) { $found.Add($name); break }
            }
        }
        else {
            foreach ($directory in $directories) {
                $expanded = $directory
                if ($directory -eq '.' -or $directory.StartsWith('.' + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::Ordinal)) {
                    $expanded = Resolve-GnuPath -Path $directory
                }
                foreach ($name in $names) {
                    $candidate = [System.IO.Path]::Combine($expanded, $name)
                    if (-not (Test-GnuExecutable -Path $candidate -Extensions $extensions)) { continue }
                    $shown = $candidate
                    if ((Test-GnuOption -Context $Context -Key 'show-dot') -and $directory -ne $expanded) { $shown = [System.IO.Path]::Combine($directory, $name) }
                    if ((Test-GnuOption -Context $Context -Key 'show-tilde') -and $homeDirectory -and $shown.StartsWith($homeDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $shown = '~' + $shown.Substring($homeDirectory.Length)
                    }
                    if (-not $found.Contains($shown)) { $found.Add($shown) }
                    if (-not $all) { break }
                }
                if ($found.Count -gt 0 -and -not $all) { break }
            }
        }

        if ($found.Count -eq 0) {
            Write-GnuError -Context $Context -Message "no $command in ($pathText)"
            continue
        }
        foreach ($path in $found) { $path }
    }
}
