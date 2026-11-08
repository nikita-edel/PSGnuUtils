Register-GnuUtil @{
    Name        = 'pathchk'
    Category    = 'Paths and names'
    Synopsis    = 'Check whether file names are valid or portable.'
    Usage       = @('pathchk [OPTION]... NAME...')
    Description = @('Diagnose invalid or non-portable file names.')
    Options     = @(
        @{ Short = 'p'; Key = 'posix'; Help = 'check for most POSIX systems' }
        @{ Short = 'P'; Key = 'extra'; Help = 'check for empty names and leading "-"' }
        @{ Long = 'portability'; Sets = @{ posix = 1; extra = 1 }; Help = 'check for all POSIX systems (equivalent to -p -P)' }
    )
    Notes       = @('PowerShell note: without -p the limits are 255 bytes per component and 4096 bytes per name.')
}

function Invoke-GnuPathchk {
    <#
    .SYNOPSIS
    GNU pathchk: check whether file names are valid or portable.

    .DESCRIPTION
    Reports names whose components are too long, and with -p names that are not portable to
    every POSIX system (14 byte components, 256 byte names, only A-Z a-z 0-9 . _ -).
    -P additionally rejects empty names and components starting with '-'.
    Enable the GNU name with: Enable-GnuAlias pathchk

    .EXAMPLE
    Invoke-GnuPathchk --portability 'my file.txt'
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'pathchk' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            $operands = @($ctx.Operands)
            if ($operands.Count -eq 0) {
                Write-GnuUsageError -Context $ctx -Message 'missing operand'
            }
            else {
                $posix = Test-GnuOption -Context $ctx -Key 'posix'
                $extra = Test-GnuOption -Context $ctx -Key 'extra'
                foreach ($name in $operands) {
                    $problem = Test-GnuPathName -Name $name -Posix:$posix -Extra:$extra
                    if ($problem) { Write-GnuError -Context $ctx -Message $problem }
                }
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}

function Test-GnuPathName {
    <#
    .SYNOPSIS
    Returns the first problem of a file name as a GNU message, or nothing if the name is fine.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [switch]$Posix,
        [switch]$Extra
    )

    if ($Extra) {
        if ($Name.Length -eq 0) { return 'empty file name' }
        foreach ($component in $Name.Split('/')) {
            if ($component.StartsWith('-', [System.StringComparison]::Ordinal)) { return "leading '-' in a component of file name '$Name'" }
        }
    }
    elseif ($Name.Length -eq 0) {
        # GNU without -P: an empty name does not exist, like "pathchk ''" -> No such file or directory
        return "'': No such file or directory"
    }

    if ($Posix) {
        foreach ($char in $Name.ToCharArray()) {
            if ($char -cnotmatch '[A-Za-z0-9._/-]') { return "nonportable character '$char' in file name '$Name'" }
        }
    }

    $nameLimit = 4096
    $componentLimit = 255
    if ($Posix) {
        $nameLimit = 256
        $componentLimit = 14
    }
    $nameLength = $script:GnuUtf8.GetByteCount($Name)
    if ($nameLength -gt $nameLimit) { return "limit $nameLimit exceeded by length $nameLength of file name '$Name'" }
    foreach ($component in $Name.Split('/')) {
        $length = $script:GnuUtf8.GetByteCount($component)
        if ($length -gt $componentLimit) { return "limit $componentLimit exceeded by length $length of file name component '$component'" }
    }
}
