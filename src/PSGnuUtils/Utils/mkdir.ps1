Register-GnuUtil @{
    Name        = 'mkdir'
    Category    = 'File and directory operations'
    Synopsis    = 'Make directories.'
    Usage       = @('mkdir [OPTION]... DIRECTORY...')
    Description = @('Create the DIRECTORY(ies), if they do not already exist.')
    Options     = @(
        @{ Short = 'm'; Long = 'mode'; Arg = 'MODE'; Help = 'set file mode (as in chmod), not a=rwx - umask' }
        @{ Short = 'p'; Long = 'parents'; Help = 'no error if existing, make parent directories as needed' }
        @{ Short = 'v'; Long = 'verbose'; Help = 'print a message for each created directory' }
        @{ Short = 'Z'; Long = 'context'; Arg = 'CTX'; OptionalArg = $true; Help = 'accepted for compatibility; SELinux contexts are not supported' }
    )
    Notes       = @(
        'PowerShell note: only octal modes (e.g. 755) are supported. Modes are applied on',
        'Linux/macOS with PowerShell 7.3+ and ignored on Windows.'
    )
}

function Invoke-GnuMkdir {
    <#
    .SYNOPSIS
    GNU mkdir: make directories.

    .DESCRIPTION
    Creates each DIRECTORY. With -p, missing parents are created and existing directories are
    not an error. -v reports every directory created.
    Enable the GNU name with: Enable-GnuAlias mkdir (replaces the built-in mkdir function).

    .EXAMPLE
    Invoke-GnuMkdir -pv build/output/logs

    mkdir: created directory 'build'
    mkdir: created directory 'build/output'
    mkdir: created directory 'build/output/logs'
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'mkdir' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            $operands = @($ctx.Operands)
            $mode = $null
            if (Test-GnuOption -Context $ctx -Key 'mode') {
                $modeText = [string](Get-GnuOptionValue -Context $ctx -Key 'mode')
                if ($modeText -notmatch '^[0-7]{1,4}$') {
                    Write-GnuError -Context $ctx -Message "invalid mode '$modeText' (only octal modes are supported)"
                    $ctx.Done = $true
                }
                else {
                    $mode = [System.Convert]::ToInt32($modeText, 8)
                }
            }

            if ($ctx.Done) {
                # invalid mode already reported
            }
            elseif ($operands.Count -eq 0) {
                Write-GnuUsageError -Context $ctx -Message 'missing operand'
            }
            else {
                $parents = Test-GnuOption -Context $ctx -Key 'parents'
                $verbose = Test-GnuOption -Context $ctx -Key 'verbose'
                foreach ($directory in $operands) {
                    $targets = @($directory)
                    if ($parents) { $targets = @(Get-GnuPathPrefix -Path $directory) }

                    for ($i = 0; $i -lt $targets.Count; $i++) {
                        $display = $targets[$i]
                        $isFinal = $i -eq $targets.Count - 1
                        $path = Resolve-GnuPath -Path $display
                        if ([System.IO.Directory]::Exists($path)) {
                            if ($parents) { continue }
                            Write-GnuError -Context $ctx -Message "cannot create directory '$display': File exists"
                            break
                        }
                        if ([System.IO.File]::Exists($path)) {
                            $reason = 'Not a directory'
                            if ($isFinal) { $reason = 'File exists' }
                            Write-GnuError -Context $ctx -Message "cannot create directory '$directory': $reason"
                            break
                        }
                        $parent = Get-GnuParentPath -Path $path
                        if (-not $parents -and $parent -and -not [System.IO.Directory]::Exists($parent)) {
                            Write-GnuError -Context $ctx -Message "cannot create directory '$display': No such file or directory"
                            break
                        }
                        try {
                            $null = [System.IO.Directory]::CreateDirectory($path)
                            if ($isFinal -and $null -ne $mode) { $null = Set-GnuUnixMode -Path $path -Mode $mode }
                            if ($verbose) { "mkdir: created directory '$display'" }
                        }
                        catch {
                            Write-GnuError -Context $ctx -Message "cannot create directory '$display': $(Get-GnuErrorReason -Exception $_.Exception)"
                            break
                        }
                    }
                }
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}
