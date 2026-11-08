Register-GnuUtil @{
    Name         = 'od'
    Category     = 'Viewing file contents'
    Synopsis     = 'Dump files in octal and other formats.'
    Usage        = @('od [OPTION]... [FILE]...')
    Description  = @(
        'Write an unambiguous representation, octal bytes by default,',
        'of FILE to standard output.  With more than one FILE argument,',
        'concatenate them in the listed order to form the input.',
        '',
        'With no FILE, or when FILE is -, read standard input.'
    )
    FileOperands = $true
    Options      = @(
        @{ Short = 'A'; Long = 'address-radix'; Arg = 'RADIX'; Help = 'output format for file offsets; RADIX is one of [doxn], for Decimal, Octal, Hex or None' }
        @{ Long = 'endian'; Arg = '{big|little}'; Help = 'swap input bytes according the specified order' }
        @{ Short = 'j'; Long = 'skip-bytes'; Arg = 'BYTES'; Help = 'skip BYTES input bytes first' }
        @{ Short = 'N'; Long = 'read-bytes'; Arg = 'BYTES'; Help = 'limit dump to BYTES input bytes' }
        @{ Short = 't'; Long = 'format'; Key = 'format'; Arg = 'TYPE'; Multi = $true; Help = 'select output format or formats' }
        @{ Short = 'v'; Long = 'output-duplicates'; Help = 'do not use * to mark line suppression' }
        @{ Short = 'w'; Long = 'width'; Arg = 'BYTES'; OptionalArg = $true; Help = 'output BYTES bytes per output line; 32 is implied when BYTES is not specified' }
        @{ Short = 'a'; Key = 'format'; Value = 'a'; Multi = $true; Help = 'same as -t a,  select named characters, ignoring high-order bit' }
        @{ Short = 'b'; Key = 'format'; Value = 'o1'; Multi = $true; Help = 'same as -t o1, select octal bytes' }
        @{ Short = 'c'; Key = 'format'; Value = 'c'; Multi = $true; Help = 'same as -t c,  select printable characters or backslash escapes' }
        @{ Short = 'd'; Key = 'format'; Value = 'u2'; Multi = $true; Help = 'same as -t u2, select unsigned decimal 2-byte units' }
        @{ Short = 'f'; Key = 'format'; Value = 'fF'; Multi = $true; Help = 'same as -t fF, select floats' }
        @{ Short = 'i'; Key = 'format'; Value = 'dI'; Multi = $true; Help = 'same as -t dI, select decimal ints' }
        @{ Short = 'l'; Key = 'format'; Value = 'dL'; Multi = $true; Help = 'same as -t dL, select decimal longs' }
        @{ Short = 'o'; Key = 'format'; Value = 'o2'; Multi = $true; Help = 'same as -t o2, select octal 2-byte units' }
        @{ Short = 's'; Key = 'format'; Value = 'd2'; Multi = $true; Help = 'same as -t d2, select decimal 2-byte units' }
        @{ Short = 'x'; Key = 'format'; Value = 'x2'; Multi = $true; Help = 'same as -t x2, select hexadecimal 2-byte units' }
    )
    Notes        = @(
        'TYPE is made up of one or more of these specifications:',
        '  a          named character, ignoring high-order bit',
        '  c          printable character or backslash escape',
        '  d[SIZE]    signed decimal, SIZE bytes per integer',
        '  f[SIZE]    floating point, SIZE bytes per float',
        '  o[SIZE]    octal, SIZE bytes per integer',
        '  u[SIZE]    unsigned decimal, SIZE bytes per integer',
        '  x[SIZE]    hexadecimal, SIZE bytes per integer',
        '',
        'SIZE is a number.  For TYPE in [doux], SIZE may also be C for',
        'sizeof(char), S for sizeof(short), I for sizeof(int) or L for',
        'sizeof(long).  If TYPE is f, SIZE may also be F for sizeof(float), D',
        'for sizeof(double) or L for sizeof(long double).',
        '',
        'Adding a z suffix to any type displays printable characters at the end',
        'of each output line.',
        '',
        'BYTES is hex with 0x or 0X prefix, and may have a multiplier suffix:',
        '  b    512',
        '  KB   1000',
        '  K    1024',
        '  MB   1000*1000',
        '  M    1024*1024',
        'and so on for G, T, P, E, Z, Y, R, Q.',
        'Binary prefixes can be used, too: KiB=K, MiB=M, and so on.',
        '',
        'PowerShell note: long double (fL) is printed as double; -S (strings) and',
        '--traditional are not supported (use the strings program or Select-String).'
    )
}

$script:GnuOdNames = @('nul', 'soh', 'stx', 'etx', 'eot', 'enq', 'ack', 'bel', 'bs', 'ht', 'nl', 'vt', 'ff', 'cr', 'so', 'si',
    'dle', 'dc1', 'dc2', 'dc3', 'dc4', 'nak', 'syn', 'etb', 'can', 'em', 'sub', 'esc', 'fs', 'gs', 'rs', 'us', 'sp')

# Printed width of one value: integer widths by kind and size, floats by size.
$script:GnuOdWidths = @{
    d1 = 4; o1 = 3; u1 = 3; x1 = 2; d2 = 6; o2 = 6; u2 = 5; x2 = 4
    d4 = 11; o4 = 11; u4 = 10; x4 = 8; d8 = 20; o8 = 22; u8 = 20; x8 = 16
    f4 = 15; f8 = 24; a1 = 3; c1 = 3
}

function Invoke-GnuOd {
    <#
    .SYNOPSIS
    GNU od: dump files in octal, hexadecimal, decimal, floating point or character formats.

    .DESCRIPTION
    Prints the input (FILEs concatenated, or the pipeline) as 2-byte octal words by default, or
    in the formats of -t TYPE (a c d o u x f with sizes and the z suffix) and the traditional
    options -a -b -c -d -f -i -l -o -s -x. -A sets the address radix, -j and -N select a
    range, -w the bytes per line; repeated lines are shown as * unless -v.
    Enable the GNU name with: Enable-GnuUtil od

    .EXAMPLE
    Invoke-GnuOd -A x -t x1z setup.bin
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'od' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuOdDump -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function ConvertFrom-GnuOdType {
    <#
    .SYNOPSIS
    Parses a -t TYPE string into specs @{ Kind; Size; Width; Trailer }. Returns @{ Specs } or @{ Error }.
    #>
    param([Parameter(Mandatory)][string]$Text)

    $specs = New-Object 'System.Collections.Generic.List[hashtable]'
    $i = 0
    while ($i -lt $Text.Length) {
        $kind = [string]$Text[$i]
        $i++
        $size = 1
        if ('doux'.Contains($kind)) {
            $size = 4
            if ($i -lt $Text.Length -and 'CSIL'.Contains([string]$Text[$i])) {
                $size = @{ C = 1; S = 2; I = 4; L = 8 }[[string]$Text[$i]]
                $i++
            }
            elseif ($i -lt $Text.Length -and [char]::IsDigit($Text[$i])) {
                $digits = [regex]::Match($Text.Substring($i), '^\d+').Value
                $i += $digits.Length
                $size = [int]$digits
                if (@(1, 2, 4, 8) -notcontains $size) { return @{ Error = "invalid type string '$Text';`nthis system doesn't provide a $size-byte integral type" } }
            }
        }
        elseif ($kind -ceq 'f') {
            $size = 8
            if ($i -lt $Text.Length -and 'FDL'.Contains([string]$Text[$i])) {
                if ($Text[$i] -ceq 'F') { $size = 4 }
                $i++
            }
            elseif ($i -lt $Text.Length -and [char]::IsDigit($Text[$i])) {
                $digits = [regex]::Match($Text.Substring($i), '^\d+').Value
                $i += $digits.Length
                $size = [int]$digits
                if (@(4, 8) -notcontains $size) { return @{ Error = "invalid type string '$Text';`nthis system doesn't provide a $size-byte floating point type" } }
            }
        }
        elseif ($kind -cne 'a' -and $kind -cne 'c') {
            return @{ Error = "invalid character '$kind' in type string '$Text'" }
        }
        $trailer = $false
        if ($i -lt $Text.Length -and $Text[$i] -ceq 'z') { $trailer = $true; $i++ }
        $specs.Add(@{ Kind = $kind; Size = $size; Width = $script:GnuOdWidths["$kind$size"]; Trailer = $trailer })
    }
    @{ Specs = $specs }
}

function ConvertFrom-GnuOdCount {
    <#
    .SYNOPSIS
    A byte count for -j / -N (decimal, 0x hex, leading-0 octal, size suffixes), or $null.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    if ($Text -match '^0[xX]([0-9a-fA-F]+)$') { return [System.Convert]::ToInt64($Matches[1], 16) }
    if ($Text -match '^0([0-7]+)$') { return [System.Convert]::ToInt64($Matches[1], 8) }
    $value = ConvertFrom-GnuSize -Text $Text
    if ($null -eq $value) { return $null }
    ConvertTo-GnuInt64 -Value $value
}

function Format-GnuOdFloat {
    <#
    .SYNOPSIS
    The shortest %g text that reads back as the same float or double (like coreutils' ftoastr).
    #>
    param([Parameter(Mandatory)][double]$Value, [Parameter(Mandatory)][int]$Size)

    if ([double]::IsNaN($Value)) { return 'nan' }
    if ([double]::IsPositiveInfinity($Value)) { return 'inf' }
    if ([double]::IsNegativeInfinity($Value)) { return '-inf' }
    if ($Value -eq 0) {
        if ((1 / $Value) -lt 0) { return '-0' }
        return '0'
    }
    $digits = 15
    $smallest = 2.2250738585072014E-308
    if ($Size -eq 4) { $digits = 6; $smallest = 1.17549435E-38 }
    if ([Math]::Abs($Value) -lt $smallest) { $digits = 1 }
    # 'G<p>' gives up to 17 significant digits on every runtime (.NET Framework's 'F' and 'E' stop at 15);
    # 17 digits always read back exactly.
    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    for ($precision = $digits; $precision -lt 17; $precision++) {
        $text = $Value.ToString('G' + $precision, $invariant)
        $back = [double]::Parse($text, $invariant)
        if ($Size -eq 4) {
            if ([float]$back -eq [float]$Value) { return ConvertTo-GnuCStyleG -Text $text -Precision $precision }
        }
        elseif ($back -eq $Value) { return ConvertTo-GnuCStyleG -Text $text -Precision $precision }
    }
    ConvertTo-GnuCStyleG -Text $Value.ToString('G17', $invariant) -Precision 17
}

function ConvertTo-GnuCStyleG {
    <#
    .SYNOPSIS
    Re-lays a .NET 'G<p>' number text out like C's %.<p>g (exponent form when exp < -4 or exp >= p).
    #>
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][int]$Precision)

    $sign = ''
    if ($Text.StartsWith('-', [System.StringComparison]::Ordinal)) { $sign = '-'; $Text = $Text.Substring(1) }
    $exponent = 0
    $mantissa = $Text
    $at = $Text.IndexOf('E')
    if ($at -ge 0) { $mantissa = $Text.Substring(0, $at); $exponent = [int]$Text.Substring($at + 1) }
    $point = $mantissa.IndexOf('.')
    if ($point -lt 0) { $point = $mantissa.Length }
    $digits = $mantissa.Replace('.', '')
    $zeros = $digits.Length - $digits.TrimStart('0').Length
    $digits = $digits.Substring($zeros).TrimEnd('0')
    $scientific = $exponent + $point - 1 - $zeros
    if ($scientific -lt -4 -or $scientific -ge $Precision) {
        $text = $digits.Substring(0, 1)
        if ($digits.Length -gt 1) { $text += '.' + $digits.Substring(1) }
        $mark = '+'
        if ($scientific -lt 0) { $mark = '-' }
        return "$sign$($text)e$mark$([Math]::Abs($scientific).ToString('00'))"
    }
    if ($scientific -lt 0) { return "$($sign)0." + ('0' * (-$scientific - 1)) + $digits }
    if ($digits.Length -le $scientific + 1) { return $sign + $digits.PadRight($scientific + 1, '0') }
    $sign + $digits.Substring(0, $scientific + 1) + '.' + $digits.Substring($scientific + 1)
}

function Format-GnuOdValue {
    <#
    .SYNOPSIS
    One value of an od line (Bytes holds Size bytes in the requested byte order).
    #>
    param([Parameter(Mandatory)][hashtable]$Spec, [Parameter(Mandatory)][byte[]]$Bytes, [Parameter(Mandatory)][bool]$BigEndian)

    $byte = $Bytes[0]
    switch -CaseSensitive ($Spec.Kind) {
        'a' {
            $code = $byte -band 127
            if ($code -lt 33) { return $script:GnuOdNames[$code] }
            if ($code -eq 127) { return 'del' }
            return [string][char]$code
        }
        'c' {
            $escapes = @{ 0 = '\0'; 7 = '\a'; 8 = '\b'; 9 = '\t'; 10 = '\n'; 11 = '\v'; 12 = '\f'; 13 = '\r' }
            if ($escapes.ContainsKey([int]$byte)) { return $escapes[[int]$byte] }
            if ($byte -ge 32 -and $byte -lt 127) { return [string][char]$byte }
            return [System.Convert]::ToString([int]$byte, 8).PadLeft(3, '0')
        }
    }
    $ordered = [byte[]]$Bytes.Clone()
    if ($BigEndian -eq [System.BitConverter]::IsLittleEndian) { [array]::Reverse($ordered) }
    if ($Spec.Kind -ceq 'f') {
        if ($Spec.Size -eq 4) { return Format-GnuOdFloat -Value ([double][System.BitConverter]::ToSingle($ordered, 0)) -Size 4 }
        return Format-GnuOdFloat -Value ([System.BitConverter]::ToDouble($ordered, 0)) -Size 8
    }
    $unsigned = [uint64]0
    switch ($Spec.Size) {
        1 { $unsigned = [uint64]$ordered[0] }
        2 { $unsigned = [uint64][System.BitConverter]::ToUInt16($ordered, 0) }
        4 { $unsigned = [uint64][System.BitConverter]::ToUInt32($ordered, 0) }
        default { $unsigned = [System.BitConverter]::ToUInt64($ordered, 0) }
    }
    switch -CaseSensitive ($Spec.Kind) {
        'd' {
            $signed = [System.Numerics.BigInteger]$unsigned
            $limit = [System.Numerics.BigInteger]::Pow(2, 8 * $Spec.Size)
            if ($signed -ge $limit / 2) { $signed -= $limit }
            return $signed.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        }
        'u' { return $unsigned.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
        'x' { return $unsigned.ToString('x' + (2 * $Spec.Size)) }
    }
    ConvertTo-GnuRadixString -Value ([System.Numerics.BigInteger]$unsigned) -Base 8 | ForEach-Object { $_.PadLeft($Spec.Width, '0') }
}

function Invoke-GnuOdDump {
    <#
    .SYNOPSIS
    Implementation of od.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $radix = [string](Get-GnuOptionValue -Context $Context -Key 'address-radix' -Default 'o')
    if ($radix.Length -ne 1 -or 'doxn'.IndexOf($radix, [System.StringComparison]::Ordinal) -lt 0) {
        Write-GnuError -Context $Context -Message "invalid output address radix '$radix'; it must be one character from [doxn]"
        return
    }
    $bigEndian = -not [System.BitConverter]::IsLittleEndian
    if (Test-GnuOption -Context $Context -Key 'endian') {
        $endian = [string](Get-GnuOptionValue -Context $Context -Key 'endian')
        if (@('big', 'little') -notcontains $endian) { Write-GnuUsageError -Context $Context -Message "invalid argument '$endian' for '--endian'`nValid arguments are:`n  - 'big'`n  - 'little'"; return }
        $bigEndian = $endian -eq 'big'
    }

    $specs = New-Object 'System.Collections.Generic.List[hashtable]'
    foreach ($type in @(Get-GnuOptionValue -Context $Context -Key 'format' -Default @('o2'))) {
        $parsed = ConvertFrom-GnuOdType -Text $type
        if ($parsed.ContainsKey('Error')) { Write-GnuError -Context $Context -Message $parsed.Error; return }
        foreach ($spec in $parsed.Specs) { $specs.Add($spec) }
    }

    $skip = [long]0
    $limit = [long]-1
    foreach ($entry in @(@('skip-bytes', 'skip'), @('read-bytes', 'limit'))) {
        if (-not (Test-GnuOption -Context $Context -Key $entry[0])) { continue }
        $text = [string](Get-GnuOptionValue -Context $Context -Key $entry[0])
        $value = ConvertFrom-GnuOdCount -Text $text
        if ($null -eq $value) { Write-GnuError -Context $Context -Message "invalid $($entry[0].Replace('-', ' ')) argument '$text'"; return }
        if ($entry[1] -eq 'skip') { $skip = $value } else { $limit = $value }
    }

    $lcm = 1
    foreach ($spec in $specs) {
        $a = $lcm; $b = $spec.Size
        while ($b -ne 0) { $t = $a % $b; $a = $b; $b = $t }
        $lcm = $lcm / $a * $spec.Size
    }
    $width = 16   # a multiple of every size (1, 2, 4, 8)
    if (Test-GnuOption -Context $Context -Key 'width') {
        $text = [string](Get-GnuOptionValue -Context $Context -Key 'width')
        $width = 32
        if (-not [string]::IsNullOrEmpty($text)) {
            if ($text -notmatch '^\d+$' -or [int]$text -eq 0) { Write-GnuError -Context $Context -Message "invalid -w argument '$text'"; return }
            $width = [int]$text
        }
        if ($width % $lcm -ne 0) {
            Write-GnuWarning -Context $Context -Message "warning: invalid width $width; using $lcm instead"
            $width = $lcm
        }
    }

    # Read the input: the files concatenated (stopping once enough bytes are read).
    $operands = @($Context.Operands)
    if ($operands.Count -eq 0) { $operands = @('-') }
    $data = New-Object 'System.Collections.Generic.List[byte]'
    foreach ($operand in $operands) {
        if ($limit -ge 0 -and $data.Count -ge $skip + $limit) { break }
        $bytes = Get-GnuInputBytes -Context $Context -Operand $operand
        if ($null -ne $bytes) { $data.AddRange([byte[]]$bytes) }
    }
    if ($skip -gt $data.Count) { Write-GnuError -Context $Context -Message 'cannot skip past end of combined input'; return }
    $count = $data.Count - $skip
    if ($limit -ge 0 -and $limit -lt $count) { $count = $limit }
    $dump = New-Object byte[] $count
    if ($count -gt 0) { $data.CopyTo([int]$skip, $dump, 0, [int]$count) }

    # Column layout (GNU: every format gets the same width per line, extra padding is spread over the fields).
    $maxWidth = 0
    foreach ($spec in $specs) { $maxWidth = [Math]::Max($maxWidth, ($spec.Width + 1) * ($width / $spec.Size)) }
    foreach ($spec in $specs) { $spec.Pad = $maxWidth - $spec.Width * ($width / $spec.Size) }
    $addressWidth = @{ o = 7; d = 7; x = 6; n = 0 }[$radix]

    $previous = $null
    $starred = $false
    for ($offset = 0; $offset -lt $dump.Length; $offset += $width) {
        $length = [Math]::Min($width, $dump.Length - $offset)
        $line = New-Object byte[] $width
        [array]::Copy($dump, $offset, $line, 0, $length)
        if ($length -eq $width -and -not (Test-GnuOption -Context $Context -Key 'output-duplicates') -and $null -ne $previous -and
            [System.Linq.Enumerable]::SequenceEqual([byte[]]$line, [byte[]]$previous)) {
            if (-not $starred) { '*'; $starred = $true }
            continue
        }
        $starred = $false
        $previous = $line
        $first = $true
        foreach ($spec in $specs) {
            $builder = New-Object System.Text.StringBuilder
            if ($first) { [void]$builder.Append((Format-GnuOdAddress -Offset ($skip + $offset) -Radix $radix)) }
            else { [void]$builder.Append(' ' * $addressWidth) }
            $first = $false
            $fields = $width / $spec.Size
            $used = [int][Math]::Ceiling($length / $spec.Size)
            $remaining = $spec.Pad
            for ($i = $fields; $i -gt $fields - $used; $i--) {
                $nextPad = [int][Math]::Floor($spec.Pad * ($i - 1) / $fields)
                $index = ($fields - $i) * $spec.Size
                $chunk = New-Object byte[] $spec.Size
                [array]::Copy($line, $index, $chunk, 0, $spec.Size)
                $value = Format-GnuOdValue -Spec $spec -Bytes $chunk -BigEndian $bigEndian
                [void]$builder.Append($value.PadLeft($remaining - $nextPad + $spec.Width))
                $remaining = $nextPad
            }
            if ($spec.Trailer) {
                $blank = $fields - $used
                [void]$builder.Append(' ' * ($blank * $spec.Width + [int][Math]::Floor($spec.Pad * $blank / $fields)))
                [void]$builder.Append('  >')
                for ($k = 0; $k -lt $length; $k++) {
                    $byte = $line[$k]
                    if ($byte -ge 32 -and $byte -lt 127) { [void]$builder.Append([char]$byte) } else { [void]$builder.Append('.') }
                }
                [void]$builder.Append('<')
            }
            $builder.ToString()
        }
    }
    if ($radix -ne 'n') { Format-GnuOdAddress -Offset ($skip + $dump.Length) -Radix $radix }
}

function Format-GnuOdAddress {
    <#
    .SYNOPSIS
    An od address: 7 octal or decimal digits, 6 hex digits, or nothing.
    #>
    param([Parameter(Mandatory)][long]$Offset, [Parameter(Mandatory)][string]$Radix)
    switch ($Radix) {
        'o' { return [System.Convert]::ToString($Offset, 8).PadLeft(7, '0') }
        'd' { return ([string]$Offset).PadLeft(7, '0') }
        'x' { return $Offset.ToString('x6') }
    }
    ''
}
