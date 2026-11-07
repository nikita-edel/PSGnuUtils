# GNU style --help text, generated from the util spec.

function Format-GnuOptionHelp {
    <#
    .SYNOPSIS
    Formats one option line, e.g. "  -n, --lines=NUM          print the first NUM lines".
    #>
    param([Parameter(Mandatory)][hashtable]$Option)

    $left = '  '
    if ($Option.Short) {
        $left += "-$($Option.Short)"
        if ($Option.Long) { $left += ', ' }
    }
    else {
        $left += '    '
    }

    if ($Option.Long) {
        $left += "--$($Option.Long)"
        if ($Option.Arg) {
            if ($Option.OptionalArg) { $left += "[=$($Option.Arg)]" } else { $left += "=$($Option.Arg)" }
        }
    }
    elseif ($Option.Arg) {
        $left += " $($Option.Arg)"
    }

    $width = 30
    if ($left.Length -ge $width - 1) {
        $left
        (' ' * $width) + $Option.Help
    }
    else {
        $left.PadRight($width) + $Option.Help
    }
}

function Get-GnuHelpText {
    <#
    .SYNOPSIS
    Builds the --help text of a util: usage lines, description, options, notes.
    #>
    param([Parameter(Mandatory)][hashtable]$Spec)

    $usage = @($Spec.Usage)
    for ($i = 0; $i -lt $usage.Count; $i++) {
        if ($i -eq 0) { "Usage: $($usage[$i])" } else { "  or:  $($usage[$i])" }
    }

    $description = @($Spec.Description)
    if ($description.Count -eq 0) { $description = @($Spec.Synopsis) }
    foreach ($line in $description) { $line }

    ''
    foreach ($option in @($Spec.Options) + @(Get-GnuStandardOption)) {
        if (-not $option.Hidden) { Format-GnuOptionHelp -Option $option }
    }

    $notes = @($Spec.Notes)
    if ($notes.Count -gt 0) {
        ''
        foreach ($line in $notes) { $line }
    }

    ''
    "PSGnuUtils $(Get-GnuModuleVersion): PowerShell implementation of GNU $($Spec.Name)."
    "PowerShell help: Get-Help $($Spec.FunctionName) -Full"
}
