Register-GnuUtil @{
    Name         = 'basenc'
    Category     = 'Viewing file contents'
    Synopsis     = 'Encode/decode data and print to standard output.'
    Usage        = @('basenc [OPTION]... [FILE]')
    Description  = @('basenc encode or decode FILE, or standard input, to standard output.', '', 'With no FILE, or when FILE is -, read standard input.')
    FileOperands = $true
    Options      = @(
        @{ Long = 'base64'; Key = 'encoding'; Value = 'base64'; Help = 'same as ''base64'' program (RFC4648 section 4)' }
        @{ Long = 'base64url'; Key = 'encoding'; Value = 'base64url'; Help = 'file- and url-safe base64 (RFC4648 section 5)' }
        @{ Long = 'base32'; Key = 'encoding'; Value = 'base32'; Help = 'same as ''base32'' program (RFC4648 section 6)' }
        @{ Long = 'base32hex'; Key = 'encoding'; Value = 'base32hex'; Help = 'extended hex alphabet base32 (RFC4648 section 7)' }
        @{ Long = 'base16'; Key = 'encoding'; Value = 'base16'; Help = 'hex encoding (RFC4648 section 8)' }
        @{ Long = 'base2msbf'; Key = 'encoding'; Value = 'base2msbf'; Help = 'bit string with most significant bit (msb) first' }
        @{ Long = 'base2lsbf'; Key = 'encoding'; Value = 'base2lsbf'; Help = 'bit string with least significant bit (lsb) first' }
        @{ Short = 'd'; Long = 'decode'; Help = 'decode data' }
        @{ Short = 'i'; Long = 'ignore-garbage'; Help = 'when decoding, ignore non-alphabet characters' }
        @{ Short = 'w'; Long = 'wrap'; Arg = 'COLS'; Help = 'wrap encoded lines after COLS character (default 76). Use 0 to disable line wrapping' }
        @{ Long = 'z85'; Key = 'encoding'; Value = 'z85'; Help = 'ascii85-like encoding (ZeroMQ spec:32/Z85); when encoding, input length must be a multiple of 4; when decoding, input length must be a multiple of 5' }
    )
    Notes        = @(
        'When decoding, the input may contain newlines in addition to the bytes of the',
        'formal alphabet. Use --ignore-garbage to attempt to recover from any other',
        'non-alphabet bytes in the encoded stream.',
        '',
        'PowerShell note: decoded output is written as UTF-8 text lines.'
    )
}

$script:GnuBasencAlphabets = @{
    base64    = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/='
    base64url = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_='
    base32    = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567='
    base32hex = '0123456789ABCDEFGHIJKLMNOPQRSTUV='
    base16    = '0123456789ABCDEFabcdef'
    base2msbf = '01'
    base2lsbf = '01'
    z85       = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-:+=^!/*?&<>()[]{}@%$#'
}

function Invoke-GnuBasenc {
    <#
    .SYNOPSIS
    GNU basenc: encode or decode data in base64, base64url, base32, base32hex, base16, base2 or Z85.

    .DESCRIPTION
    Encodes FILE (or pipeline input) with the selected encoding, wrapped at 76 columns
    (-w COLS, 0 = no wrapping). With -d, decodes; -i ignores characters outside the alphabet.
    Enable the GNU name with: Enable-GnuAlias basenc

    .EXAMPLE
    'hello' | Invoke-GnuBasenc --base16

    68656C6C6F0A
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'basenc' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuBasencCoding -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function Invoke-GnuBasencCoding {
    <#
    .SYNOPSIS
    Implementation of basenc.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $encoding = [string](Get-GnuOptionValue -Context $Context -Key 'encoding')
    if ([string]::IsNullOrEmpty($encoding)) { Write-GnuUsageError -Context $Context -Message 'missing encoding type'; return }
    $operands = @($Context.Operands)
    if ($operands.Count -gt 1) { Write-GnuUsageError -Context $Context -Message "extra operand '$($operands[1])'"; return }
    $operand = '-'
    if ($operands.Count -eq 1) { $operand = $operands[0] }

    $wrap = 76
    if (Test-GnuOption -Context $Context -Key 'wrap') {
        $wrapText = [string](Get-GnuOptionValue -Context $Context -Key 'wrap')
        if ($wrapText -notmatch '^\d+$') { Write-GnuError -Context $Context -Message "invalid wrap size: '$wrapText'"; return }
        $wrap = [int]$wrapText
    }

    if (Test-GnuOption -Context $Context -Key 'decode') {
        $text = Get-GnuInputText -Context $Context -Operand $operand
        if ($null -eq $text) { return }
        $alphabet = $script:GnuBasencAlphabets[$encoding]
        $ignoreGarbage = Test-GnuOption -Context $Context -Key 'ignore-garbage'
        $clean = New-Object System.Text.StringBuilder
        foreach ($char in $text.ToCharArray()) {
            if ($char -eq "`n" -or $char -eq "`r") { continue }
            if ($ignoreGarbage -and $alphabet.IndexOf($char) -lt 0) { continue }
            [void]$clean.Append($char)
        }
        $bytes = ConvertFrom-GnuBasencText -Text $clean.ToString() -Encoding $encoding
        if ($null -eq $bytes) { Write-GnuError -Context $Context -Message 'invalid input'; return }
        ConvertTo-GnuOutputLine -Text $script:GnuUtf8.GetString($bytes)
        return
    }

    $data = Get-GnuInputBytes -Context $Context -Operand $operand
    if ($null -eq $data) { return }
    if ($encoding -eq 'z85' -and $data.Length % 4 -ne 0) {
        Write-GnuError -Context $Context -Message 'invalid input (length must be multiple of 4 characters)'
        return
    }
    $encoded = ConvertTo-GnuBasencText -Bytes $data -Encoding $encoding
    if ([string]::IsNullOrEmpty($encoded)) { return }
    if ($wrap -eq 0) { return $encoded }
    for ($i = 0; $i -lt $encoded.Length; $i += $wrap) {
        $encoded.Substring($i, [Math]::Min($wrap, $encoded.Length - $i))
    }
}

function ConvertTo-GnuBasencText {
    <#
    .SYNOPSIS
    Encodes bytes with one of the basenc encodings.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes,
        [Parameter(Mandatory)][string]$Encoding
    )

    switch ($Encoding) {
        'base64' { return [System.Convert]::ToBase64String($Bytes) }
        'base64url' { return [System.Convert]::ToBase64String($Bytes).Replace('+', '-').Replace('/', '_') }
        'base32' { return ConvertTo-GnuBase32 -Bytes $Bytes }
        'base32hex' { return ConvertTo-GnuBase32 -Bytes $Bytes -Alphabet $script:GnuBasencAlphabets.base32hex.TrimEnd('=') }
        'base16' { return (($Bytes | ForEach-Object { $_.ToString('X2') }) -join '') }
        'z85' {
            $alphabet = $script:GnuBasencAlphabets.z85
            $builder = New-Object System.Text.StringBuilder
            for ($offset = 0; $offset -lt $Bytes.Length; $offset += 4) {
                $value = ([long]$Bytes[$offset] -shl 24) -bor ([long]$Bytes[$offset + 1] -shl 16) -bor ([long]$Bytes[$offset + 2] -shl 8) -bor [long]$Bytes[$offset + 3]
                $chars = New-Object char[] 5
                for ($k = 4; $k -ge 0; $k--) { $chars[$k] = $alphabet[[int]($value % 85)]; $value = [Math]::Floor($value / 85) }
                [void]$builder.Append($chars)
            }
            return $builder.ToString()
        }
    }
    # base2msbf / base2lsbf
    $builder = New-Object System.Text.StringBuilder
    foreach ($byte in $Bytes) {
        $bits = [Convert]::ToString([int]$byte, 2).PadLeft(8, '0')
        if ($Encoding -eq 'base2lsbf') { $bits = -join ($bits.ToCharArray()[7..0]) }
        [void]$builder.Append($bits)
    }
    $builder.ToString()
}

function ConvertFrom-GnuBasencText {
    <#
    .SYNOPSIS
    Decodes basenc text (line breaks removed). Returns one byte[] (not unrolled), or nothing if invalid.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Encoding
    )

    switch ($Encoding) {
        { $_ -eq 'base64' -or $_ -eq 'base64url' } {
            $standard = $Text
            if ($Encoding -eq 'base64url') {
                if ($Text.IndexOfAny([char[]]'+/') -ge 0) { return }
                $standard = $Text.Replace('-', '+').Replace('_', '/')
            }
            elseif ($Text.IndexOfAny([char[]]'-_') -ge 0) { return }
            try { return , [System.Convert]::FromBase64String($standard) } catch { return }
        }
        'base32' { return ConvertFrom-GnuBase32 -Text $Text }
        'base32hex' { return ConvertFrom-GnuBase32 -Text $Text -Alphabet $script:GnuBasencAlphabets.base32hex.TrimEnd('=') }
        'base16' {
            if ($Text.Length % 2 -ne 0 -or $Text -notmatch '^[0-9A-Fa-f]*$') { return }
            $bytes = New-Object byte[] ($Text.Length / 2)
            for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($Text.Substring(2 * $i, 2), 16) }
            return , $bytes
        }
        'z85' {
            if ($Text.Length % 5 -ne 0) { return }
            $alphabet = $script:GnuBasencAlphabets.z85
            $output = New-Object 'System.Collections.Generic.List[byte]'
            for ($offset = 0; $offset -lt $Text.Length; $offset += 5) {
                $value = [long]0
                for ($k = 0; $k -lt 5; $k++) {
                    $digit = $alphabet.IndexOf($Text[$offset + $k])
                    if ($digit -lt 0) { return }
                    $value = $value * 85 + $digit
                }
                if ($value -gt 0xFFFFFFFFL) { return }
                foreach ($shift in @(24, 16, 8, 0)) { $output.Add([byte](($value -shr $shift) -band 255)) }
            }
            return , $output.ToArray()
        }
    }
    # base2msbf / base2lsbf
    if ($Text.Length % 8 -ne 0 -or $Text -notmatch '^[01]*$') { return }
    $bytes = New-Object byte[] ($Text.Length / 8)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bits = $Text.Substring(8 * $i, 8)
        if ($Encoding -eq 'base2lsbf') { $bits = -join ($bits.ToCharArray()[7..0]) }
        $bytes[$i] = [Convert]::ToByte($bits, 2)
    }
    , $bytes
}
