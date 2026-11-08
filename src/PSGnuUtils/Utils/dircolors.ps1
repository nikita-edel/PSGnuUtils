Register-GnuUtil @{
    Name         = 'dircolors'
    Category     = 'File and directory operations'
    Synopsis     = 'Color setup for ls.'
    Usage        = @('dircolors [OPTION]... [FILE]')
    Description  = @(
        'Output commands to set the LS_COLORS environment variable.',
        '',
        'Determine format of output:'
    )
    FileOperands = $true
    Options      = @(
        @{ Short = 'b'; Long = 'sh'; Key = 'shell'; Value = 'bourne'; Help = 'output Bourne shell code to set LS_COLORS' }
        @{ Long = 'bourne-shell'; Key = 'shell'; Value = 'bourne'; Help = 'output Bourne shell code to set LS_COLORS' }
        @{ Short = 'c'; Long = 'csh'; Key = 'shell'; Value = 'csh'; Help = 'output C shell code to set LS_COLORS' }
        @{ Long = 'c-shell'; Key = 'shell'; Value = 'csh'; Help = 'output C shell code to set LS_COLORS' }
        @{ Short = 'p'; Long = 'print-database'; Help = 'output defaults' }
    )
    Notes        = @(
        'If FILE is specified, read it to determine which colors to use for which',
        'file types and extensions.  Otherwise, a precompiled database is used.',
        'For details on the format of these files, run ''dircolors --print-database''.',
        '',
        'PowerShell note: without -b / -c and without a SHELL variable (the usual case on',
        'Windows), PowerShell code is printed: $env:LS_COLORS = ''...''. Use it with',
        'dircolors | Invoke-Expression. Without a TERM variable, Windows assumes',
        'xterm-256color (Windows Terminal and conhost understand the colors).'
    )
}

$script:GnuDircolorsKeywords = @{
    NORMAL = 'no'; NORM = 'no'; FILE = 'fi'; RESET = 'rs'; DIR = 'di'; LNK = 'ln'; LINK = 'ln'; SYMLINK = 'ln'
    ORPHAN = 'or'; MISSING = 'mi'; FIFO = 'pi'; PIPE = 'pi'; SOCK = 'so'; BLK = 'bd'; BLOCK = 'bd'; CHR = 'cd'
    CHAR = 'cd'; DOOR = 'do'; EXEC = 'ex'; LEFT = 'lc'; LEFTCODE = 'lc'; RIGHT = 'rc'; RIGHTCODE = 'rc'; END = 'ec'
    ENDCODE = 'ec'; SUID = 'su'; SETUID = 'su'; SGID = 'sg'; SETGID = 'sg'; STICKY = 'st'; OTHER_WRITABLE = 'ow'
    OWR = 'ow'; STICKY_OTHER_WRITABLE = 'tw'; OWT = 'tw'; CAPABILITY = 'ca'; MULTIHARDLINK = 'mh'; CLRTOEOL = 'cl'
}

function Invoke-GnuDircolors {
    <#
    .SYNOPSIS
    GNU dircolors: output commands that set LS_COLORS (used by ls --color).

    .DESCRIPTION
    Converts the built-in database (or FILE) into an LS_COLORS value for the current TERM and
    prints it as Bourne shell (-b), C shell (-c) or, without a SHELL variable, PowerShell code.
    -p prints the database.
    Enable the GNU name with: Enable-GnuUtil dircolors

    .EXAMPLE
    Invoke-GnuDircolors | Invoke-Expression

    Sets $env:LS_COLORS for this session.
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'dircolors' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuDircolorsOutput -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function ConvertTo-GnuLsColors {
    <#
    .SYNOPSIS
    The LS_COLORS value of a dircolors database for a terminal type. Returns @{ Value } or @{ Error }.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Database,
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][string]$Term,
        [AllowEmptyString()][string]$ColorTerm = ''
    )

    $builder = New-Object System.Text.StringBuilder
    $state = 'global'
    $number = 0
    $errors = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in ($Database -split "`r?`n")) {
        $number++
        $match = [regex]::Match($line, '^\s*([^\s#]+)(?:\s+([^\s#]+))?')
        if (-not $match.Success) { continue }
        $keyword = $match.Groups[1].Value
        if (-not $match.Groups[2].Success) { $errors.Add("$($FileName):$($number): invalid line;  missing second token"); continue }
        $argument = $match.Groups[2].Value
        $upper = $keyword.ToUpperInvariant()
        if ($upper -eq 'TERM' -or $upper -eq 'COLORTERM') {
            $subject = $Term
            if ($upper -eq 'COLORTERM') { $subject = $ColorTerm }
            if ((New-Object System.Management.Automation.WildcardPattern -ArgumentList $argument, ([System.Management.Automation.WildcardOptions]::None)).IsMatch($subject) -and
                -not ($upper -eq 'COLORTERM' -and [string]::IsNullOrEmpty($subject) -and $argument -ne '*')) {
                $state = 'sure'
            }
            elseif ($state -ne 'sure') { $state = 'no' }
            continue
        }
        if ($state -eq 'sure') { $state = 'yes' }
        if ($state -eq 'no') { continue }
        if ($keyword.StartsWith('.', [System.StringComparison]::Ordinal)) { [void]$builder.Append("*$keyword=${argument}:") }
        elseif ($keyword.StartsWith('*', [System.StringComparison]::Ordinal)) { [void]$builder.Append("$keyword=${argument}:") }
        elseif (@('OPTIONS', 'COLOR', 'EIGHTBIT') -contains $upper) { continue }
        elseif ($script:GnuDircolorsKeywords.ContainsKey($upper)) { [void]$builder.Append("$($script:GnuDircolorsKeywords[$upper])=${argument}:") }
        else { $errors.Add("$($FileName):$($number): unrecognized keyword $keyword") }
    }
    @{ Value = $builder.ToString(); Errors = $errors.ToArray() }
}

function Invoke-GnuDircolorsOutput {
    <#
    .SYNOPSIS
    Implementation of dircolors.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $operands = @($Context.Operands)
    $shell = [string](Get-GnuOptionValue -Context $Context -Key 'shell' -Default '')
    if (Test-GnuOption -Context $Context -Key 'print-database') {
        if (-not [string]::IsNullOrEmpty($shell)) {
            Write-GnuUsageError -Context $Context -Message "the options to output dircolors' internal database and`nto select a shell syntax are mutually exclusive"
            return
        }
        if ($operands.Count -gt 0) { Write-GnuUsageError -Context $Context -Message "extra operand '$($operands[0])'`nfile operands cannot be combined with --print-database (-p)"; return }
        ConvertTo-GnuOutputLine -Text ($script:GnuDircolorsDatabase + "`n")
        return
    }
    if ($operands.Count -gt 1) { Write-GnuUsageError -Context $Context -Message "extra operand '$($operands[1])'"; return }

    if ([string]::IsNullOrEmpty($shell)) {
        $shell = 'powershell'
        if (-not [string]::IsNullOrEmpty($env:SHELL)) {
            $shell = 'bourne'
            if ((Get-GnuBaseName -Path $env:SHELL) -match 'csh(\.exe)?$') { $shell = 'csh' }
        }
    }

    $database = $script:GnuDircolorsDatabase
    $fileName = '<internal>'
    if ($operands.Count -eq 1) {
        $database = Get-GnuInputText -Context $Context -Operand $operands[0]
        if ($null -eq $database) { return }
        $fileName = $operands[0]
    }
    $term = $env:TERM
    if ([string]::IsNullOrEmpty($term)) {
        $term = 'none'
        if (Test-GnuWindows) { $term = 'xterm-256color' }
    }
    $result = ConvertTo-GnuLsColors -Database $database -FileName $fileName -Term $term -ColorTerm ([string]$env:COLORTERM)
    foreach ($message in $result.Errors) { Write-GnuError -Context $Context -Message $message }
    $value = $result.Value.Replace("'", "'\''")
    switch ($shell) {
        'bourne' { "LS_COLORS='$value';"; 'export LS_COLORS' }
        'csh' { "setenv LS_COLORS '$value'" }
        default { "`$env:LS_COLORS = '$($result.Value.Replace("'", "''"))'" }
    }
}
