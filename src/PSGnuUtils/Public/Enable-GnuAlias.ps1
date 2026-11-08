function Enable-GnuAlias {
    <#
    .SYNOPSIS
    Makes GNU names (cat, head, sha256sum, ...) call the PSGnuUtils implementations.

    .DESCRIPTION
    Every util is always available under its PowerShell name (Invoke-GnuCat, Invoke-GnuHead, ...).
    Enable-GnuAlias additionally creates a global alias with the GNU name that points to that
    function.

    Aliases take precedence over functions, cmdlets and native executables, so an enabled GNU
    name always wins. Existing aliases with the same name (for example cat -> Get-Content or
    ls -> Get-ChildItem on Windows) are overridden and remembered; Disable-GnuAlias or
    Remove-Module PSGnuUtils restores them. Use -NoClobber to skip names that already resolve
    to another command instead.

    To enable utils in every session, add the call to your profile, or import with
    configuration:  Import-Module PSGnuUtils -ArgumentList @{ All = $true; Exclude = 'ls' }

    .PARAMETER Name
    Utils to enable. Wildcards are supported (sha*sum).

    .PARAMETER All
    Enable every util.

    .PARAMETER Exclude
    Utils to leave disabled when using -All or wildcards. Wildcards are supported.

    .PARAMETER NoClobber
    Do not enable a GNU name that already resolves to another alias, function, cmdlet or executable.

    .PARAMETER PassThru
    Return the util info objects (see Get-GnuUtil).

    .EXAMPLE
    Enable-GnuAlias -Name cat, head, tail

    cat, head and tail now run the GNU implementations.

    .EXAMPLE
    Enable-GnuAlias -All -Exclude ls, rm

    Enables everything except ls and rm.

    .EXAMPLE
    Enable-GnuAlias -All -NoClobber

    Enables only names that do not exist yet.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Name')]
    [OutputType('PSGnuUtils.UtilInfo')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Name', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [SupportsWildcards()]
        [string[]]$Name,

        [Parameter(Mandatory, ParameterSetName = 'All')]
        [switch]$All,

        [SupportsWildcards()]
        [string[]]$Exclude = @(),

        [switch]$NoClobber,

        [switch]$PassThru
    )

    process {
        $patterns = $Name
        if ($All) { $patterns = @('*') }

        foreach ($utilName in @(Resolve-GnuUtilName -Name $patterns -Exclude $Exclude)) {
            Enable-GnuUtilAlias -Name $utilName -NoClobber:$NoClobber
            if ($PassThru) { Get-GnuUtil -Name $utilName }
        }
    }
}
