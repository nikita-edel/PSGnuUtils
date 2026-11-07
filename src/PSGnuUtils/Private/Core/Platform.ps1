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
        $runtime = [System.Runtime.InteropServices.RuntimeInformation]
        $os = [System.Runtime.InteropServices.OSPlatform]
        if ($runtime::IsOSPlatform($os::Windows)) { $platform = 'Windows' }
        elseif ($runtime::IsOSPlatform($os::Linux)) { $platform = 'Linux' }
        elseif ($runtime::IsOSPlatform($os::OSX)) { $platform = 'MacOS' }
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
    #>
    $architecture = $null
    try { $architecture = [string][System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture }
    catch { $architecture = $null }
    if (-not $architecture) { $architecture = [string]$env:PROCESSOR_ARCHITECTURE }

    switch -Regex ($architecture) {
        '^(X64|AMD64)$' { return 'x86_64' }
        '^X86$' { return 'i686' }
        '^ARM64$' { if ((Get-GnuPlatform) -eq 'MacOS') { return 'arm64' } else { return 'aarch64' } }
        '^ARM$' { return 'armv7l' }
    }
    if ($architecture) { return $architecture.ToLowerInvariant() }
    'unknown'
}

function Get-GnuOsInfo {
    <#
    .SYNOPSIS
    Collects the fields printed by uname.
    #>
    $platform = Get-GnuPlatform
    $description = ''
    try { $description = [string][System.Runtime.InteropServices.RuntimeInformation]::OSDescription }
    catch { $description = '' }

    $info = @{
        NodeName         = [System.Net.Dns]::GetHostName()
        Machine          = Get-GnuMachineName
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
    $method = [System.IO.File].GetMethods() |
        Where-Object { $_.Name -eq 'SetUnixFileMode' -and $_.GetParameters()[0].ParameterType -eq [string] } |
        Select-Object -First 1
    if ($null -eq $method) { return $false }

    $enumType = $method.GetParameters()[1].ParameterType
    [void]$method.Invoke($null, @($Path, [System.Enum]::ToObject($enumType, $Mode)))
    $true
}
