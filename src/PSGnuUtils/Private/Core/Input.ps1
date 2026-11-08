# Input handling: pipeline input as stdin, file operands, wildcard expansion.
#
# Input model (see docs/ARCHITECTURE.md):
#   * PowerShell pipeline input is the util's standard input. Strings are split into lines,
#     numbers/booleans are converted with invariant culture, FileInfo/DirectoryInfo become their
#     full path, and any other object is rendered the way the console would show it
#     (Out-String), so 'Get-Process | grep pwsh' works on the visible text.
#   * Without pipeline input, '-' (or no operand) reads the console's standard input.
#   * Files are read as UTF-8 (a BOM selects UTF-16/UTF-32). Byte-oriented utils read raw bytes;
#     pipeline text becomes UTF-8 bytes with a LF after every line.

$script:GnuUtf8 = New-Object System.Text.UTF8Encoding($false)

function ConvertFrom-GnuPipelineItem {
    <#
    .SYNOPSIS
    Converts one pipeline item into the input lines that are ready now.
    .DESCRIPTION
    Objects that need formatting are buffered in Context.Pending and rendered together (one
    table header) when the next string arrives or Complete-GnuPipelineInput is called.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [AllowNull()][object]$InputObject
    )

    if ($null -eq $InputObject) { return }

    if ($InputObject -is [string] -or $InputObject -is [System.ValueType] -or $InputObject -is [System.IO.FileSystemInfo]) {
        Complete-GnuPipelineInput -Context $Context
        if ($InputObject -is [System.IO.FileSystemInfo]) {
            $InputObject.FullName
            return
        }
        $text = [string]$InputObject
        if ([string]::IsNullOrEmpty($text)) {
            ''
            return
        }
        ConvertTo-GnuOutputLine -Text $text
        return
    }

    $Context.Pending.Add($InputObject)
}

function Complete-GnuPipelineInput {
    <#
    .SYNOPSIS
    Renders buffered non-string pipeline objects (Out-String) and emits their lines.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    if ($Context.Pending.Count -eq 0) { return }
    $lines = @($Context.Pending | Out-String -Stream)
    $Context.Pending.Clear()

    $first = 0
    $last = $lines.Count - 1
    while ($first -le $last -and [string]::IsNullOrEmpty($lines[$first].Trim())) { $first++ }
    while ($last -ge $first -and [string]::IsNullOrEmpty($lines[$last].Trim())) { $last-- }
    for ($i = $first; $i -le $last; $i++) { $lines[$i].TrimEnd() }
}

function Add-GnuPipelineInput {
    <#
    .SYNOPSIS
    Buffers one pipeline item as stdin lines (for utils that do not stream their input).
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [AllowNull()][object]$InputObject
    )
    foreach ($line in @(ConvertFrom-GnuPipelineItem -Context $Context -InputObject $InputObject)) {
        $Context.Stdin.Add($line)
    }
}

function Test-GnuStdinOnly {
    <#
    .SYNOPSIS
    Returns $true when the util reads nothing but pipeline input (no operands, or only '-').
    Such utils can process lines as they arrive instead of buffering them.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)
    $operands = @($Context.Operands)
    $Context.ExpectingInput -and ($operands.Count -eq 0 -or ($operands.Count -eq 1 -and $operands[0] -eq '-'))
}

function Read-GnuStdinLine {
    <#
    .SYNOPSIS
    Emits all standard input lines: buffered pipeline input, or the console's stdin.
    Standard input can be consumed once; later reads return nothing (like GNU at EOF).
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    if ($Context.StdinConsumed) { return }
    $Context.StdinConsumed = $true

    if ($Context.ExpectingInput) {
        foreach ($line in @(Complete-GnuPipelineInput -Context $Context)) { $Context.Stdin.Add($line) }
        foreach ($line in $Context.Stdin) { $line }
        return
    }

    $reader = [System.Console]::In
    while ($null -ne ($line = $reader.ReadLine())) { $line }
}

function Get-GnuDisplayName {
    <#
    .SYNOPSIS
    Name used for an operand in headers and messages ('-' is 'standard input').
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Operand)
    if ($Operand -eq '-') { return 'standard input' }
    $Operand
}

function Get-GnuReadablePath {
    <#
    .SYNOPSIS
    Resolves a file operand to a provider path, or writes a GNU style error and returns nothing.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Operand,
        [switch]$Quiet
    )

    $path = ''
    if (-not [string]::IsNullOrEmpty($Operand)) { $path = Resolve-GnuPath -Path $Operand }
    if (-not [string]::IsNullOrEmpty($path) -and [System.IO.Directory]::Exists($path)) {
        if (-not $Quiet) { Write-GnuError -Context $Context -Message ($Context.Spec.ReadErrorFormat -f $Operand, 'Is a directory') }
        return
    }
    if ([string]::IsNullOrEmpty($path) -or -not [System.IO.File]::Exists($path)) {
        if (-not $Quiet) { Write-GnuError -Context $Context -Message ($Context.Spec.OpenErrorFormat -f $Operand, 'No such file or directory') }
        return
    }
    $path
}

function Get-GnuInputLine {
    <#
    .SYNOPSIS
    Emits the lines of one input operand ('-' = standard input).
    .PARAMETER Limit
    Stop after this many lines (0 = no limit). Avoids reading whole files for head and friends.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Operand,
        [long]$Limit = 0
    )

    if ($Operand -eq '-') {
        $emitted = 0
        foreach ($line in @(Read-GnuStdinLine -Context $Context)) {
            if ($Limit -gt 0 -and $emitted -ge $Limit) { break }
            $emitted++
            $line
        }
        return
    }

    $path = Get-GnuReadablePath -Context $Context -Operand $Operand
    if ($null -eq $path) { return }

    $reader = $null
    try {
        $reader = New-Object System.IO.StreamReader -ArgumentList $path, $script:GnuUtf8, $true
        $emitted = 0
        while (($Limit -eq 0 -or $emitted -lt $Limit) -and $null -ne ($line = $reader.ReadLine())) {
            $emitted++
            $line
        }
    }
    catch {
        Write-GnuError -Context $Context -Message ($Context.Spec.OpenErrorFormat -f $Operand, (Get-GnuErrorReason -Exception $_.Exception))
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
    }
}

function Get-GnuInputText {
    <#
    .SYNOPSIS
    Returns the whole text of one input operand, or nothing if it cannot be read.
    Standard input is returned as its lines joined with LF plus a final LF.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Operand
    )

    if ($Operand -eq '-') {
        $lines = @(Read-GnuStdinLine -Context $Context)
        if ($lines.Count -eq 0) { return '' }
        return (($lines -join "`n") + "`n")
    }

    $path = Get-GnuReadablePath -Context $Context -Operand $Operand
    if ($null -eq $path) { return }
    try {
        [System.IO.File]::ReadAllText($path, $script:GnuUtf8)
    }
    catch {
        Write-GnuError -Context $Context -Message ($Context.Spec.OpenErrorFormat -f $Operand, (Get-GnuErrorReason -Exception $_.Exception))
    }
}

function Get-GnuInputBytes {
    <#
    .SYNOPSIS
    Returns the content of one input operand as a single byte[] (not unrolled), or nothing on error.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Operand
    )

    if ($Operand -eq '-') {
        $text = [string](Get-GnuInputText -Context $Context -Operand '-')
        return , $script:GnuUtf8.GetBytes($text)
    }

    $path = Get-GnuReadablePath -Context $Context -Operand $Operand
    if ($null -eq $path) { return }
    try {
        return , [System.IO.File]::ReadAllBytes($path)
    }
    catch {
        Write-GnuError -Context $Context -Message ($Context.Spec.OpenErrorFormat -f $Operand, (Get-GnuErrorReason -Exception $_.Exception))
    }
}

function Open-GnuInputStream {
    <#
    .SYNOPSIS
    Opens one input operand as a readable stream (caller disposes it), or returns nothing on error.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Operand,
        [switch]$Quiet,
        [switch]$AllowWriters
    )

    if ($Operand -eq '-') {
        $bytes = Get-GnuInputBytes -Context $Context -Operand '-'
        return [System.IO.MemoryStream]::new([byte[]]$bytes)
    }

    $path = Get-GnuReadablePath -Context $Context -Operand $Operand -Quiet:$Quiet
    if ($null -eq $path) { return }
    try {
        if ($AllowWriters) { New-Object System.IO.FileStream -ArgumentList $path, 'Open', 'Read', 'ReadWrite' }
        else { [System.IO.File]::OpenRead($path) }
    }
    catch {
        if (-not $Quiet) {
            Write-GnuError -Context $Context -Message ($Context.Spec.OpenErrorFormat -f $Operand, (Get-GnuErrorReason -Exception $_.Exception))
        }
    }
}

function Expand-GnuWildcard {
    <#
    .SYNOPSIS
    Expands wildcard operands like a Unix shell would (PowerShell does not glob for functions).
    .DESCRIPTION
    An operand is kept unchanged if it has no wildcard characters, if it exists literally (so
    'file[1].txt' works), or if nothing matches (like bash without nullglob). Hidden entries
    (leading '.') only match patterns that start with '.'. Matches are sorted ordinally and keep
    the directory part exactly as typed.
    #>
    param([AllowEmptyCollection()][string[]]$Operands = @())

    foreach ($operand in $Operands) {
        if ($operand -eq '-' -or [string]::IsNullOrEmpty($operand) -or -not [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($operand)) {
            $operand
            continue
        }
        $full = Resolve-GnuPath -Path $operand
        if ([System.IO.File]::Exists($full) -or [System.IO.Directory]::Exists($full)) {
            $operand
            continue
        }
        $found = @(Get-GnuWildcardMatch -Pattern $operand)
        if ($found.Count -eq 0) { $operand } else { $found }
    }
}

function Get-GnuWildcardMatch {
    <#
    .SYNOPSIS
    Returns the paths matching a wildcard pattern (helper of Expand-GnuWildcard).
    #>
    param([Parameter(Mandatory)][string]$Pattern)

    $separatorIndex = $Pattern.LastIndexOfAny((Get-GnuPathSeparator))
    $parent = ''
    $leaf = $Pattern
    if ($separatorIndex -ge 0) {
        $parent = $Pattern.Substring(0, $separatorIndex + 1)
        $leaf = $Pattern.Substring($separatorIndex + 1)
    }

    if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($parent)) {
        # Wildcards in directory components: let PowerShell resolve the full pattern.
        $resolved = @(Resolve-Path -Path $Pattern -ErrorAction SilentlyContinue | ForEach-Object { $_.ProviderPath })
        [System.Array]::Sort($resolved, [System.StringComparer]::Ordinal)
        $resolved
        return
    }

    $directory = Resolve-GnuPath -Path '.'
    if (-not [string]::IsNullOrEmpty($parent)) { $directory = Resolve-GnuPath -Path $parent }
    if (-not [System.IO.Directory]::Exists($directory)) { return }

    $options = [System.Management.Automation.WildcardOptions]::None
    if (Test-GnuWindows) { $options = [System.Management.Automation.WildcardOptions]::IgnoreCase }
    $wildcard = New-Object System.Management.Automation.WildcardPattern -ArgumentList $leaf, $options

    $names = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entry in [System.IO.Directory]::GetFileSystemEntries($directory)) {
        $name = [System.IO.Path]::GetFileName($entry)
        if ($name.StartsWith('.', [System.StringComparison]::Ordinal) -and -not $leaf.StartsWith('.', [System.StringComparison]::Ordinal)) { continue }
        if ($wildcard.IsMatch($name)) { $names.Add($name) }
    }
    $names.Sort([System.StringComparer]::Ordinal)
    foreach ($name in $names) { $parent + $name }
}
