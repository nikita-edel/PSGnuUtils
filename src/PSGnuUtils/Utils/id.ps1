Register-GnuUtil @{
    Name        = 'id'
    Category    = 'User and system info'
    Synopsis    = 'Print real and effective user and group IDs.'
    Usage       = @('id [OPTION]... [USER]...')
    Description = @(
        'Print user and group information for each specified USER,',
        'or (when USER omitted) for the current user.'
    )
    Options     = @(
        @{ Short = 'a'; Help = 'ignore, for compatibility with other versions' }
        @{ Short = 'Z'; Long = 'context'; Help = 'print only the security context of the process' }
        @{ Short = 'g'; Long = 'group'; Help = 'print only the effective group ID' }
        @{ Short = 'G'; Long = 'groups'; Help = 'print all group IDs' }
        @{ Short = 'n'; Long = 'name'; Help = 'print a name instead of a number, for -ugG' }
        @{ Short = 'r'; Long = 'real'; Help = 'print the real ID instead of the effective ID, with -ugG' }
        @{ Short = 'u'; Long = 'user'; Help = 'print only the effective user ID' }
        @{ Short = 'z'; Long = 'zero'; Help = 'delimit entries with NUL characters, not whitespace; not permitted in default format' }
    )
    Notes       = @(
        'Without any OPTION, print some useful set of identified information.',
        '',
        'PowerShell note: on Windows the IDs are SIDs and the names DOMAIN\NAME; the primary',
        'group is the account domain''s RID 513 group (None / Domain Users). For other users',
        'Windows shows only the user SID. -Z (SELinux) is not supported.'
    )
}

function Invoke-GnuId {
    <#
    .SYNOPSIS
    GNU id: print user and group IDs.

    .DESCRIPTION
    Prints "uid=ID(NAME) gid=ID(NAME) groups=ID(NAME),..." for the current user or each USER;
    -u, -g or -G print only the user, group or all group IDs (-n names, -r real IDs, -z NUL).
    On Windows the IDs are SIDs.
    Enable the GNU name with: Enable-GnuUtil id

    .EXAMPLE
    Invoke-GnuId -un
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'id' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) { Invoke-GnuIdPrint -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function Format-GnuIdEntry {
    <#
    .SYNOPSIS
    "ID(NAME)", or "ID" when the name is unknown.
    #>
    param([AllowNull()][string]$Id, [AllowNull()][string]$Name)
    if ([string]::IsNullOrEmpty($Name)) { return $Id }
    "$Id($Name)"
}

function Invoke-GnuIdPrint {
    <#
    .SYNOPSIS
    Implementation of id.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $chosen = @('user', 'group', 'groups' | Where-Object { Test-GnuOption -Context $Context -Key $_ })
    $only = ''
    if ($chosen.Count -eq 1) { $only = $chosen[0] }
    $names = Test-GnuOption -Context $Context -Key 'name'
    $real = Test-GnuOption -Context $Context -Key 'real'
    $zero = Test-GnuOption -Context $Context -Key 'zero'
    if (Test-GnuOption -Context $Context -Key 'context') { Write-GnuError -Context $Context -Message '--context (-Z) works only on an SELinux-enabled kernel'; return }
    if ($chosen.Count -gt 1) { Write-GnuUsageError -Context $Context -Message 'cannot print "only" of more than one choice'; return }
    if ([string]::IsNullOrEmpty($only) -and ($names -or $real)) { Write-GnuUsageError -Context $Context -Message 'cannot print only names or real IDs in default format'; return }
    if ([string]::IsNullOrEmpty($only) -and $zero) { Write-GnuUsageError -Context $Context -Message 'option --zero not permitted in default format'; return }

    $users = @($Context.Operands)
    if ($users.Count -eq 0) { $users = @('') }
    $records = New-Object 'System.Collections.Generic.List[string]'
    foreach ($user in $users) {
        $identity = Get-GnuIdentity -User $user -Real:$real
        if ($null -eq $identity) { Write-GnuError -Context $Context -Message "'$user': no such user"; continue }
        switch ($only) {
            'user' { if ($names) { $records.Add([string]$identity.UserName) } else { $records.Add([string]$identity.UserId) } }
            'group' { if ($names) { $records.Add([string]$identity.GroupName) } else { $records.Add([string]$identity.GroupId) } }
            'groups' {
                $items = @(foreach ($group in $identity.Groups) { if ($names -and $group.Name) { $group.Name } else { $group.Id } })
                if ($zero) { foreach ($item in $items) { $records.Add($item) } } else { $records.Add($items -join ' ') }
            }
            default {
                $line = 'uid=' + (Format-GnuIdEntry -Id $identity.UserId -Name $identity.UserName)
                if ($null -ne $identity.GroupId) { $line += ' gid=' + (Format-GnuIdEntry -Id $identity.GroupId -Name $identity.GroupName) }
                if (@($identity.Groups).Count -gt 0) { $line += ' groups=' + (@($identity.Groups | ForEach-Object { Format-GnuIdEntry -Id $_.Id -Name $_.Name }) -join ',') }
                $records.Add($line)
            }
        }
    }
    ConvertTo-GnuRecordOutput -Record $records.ToArray() -Zero:$zero
}
