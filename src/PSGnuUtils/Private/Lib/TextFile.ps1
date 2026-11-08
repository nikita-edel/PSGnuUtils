# Reading text files so that their exact bytes can be written back (sed -i) or compared (diff).

function Read-GnuTextFile {
    <#
    .SYNOPSIS
    The bytes of a file as text: @{ Text; Encoding }. Invalid UTF-8 is read as Latin-1, so writing it back keeps every byte.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $strict = New-Object System.Text.UTF8Encoding($false, $true)
    $start = 0
    $encoding = $script:GnuUtf8
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
        $start = 3
        $encoding = New-Object System.Text.UTF8Encoding($true)
    }
    try { return @{ Text = $strict.GetString($bytes, $start, $bytes.Length - $start); Encoding = $encoding } }
    catch [System.Text.DecoderFallbackException] {
        $latin = [System.Text.Encoding]::GetEncoding(28591)
        return @{ Text = $latin.GetString($bytes); Encoding = $latin }
    }
}
