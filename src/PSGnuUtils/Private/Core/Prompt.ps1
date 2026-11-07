# Interactive confirmation (rm -i, cp -i, mv -i, ln -i).

function Read-GnuConfirmation {
    <#
    .SYNOPSIS
    Writes a GNU style prompt to standard error and returns $true if the answer starts with y or Y.
    .NOTES
    Reads [Console]::In like GNU reads stdin; an empty or missing answer means no.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$Question
    )

    [System.Console]::Error.Write("$($Context.Name): $Question ")
    $answer = [System.Console]::In.ReadLine()
    $null -ne $answer -and $answer -match '^[yY]'
}
