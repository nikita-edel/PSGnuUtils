# User and group identities for id and groups.
#
# Get-GnuIdentity returns @{ UserId; UserName; GroupId; GroupName; Groups = @(@{ Id; Name }, ...) }.
# Windows uses SIDs as ids and DOMAIN\name as names. Linux reads /proc/self/status, /etc/passwd and
# /etc/group (the paths are parameters, so the parser is testable everywhere). Other Unix systems
# ask the system id command.

function Get-GnuIdentity {
    <#
    .SYNOPSIS
    The identity of the current user, or of User; $null if the user does not exist.
    .PARAMETER Real
    The real instead of the effective ids (they only differ for setuid programs on Unix).
    #>
    param([AllowEmptyString()][string]$User, [switch]$Real, [string]$StatusPath = '/proc/self/status')

    if (Test-GnuWindows) { return Get-GnuWindowsIdentity -User $User }
    if ([System.IO.File]::Exists($StatusPath)) { return Get-GnuLinuxIdentity -User $User -Real:$Real }
    Get-GnuNativeIdentity -User $User -Real:$Real
}

function ConvertTo-GnuAccountName {
    <#
    .SYNOPSIS
    The DOMAIN\name of a SID, or $null if it cannot be translated.
    #>
    param([Parameter(Mandatory)][System.Security.Principal.SecurityIdentifier]$Sid)
    try { $Sid.Translate([System.Security.Principal.NTAccount]).Value } catch { $null }
}

function Get-GnuWindowsIdentity {
    <#
    .SYNOPSIS
    The Windows identity: SIDs as ids. Other users get their SID only (no group information).
    #>
    param([AllowEmptyString()][string]$User)

    if (-not [string]::IsNullOrEmpty($User)) {
        try { $sid = (New-Object System.Security.Principal.NTAccount -ArgumentList $User).Translate([System.Security.Principal.SecurityIdentifier]) }
        catch { return $null }
        return @{ UserId = $sid.Value; UserName = (ConvertTo-GnuAccountName -Sid $sid); GroupId = $null; GroupName = $null; Groups = @() }
    }
    $current = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    # The primary group of local and domain accounts: "None" / "Domain Users" (RID 513).
    $groupSid = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList ($current.User.AccountDomainSid.Value + '-513')
    $groups = @(foreach ($sid in $current.Groups) {
            $value = $sid.Translate([System.Security.Principal.SecurityIdentifier])
            # The primary group is listed first already.
            if ($value.Value -ne $groupSid.Value) { @{ Id = $value.Value; Name = (ConvertTo-GnuAccountName -Sid $value) } }
        })
    @{
        UserId    = $current.User.Value
        UserName  = $current.Name
        GroupId   = $groupSid.Value
        GroupName = (ConvertTo-GnuAccountName -Sid $groupSid)
        Groups    = @(@{ Id = $groupSid.Value; Name = (ConvertTo-GnuAccountName -Sid $groupSid) }) + $groups
    }
}

function Read-GnuColonFile {
    <#
    .SYNOPSIS
    The colon separated records of /etc/passwd or /etc/group (comments and blank lines skipped).
    #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return }
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ([string]::IsNullOrEmpty($line) -or $line.StartsWith('#', [System.StringComparison]::Ordinal)) { continue }
        , ($line.Split(':'))
    }
}

function Get-GnuLinuxIdentity {
    <#
    .SYNOPSIS
    The Linux identity from /proc/self/status (current user) or /etc/passwd (other users).
    #>
    param(
        [AllowEmptyString()][string]$User,
        [switch]$Real,
        [string]$StatusPath = '/proc/self/status',
        [string]$PasswdPath = '/etc/passwd',
        [string]$GroupPath = '/etc/group'
    )

    $passwd = @(Read-GnuColonFile -Path $PasswdPath)
    $groupFile = @(Read-GnuColonFile -Path $GroupPath)
    $userNames = @{}
    foreach ($record in $passwd) { if ($record.Count -ge 4 -and -not $userNames.ContainsKey($record[2])) { $userNames[$record[2]] = $record[0] } }
    $groupNames = @{}
    foreach ($record in $groupFile) { if ($record.Count -ge 3 -and -not $groupNames.ContainsKey($record[2])) { $groupNames[$record[2]] = $record[0] } }

    if ([string]::IsNullOrEmpty($User)) {
        $field = 1
        if ($Real) { $field = 0 }
        $status = @{}
        foreach ($line in [System.IO.File]::ReadAllLines($StatusPath)) {
            if ($line -match '^(\w+):\s*(.*)$') { $status[$Matches[1]] = @($Matches[2] -split '\s+' | Where-Object { $_ }) }
        }
        $uid = $status['Uid'][$field]
        $gid = $status['Gid'][$field]
        $groupIds = @($gid) + @($status['Groups'] | Where-Object { $_ -ne $gid })
    }
    else {
        $entry = @($passwd | Where-Object { $_[0] -ceq $User -or $_[2] -ceq $User }) | Select-Object -First 1
        if ($null -eq $entry) { return $null }
        $uid = $entry[2]
        $gid = $entry[3]
        $member = @($groupFile | Where-Object { $_.Count -ge 4 -and @($_[3].Split(',')) -ccontains $entry[0] } | ForEach-Object { $_[2] })
        $groupIds = @($gid) + @($member | Where-Object { $_ -ne $gid })
    }
    @{
        UserId    = $uid
        UserName  = $userNames[$uid]
        GroupId   = $gid
        GroupName = $groupNames[$gid]
        Groups    = @(foreach ($id in $groupIds) { @{ Id = $id; Name = $groupNames[$id] } })
    }
}

function Get-GnuNativeIdentity {
    <#
    .SYNOPSIS
    The identity from the system's id command (macOS and other Unix systems without /proc).
    #>
    param([AllowEmptyString()][string]$User, [switch]$Real, [string]$IdCommand = '/usr/bin/id')

    $extra = @()
    if ($Real) { $extra += '-r' }
    if (-not [string]::IsNullOrEmpty($User)) { $extra += $User }
    $uid = [string](& $IdCommand -u @extra 2>$null)
    if ([string]::IsNullOrEmpty($uid)) { return $null }
    $ids = @(([string](& $IdCommand -G @extra)) -split '\s+' | Where-Object { $_ })
    $names = @(([string](& $IdCommand -Gn @extra)) -split '\s+' | Where-Object { $_ })
    @{
        UserId    = $uid
        UserName  = [string](& $IdCommand -un @extra)
        GroupId   = [string](& $IdCommand -g @extra)
        GroupName = [string](& $IdCommand -gn @extra)
        Groups    = @(for ($i = 0; $i -lt $ids.Count; $i++) { @{ Id = $ids[$i]; Name = $names[$i] } })
    }
}
