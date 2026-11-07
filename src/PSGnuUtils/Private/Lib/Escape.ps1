# Backslash escape interpretation (echo -e; printf will reuse it).

function ConvertFrom-GnuEscape {
    <#
    .SYNOPSIS
    Interprets backslash escapes the way 'echo -e' does.
    .DESCRIPTION
    Supported: \\ \a \b \c \e \f \n \r \t \v \0NNN (octal, up to 3 digits) \xHH (hex, 1-2 digits).
    \c stops all further output. Unknown escapes are kept literally.
    .OUTPUTS
    Hashtable with Text (the result) and Stop ($true if \c was seen).
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $builder = New-Object System.Text.StringBuilder
    $stop = $false
    $i = 0
    while ($i -lt $Text.Length) {
        $char = $Text[$i]
        if ($char -ne '\' -or $i + 1 -ge $Text.Length) {
            [void]$builder.Append($char)
            $i++
            continue
        }

        $next = [string]$Text[$i + 1]
        $i += 2
        switch -CaseSensitive ($next) {
            '\' { [void]$builder.Append('\') }
            'a' { [void]$builder.Append([char]7) }
            'b' { [void]$builder.Append([char]8) }
            'c' { $stop = $true }
            'e' { [void]$builder.Append([char]27) }
            'f' { [void]$builder.Append([char]12) }
            'n' { [void]$builder.Append([char]10) }
            'r' { [void]$builder.Append([char]13) }
            't' { [void]$builder.Append([char]9) }
            'v' { [void]$builder.Append([char]11) }
            '0' {
                $digits = ''
                while ($digits.Length -lt 3 -and $i -lt $Text.Length -and '01234567'.IndexOf($Text[$i]) -ge 0) {
                    $digits += $Text[$i]
                    $i++
                }
                $value = 0
                if ($digits) { $value = [System.Convert]::ToInt32($digits, 8) }
                [void]$builder.Append([char]($value -band 255))
            }
            'x' {
                $digits = ''
                while ($digits.Length -lt 2 -and $i -lt $Text.Length -and '0123456789abcdefABCDEF'.IndexOf($Text[$i]) -ge 0) {
                    $digits += $Text[$i]
                    $i++
                }
                if ($digits) { [void]$builder.Append([char][System.Convert]::ToInt32($digits, 16)) }
                else { [void]$builder.Append('\x') }
            }
            default { [void]$builder.Append('\').Append($next) }
        }
        if ($stop) { break }
    }

    @{ Text = $builder.ToString(); Stop = $stop }
}
