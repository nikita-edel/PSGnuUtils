# Base64 / Base32 (RFC 4648) helpers shared by the base64 and base32 utils.

$script:GnuBase32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'
$script:GnuBase64Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

function ConvertTo-GnuBase32 {
    <#
    .SYNOPSIS
    Encodes bytes as RFC 4648 base32 with '=' padding.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)

    $builder = New-Object System.Text.StringBuilder
    for ($offset = 0; $offset -lt $Bytes.Length; $offset += 5) {
        $chunk = [Math]::Min(5, $Bytes.Length - $offset)
        [long]$buffer = 0
        for ($j = 0; $j -lt 5; $j++) {
            $buffer = $buffer -shl 8
            if ($j -lt $chunk) { $buffer = $buffer -bor $Bytes[$offset + $j] }
        }
        $dataChars = [int][Math]::Ceiling($chunk * 8 / 5)
        for ($k = 0; $k -lt 8; $k++) {
            if ($k -lt $dataChars) {
                $index = [int](($buffer -shr (35 - 5 * $k)) -band 31)
                [void]$builder.Append($script:GnuBase32Alphabet[$index])
            }
            else {
                [void]$builder.Append('=')
            }
        }
    }
    $builder.ToString()
}

function ConvertFrom-GnuBase32 {
    <#
    .SYNOPSIS
    Decodes RFC 4648 base32 (whitespace already removed). Returns one byte[] (not unrolled), or nothing if invalid.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    if ($Text.Length % 8 -ne 0) { return }
    $output = New-Object 'System.Collections.Generic.List[byte]'
    for ($offset = 0; $offset -lt $Text.Length; $offset += 8) {
        $block = $Text.Substring($offset, 8)
        $dataChars = $block.TrimEnd('=').Length
        if ($dataChars -lt 8 -and $offset + 8 -lt $Text.Length) { return }

        $byteCount = -1
        switch ($dataChars) { 8 { $byteCount = 5 } 7 { $byteCount = 4 } 5 { $byteCount = 3 } 4 { $byteCount = 2 } 2 { $byteCount = 1 } }
        if ($byteCount -lt 0) { return }

        [long]$buffer = 0
        for ($k = 0; $k -lt 8; $k++) {
            $value = 0
            if ($k -lt $dataChars) {
                $value = $script:GnuBase32Alphabet.IndexOf($block[$k])
                if ($value -lt 0) { return }
            }
            $buffer = ($buffer -shl 5) -bor $value
        }
        for ($b = 0; $b -lt $byteCount; $b++) {
            $output.Add([byte](($buffer -shr (32 - 8 * $b)) -band 255))
        }
    }
    , $output.ToArray()
}

function Get-GnuBaseAlphabet {
    <#
    .SYNOPSIS
    The alphabet of 'base64' or 'base32' (used by --ignore-garbage).
    #>
    param([Parameter(Mandatory)][ValidateSet('base64', 'base32')][string]$Encoding)
    if ($Encoding -eq 'base64') { return $script:GnuBase64Alphabet }
    $script:GnuBase32Alphabet
}

function Invoke-GnuBaseEncodingUtil {
    <#
    .SYNOPSIS
    Shared implementation of the base64 and base32 utils.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $encoding = $Context.Name
    $operands = @($Context.Operands)
    if ($operands.Count -gt 1) {
        Write-GnuUsageError -Context $Context -Message "extra operand '$($operands[1])'"
        return
    }
    $operand = '-'
    if ($operands.Count -eq 1) { $operand = $operands[0] }

    $wrap = 76
    if (Test-GnuOption -Context $Context -Key 'wrap') {
        $wrapText = [string](Get-GnuOptionValue -Context $Context -Key 'wrap')
        if ($wrapText -notmatch '^\d+$') {
            Write-GnuError -Context $Context -Message "invalid wrap size: '$wrapText'"
            return
        }
        $wrap = [int]$wrapText
    }

    if (Test-GnuOption -Context $Context -Key 'decode') {
        $text = Get-GnuInputText -Context $Context -Operand $operand
        if ($null -eq $text) { return }
        $alphabet = Get-GnuBaseAlphabet -Encoding $encoding
        $clean = New-Object System.Text.StringBuilder
        $ignoreGarbage = Test-GnuOption -Context $Context -Key 'ignore-garbage'
        foreach ($char in $text.ToCharArray()) {
            if ([char]::IsWhiteSpace($char)) { continue }
            if ($ignoreGarbage -and $char -ne '=' -and $alphabet.IndexOf($char) -lt 0) { continue }
            [void]$clean.Append($char)
        }

        $bytes = $null
        if ($encoding -eq 'base64') {
            try { $bytes = [System.Convert]::FromBase64String($clean.ToString()) } catch { $bytes = $null }
        }
        else {
            $bytes = ConvertFrom-GnuBase32 -Text $clean.ToString()
        }
        if ($null -eq $bytes) {
            Write-GnuError -Context $Context -Message 'invalid input'
            return
        }
        ConvertTo-GnuOutputLine -Text $script:GnuUtf8.GetString($bytes)
        return
    }

    $data = Get-GnuInputBytes -Context $Context -Operand $operand
    if ($null -eq $data) { return }
    $encoded = ''
    if ($encoding -eq 'base64') { $encoded = [System.Convert]::ToBase64String([byte[]]$data) }
    else { $encoded = ConvertTo-GnuBase32 -Bytes $data }

    if ([string]::IsNullOrEmpty($encoded)) { return }
    if ($wrap -eq 0) {
        $encoded
        return
    }
    for ($i = 0; $i -lt $encoded.Length; $i += $wrap) {
        $encoded.Substring($i, [Math]::Min($wrap, $encoded.Length - $i))
    }
}

function New-GnuBaseEncodingSpec {
    <#
    .SYNOPSIS
    The registry spec shared by base64 and base32.
    #>
    param([Parameter(Mandatory)][ValidateSet('base64', 'base32')][string]$Name)

    @{
        Name         = $Name
        Category     = 'Viewing file contents'
        Synopsis     = "$Name encode/decode data and print to standard output."
        Usage        = @("$Name [OPTION]... [FILE]")
        Description  = @("$Name encode or decode FILE, or standard input, to standard output.", '', 'With no FILE, or when FILE is -, read standard input.')
        FileOperands = $true
        Options      = @(
            @{ Short = 'd'; Long = 'decode'; Help = 'decode data' }
            @{ Short = 'i'; Long = 'ignore-garbage'; Help = 'when decoding, ignore non-alphabet characters' }
            @{ Short = 'w'; Long = 'wrap'; Arg = 'COLS'; Help = 'wrap encoded lines after COLS character (default 76). Use 0 to disable line wrapping' }
        )
        Notes        = @(
            'The data are encoded as described for the ' + $Name + ' alphabet in RFC 4648.',
            'When decoding, the input may contain newlines in addition to the bytes of the',
            'formal alphabet. Use --ignore-garbage to attempt to recover from any other',
            'non-alphabet bytes in the encoded stream.',
            '',
            'PowerShell note: decoded output is written as UTF-8 text lines.'
        )
    }
}
