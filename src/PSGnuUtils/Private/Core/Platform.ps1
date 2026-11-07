# Platform detection.
#
# Windows PowerShell 5.1 has no $IsWindows / $IsLinux / $IsMacOS, and reading those variables
# there fails under strict mode. All OS checks must go through these functions.

$script:GnuPlatformCache = $null

function Get-GnuPlatform {
    <#
    .SYNOPSIS
    Returns 'Windows', 'Linux', 'MacOS' or 'Unix'.
    #>
    if ($null -ne $script:GnuPlatformCache) { return $script:GnuPlatformCache }

    $platform = 'Windows'
    if ($PSVersionTable.PSEdition -eq 'Core') {
        if (Test-GnuOSPlatform -Name 'Windows') { $platform = 'Windows' }
        elseif (Test-GnuOSPlatform -Name 'Linux') { $platform = 'Linux' }
        elseif (Test-GnuOSPlatform -Name 'OSX') { $platform = 'MacOS' }
        else { $platform = 'Unix' }
    }
    $script:GnuPlatformCache = $platform
    $platform
}

function Test-GnuWindows {
    <#
    .SYNOPSIS
    Returns $true on Windows (Windows PowerShell 5.1 or PowerShell 7 on Windows).
    #>
    (Get-GnuPlatform) -eq 'Windows'
}

function Get-GnuPathSeparator {
    <#
    .SYNOPSIS
    Characters that separate path components: '/' everywhere, plus '\' on Windows.
    #>
    if (Test-GnuWindows) { return [char[]]@('/', '\') }
    [char[]]@('/')
}

function Get-GnuMachineName {
    <#
    .SYNOPSIS
    Hardware name as printed by 'uname -m' (x86_64, aarch64, arm64 on macOS, i686, armv7l).
    .PARAMETER Architecture
    .NET / Windows architecture name (X64, Arm64, AMD64, ...). Detected when omitted.
    .PARAMETER Platform
    Result of Get-GnuPlatform. Detected when omitted.
    #>
    param(
        [AllowEmptyString()][string]$Architecture,
        [string]$Platform
    )

    if (-not $PSBoundParameters.ContainsKey('Architecture')) {
        $Architecture = Get-GnuRuntimeInformation -Property 'OSArchitecture'
        if (-not $Architecture) { $Architecture = [string]$env:PROCESSOR_ARCHITECTURE }
    }
    if (-not $Platform) { $Platform = Get-GnuPlatform }

    switch -Regex ($Architecture) {
        '^(X64|AMD64)$' { return 'x86_64' }
        '^X86$' { return 'i686' }
        '^ARM64$' { if ($Platform -eq 'MacOS') { return 'arm64' } else { return 'aarch64' } }
        '^ARM$' { return 'armv7l' }
    }
    if ($Architecture) { return $Architecture.ToLowerInvariant() }
    'unknown'
}

function Get-GnuOsInfo {
    <#
    .SYNOPSIS
    Collects the fields printed by uname.
    .PARAMETER Platform
    Result of Get-GnuPlatform. Detected when omitted.
    .PARAMETER Description
    RuntimeInformation.OSDescription. Detected when omitted.
    #>
    param(
        [string]$Platform,
        [AllowEmptyString()][string]$Description
    )

    if (-not $Platform) { $Platform = Get-GnuPlatform }
    if (-not $PSBoundParameters.ContainsKey('Description')) {
        $Description = Get-GnuRuntimeInformation -Property 'OSDescription'
    }
    $platform = $Platform
    $description = $Description

    $info = @{
        NodeName         = [System.Net.Dns]::GetHostName()
        Machine          = Get-GnuMachineName -Platform $platform
        Processor        = 'unknown'
        HardwarePlatform = 'unknown'
    }

    if ($platform -eq 'Windows') {
        $info.KernelName = 'Windows_NT'
        $info.KernelRelease = [System.Environment]::OSVersion.Version.ToString()
        $info.KernelVersion = [System.Environment]::OSVersion.VersionString
        if ($description) { $info.KernelVersion = $description.Trim() }
        $info.OperatingSystem = 'Windows'
        return $info
    }

    # On Unix, OSDescription is "<kernel name> <release> <version...>" (like uname -srv).
    $parts = @($description.Trim() -split '\s+', 3)
    $info.KernelName = 'Unix'
    $info.KernelRelease = [System.Environment]::OSVersion.Version.ToString()
    $info.KernelVersion = ''
    if ($parts.Count -ge 1 -and $parts[0]) { $info.KernelName = $parts[0] }
    if ($parts.Count -ge 2) { $info.KernelRelease = $parts[1] }
    if ($parts.Count -ge 3) { $info.KernelVersion = $parts[2] }
    switch ($platform) {
        'Linux' { $info.OperatingSystem = 'GNU/Linux' }
        'MacOS' { $info.OperatingSystem = 'Darwin' }
        default { $info.OperatingSystem = $info.KernelName }
    }
    $info
}

function Set-GnuUnixMode {
    <#
    .SYNOPSIS
    Sets Unix permission bits when the runtime supports it (.NET 7+, i.e. PowerShell 7.3+ on Unix).
    .OUTPUTS
    $true if the mode was applied, $false if the platform does not support it (Windows, older runtimes).
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$Mode
    )

    if (Test-GnuWindows) { return $false }
    $method = Get-GnuUnixModeMethod
    if ($null -eq $method) { return $false }

    $enumType = $method.GetParameters()[1].ParameterType
    [void]$method.Invoke($null, @($Path, [System.Enum]::ToObject($enumType, $Mode)))
    $true
}

function Test-GnuOSPlatform {
    <#
    .SYNOPSIS
    RuntimeInformation.IsOSPlatform for an OSPlatform name (Windows, Linux, OSX, FreeBSD). PowerShell 7 only.
    #>
    param([Parameter(Mandatory)][string]$Name)
    [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::$Name)
}

function Get-GnuRuntimeInformation {
    <#
    .SYNOPSIS
    A static property of RuntimeInformation (OSArchitecture, OSDescription, ...) as string, or '' if unavailable.
    .PARAMETER TypeName
    The type to read from (default: System.Runtime.InteropServices.RuntimeInformation, which very old
    .NET Framework versions do not have).
    #>
    param(
        [Parameter(Mandatory)][string]$Property,
        [string]$TypeName = 'System.Runtime.InteropServices.RuntimeInformation'
    )

    $type = $TypeName -as [type]
    if ($null -eq $type) { return '' }
    $info = $type.GetProperty($Property)
    if ($null -eq $info) { return '' }
    [string]$info.GetValue($null, $null)
}

function Get-GnuUnixModeMethod {
    <#
    .SYNOPSIS
    The File.SetUnixFileMode(string, UnixFileMode) method (.NET 7+), or nothing on older runtimes.
    #>
    [System.IO.File].GetMethods() |
        Where-Object { $_.Name -eq 'SetUnixFileMode' -and $_.GetParameters()[0].ParameterType -eq [string] } |
        Select-Object -First 1
}

function Get-GnuUnixFileMode {
    <#
    .SYNOPSIS
    The Unix permission bits of a file (.NET 7+ on Unix), or nothing on Windows and older runtimes.
    #>
    param([Parameter(Mandatory)][string]$Path)
    if (Test-GnuWindows) { return }
    $method = Get-GnuFileMethod -Name 'GetUnixFileMode' -ParameterTypes @([string])
    if ($null -eq $method) { return }
    [int]$method.Invoke($null, @($Path))
}

function Get-GnuFileMethod {
    <#
    .SYNOPSIS
    A static System.IO.File method by name and parameter types, or nothing if this runtime does not have it.
    #>
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][type[]]$ParameterTypes)
    [System.IO.File].GetMethod($Name, $ParameterTypes)
}
