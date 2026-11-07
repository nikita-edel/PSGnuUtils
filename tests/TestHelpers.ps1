# Shared helpers for all Pester tests. Dot-source from BeforeAll:
#
#   BeforeAll { . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1') }
#
# The module under test is src/PSGnuUtils/PSGnuUtils.psd1, or the manifest in
# $env:PSGNUUTILS_TEST_MANIFEST (./build.ps1 -Task TestBuild uses the built module).
# Test files must stay ASCII-only (Windows PowerShell 5.1 reads BOM-less files as ANSI);
# build non-ASCII strings with [char] codes.

$script:TestRepoRoot = Split-Path -Parent $PSScriptRoot
$script:TestManifest = Join-Path -Path $script:TestRepoRoot -ChildPath 'src/PSGnuUtils/PSGnuUtils.psd1'
if ($env:PSGNUUTILS_TEST_MANIFEST) { $script:TestManifest = $env:PSGNUUTILS_TEST_MANIFEST }

$loaded = Get-Module -Name PSGnuUtils
if ($null -eq $loaded -or -not $loaded.Path.StartsWith((Split-Path -Parent $script:TestManifest))) {
    Import-Module -Name $script:TestManifest -Force -ErrorAction Stop
}

function Invoke-TestGnu {
    <#
    .SYNOPSIS
    Runs a util function (Invoke-Gnu<Name>) and captures everything it produces.
    .OUTPUTS
    Object with Output (string[]), Text (output joined with LF), Errors (string[]), ErrorText,
    Warnings (string[]), WarningText and ExitCode ($LASTEXITCODE after the call).
    .EXAMPLE
    $r = Invoke-TestGnu head '-n', '2' -InputObject 'a', 'b', 'c'
    #>
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [Parameter(Position = 1)][AllowEmptyCollection()][object[]]$Arguments = @(),
        [object[]]$InputObject,
        [string]$WorkingDirectory
    )

    $command = 'Invoke-Gnu' + $Name.Substring(0, 1).ToUpperInvariant() + $Name.Substring(1)
    $global:LASTEXITCODE = -1
    if ($WorkingDirectory) { Push-Location -LiteralPath $WorkingDirectory }
    try {
        if ($PSBoundParameters.ContainsKey('InputObject')) {
            $records = $InputObject | & $command @Arguments 2>&1 3>&1
        }
        else {
            $records = & $command @Arguments 2>&1 3>&1
        }
    }
    finally {
        if ($WorkingDirectory) { Pop-Location }
    }
    $exitCode = $global:LASTEXITCODE

    $output = New-Object 'System.Collections.Generic.List[string]'
    $errors = New-Object 'System.Collections.Generic.List[string]'
    $warnings = New-Object 'System.Collections.Generic.List[string]'
    foreach ($record in @($records)) {
        if ($record -is [System.Management.Automation.ErrorRecord]) { $errors.Add($record.Exception.Message) }
        elseif ($record -is [System.Management.Automation.WarningRecord]) { $warnings.Add($record.Message) }
        elseif ($null -ne $record) { $output.Add([string]$record) }
    }

    [pscustomobject]@{
        Output      = $output.ToArray()
        Text        = $output -join "`n"
        Errors      = $errors.ToArray()
        ErrorText   = $errors -join "`n"
        Warnings    = $warnings.ToArray()
        WarningText = $warnings -join "`n"
        ExitCode    = $exitCode
    }
}

function New-TestFile {
    <#
    .SYNOPSIS
    Writes a test file (UTF-8 without BOM, content written exactly as given) and returns its path.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowEmptyString()][string]$Content = '',
        [byte[]]$Bytes
    )

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) { $null = New-Item -ItemType Directory -Path $directory -Force }
    if ($PSBoundParameters.ContainsKey('Bytes')) { [System.IO.File]::WriteAllBytes($Path, $Bytes) }
    else { [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false))) }
    $Path
}

function Test-IsWindowsPlatform {
    <#
    .SYNOPSIS
    $true on Windows (works on Windows PowerShell 5.1, which has no $IsWindows).
    #>
    $PSVersionTable.PSEdition -ne 'Core' -or [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
}

function New-TestDirectoryLink {
    <#
    .SYNOPSIS
    Creates a link Path -> Target directory: a symbolic link if allowed, else (Windows) a junction,
    which needs neither admin rights nor developer mode. Returns $false if neither works.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Target
    )

    try {
        $null = New-Item -ItemType SymbolicLink -Path $Path -Value $Target -ErrorAction Stop
        return $true
    }
    catch {
        if (-not (Test-IsWindowsPlatform)) { return $false }
    }
    try {
        $null = New-Item -ItemType Junction -Path $Path -Value $Target -ErrorAction Stop
        $true
    }
    catch {
        $false
    }
}

function Use-TestConsoleInput {
    <#
    .SYNOPSIS
    Runs Script with [Console]::In reading Text (and [Console]::Error captured as .ConsoleError of the result).
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][scriptblock]$Script
    )

    $originalIn = [System.Console]::In
    $originalError = [System.Console]::Error
    $errorWriter = New-Object System.IO.StringWriter
    [System.Console]::SetIn((New-Object System.IO.StringReader -ArgumentList $Text))
    [System.Console]::SetError($errorWriter)
    try { $result = & $Script }
    finally {
        [System.Console]::SetIn($originalIn)
        [System.Console]::SetError($originalError)
    }
    # Prompts (rm -i) go to the console's stderr; attach them to Invoke-TestGnu results.
    if ($result -is [pscustomobject]) { Add-Member -InputObject $result -NotePropertyName 'ConsoleError' -NotePropertyValue $errorWriter.ToString() -Force }
    $result
}

function Lock-TestFile {
    <#
    .SYNOPSIS
    Opens Path exclusively and returns the stream (dispose it to unlock), or nothing if the OS does not enforce the lock.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try {
        $null = [System.IO.File]::ReadAllBytes($Path)
        $stream.Dispose()
    }
    catch {
        $stream
    }
}
