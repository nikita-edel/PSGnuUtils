Register-GnuUtil @{
    Name        = 'groups'
    Category    = 'User and system info'
    Synopsis    = 'Print the groups a user is in.'
    Usage       = @('groups [OPTION]... [USERNAME]...')
    Description = @(
        'Print group memberships for each USERNAME or, if no USERNAME is specified, for',
        'the current process (which may differ if the groups database has changed).'
    )
    Notes       = @('PowerShell note: on Windows the names are DOMAIN\NAME (SIDs for unknown groups); other users have no group information.')
}

function Invoke-GnuGroups {
    <#
    .SYNOPSIS
    GNU groups: print the groups a user is in.

    .DESCRIPTION
    Prints the group names of the current user, or "USER : GROUP..." for each USERNAME.
    Enable the GNU name with: Enable-GnuAlias groups

    .EXAMPLE
    Invoke-GnuGroups
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'groups' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            $users = @($ctx.Operands)
            if ($users.Count -eq 0) { $users = @('') }
            foreach ($user in $users) {
                $identity = Get-GnuIdentity -User $user
                if ($null -eq $identity) { Write-GnuError -Context $ctx -Message "'$user': no such user"; continue }
                $names = @(foreach ($group in $identity.Groups) { if ($group.Name) { $group.Name } else { $group.Id } }) -join ' '
                if ([string]::IsNullOrEmpty($user)) { $names } else { "$user : $names" }
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}
