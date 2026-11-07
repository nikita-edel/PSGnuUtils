@{
    Severity     = @('Error', 'Warning')

    ExcludeRules = @(
        # Util functions are named after GNU tools (Invoke-GnuYes, Invoke-GnuSha256sum).
        'PSUseSingularNouns'
        # Utils set $global:LASTEXITCODE so they report status like native commands.
        'PSAvoidGlobalVars'
        # Enable-GnuUtil intentionally creates global aliases with the GNU names.
        'PSAvoidGlobalAliases'
        # Private helpers named Set-*/New-* only change in-memory state; Enable/Disable are not destructive.
        'PSUseShouldProcessForStateChangingFunctions'
        # build.ps1 prints progress for humans.
        'PSAvoidUsingWriteHost'
    )

    Rules        = @{
        # Everything in src/ must parse and run on Windows PowerShell 5.1 and PowerShell 7.
        PSUseCompatibleSyntax  = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }
        PSUseCompatibleCmdlets = @{
            Compatibility = @(
                'desktop-5.1.14393.206-windows'
                'core-6.1.0-windows'
                'core-6.1.0-linux'
                'core-6.1.0-macos'
            )
        }
    }
}
