Register-GnuUtil @{
    Name         = 'printf'
    Category     = 'Shell helpers'
    Synopsis     = 'Format and print data.'
    Usage        = @('printf FORMAT [ARGUMENT]...', 'printf OPTION')
    Description  = @('Print ARGUMENT(s) according to FORMAT, or execute according to OPTION:')
    RawArguments = $true
    Notes        = @(
        'FORMAT controls the output as in C printf.  Interpreted sequences are:',
        '',
        '  \"      double quote',
        '  \\      backslash',
        '  \a      alert (BEL)',
        '  \b      backspace',
        '  \c      produce no further output',
        '  \e      escape',
        '  \f      form feed',
        '  \n      new line',
        '  \r      carriage return',
        '  \t      horizontal tab',
        '  \v      vertical tab',
        '  \NNN    byte with octal value NNN (1 to 3 digits)',
        '  \xHH    byte with hexadecimal value HH (1 to 2 digits)',
        '  \uHHHH  Unicode (ISO/IEC 10646) character with hex value HHHH (4 digits)',
        '  \UHHHHHHHH  Unicode character with hex value HHHHHHHH (8 digits)',
        '  %%      a single %',
        '  %b      ARGUMENT as a string with ''\'' escapes interpreted,',
        '          except that octal escapes are of the form \0 or \0NNN',
        '  %q      ARGUMENT is printed in a format that can be reused as shell input,',
        '          escaping non-printable characters with the proposed POSIX $'''' syntax.',
        '',
        'and all C format specifications ending with one of diouxXfeEgGcs, with',
        'ARGUMENTs converted to proper type first.  Variable widths are handled.',
        '',
        'PowerShell note: %a / %A are not supported; floating point uses [double]. Quote',
        'the FORMAT in PowerShell (''%d\n''), and write a literal % in it as %%.'
    )
}

function Invoke-GnuPrintf {
    <#
    .SYNOPSIS
    GNU printf: format and print data.

    .DESCRIPTION
    Prints the ARGUMENTs according to FORMAT (C printf conversions d i o u x X f F e E g G c s,
    plus %b for escapes and %q for shell quoting). The FORMAT is reused until all ARGUMENTs are
    consumed. Invalid numbers are reported and printed as 0 (exit code 1).
    Enable the GNU name with: Enable-GnuUtil printf

    .EXAMPLE
    Invoke-GnuPrintf '%-10s %5.1f\n' apples 1.25 pears 10

    .EXAMPLE
    Invoke-GnuPrintf '%x\n' 255
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'printf' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            $operands = @($ctx.Operands)
            if ($operands.Count -gt 0 -and $operands[0] -eq '--') { $operands = @($operands | Select-Object -Skip 1) }
            if ($operands.Count -eq 0) { Write-GnuUsageError -Context $ctx -Message 'missing operand' }
            else {
                $format = $operands[0]
                $arguments = @($operands | Select-Object -Skip 1)
                $builder = New-Object System.Text.StringBuilder
                $index = 0
                do {
                    $pass = Format-GnuPrintfText -Context $ctx -Format $format -Arguments $arguments -Index $index
                    [void]$builder.Append($pass.Text)
                    $used = $pass.Index - $index
                    $index = $pass.Index
                } while (-not $pass.Stop -and $used -gt 0 -and $index -lt $arguments.Count)
                if (-not $pass.Stop -and $index -lt $arguments.Count) {
                    Write-GnuWarning -Context $ctx -Message "warning: ignoring excess arguments, starting with '$($arguments[$index])'"
                }
                ConvertTo-GnuOutputLine -Text $builder.ToString()
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}

function Format-GnuPrintfText {
    <#
    .SYNOPSIS
    One pass over FORMAT. Returns @{ Text; Index (next unused argument); Stop (\c or a fatal error) }.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Format,
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Arguments,
        [Parameter(Mandatory)][int]$Index
    )

    $builder = New-Object System.Text.StringBuilder
    $i = 0
    while ($i -lt $Format.Length) {
        $char = $Format[$i]
        if ($char -eq '\') {
            $escape = ConvertFrom-GnuPrintfEscape -Context $Context -Text $Format -Start $i
            if ($escape.Stop) { return @{ Text = $builder.ToString(); Index = $Index; Stop = $true } }
            [void]$builder.Append($escape.Text)
            $i = $escape.Next
            continue
        }
        if ($char -ne '%') {
            [void]$builder.Append($char)
            $i++
            continue
        }

        $directive = [regex]::Match($Format.Substring($i), "^%([-+ #0']*)(\*|\d+)?(?:\.(\*|\d*))?(?:hh|h|ll|l|L|j|z|t)?([a-zA-Z%])?")
        $conversion = $directive.Groups[4].Value
        $i += $directive.Length
        if ($conversion -eq '%' -and $directive.Length -eq 2) { [void]$builder.Append('%'); continue }
        if ([string]::IsNullOrEmpty($conversion) -or 'diouxXfFeEgGcsbq'.IndexOf($conversion, [System.StringComparison]::Ordinal) -lt 0) {
            Write-GnuError -Context $Context -Message "$($directive.Value): invalid conversion specification"
            return @{ Text = $builder.ToString(); Index = $Index; Stop = $true }
        }

        $flags = $directive.Groups[1].Value
        $width = 0
        if ($directive.Groups[2].Success) {
            if ($directive.Groups[2].Value -eq '*') {
                $widthArgument = '0'
                if ($Index -lt $Arguments.Count) { $widthArgument = $Arguments[$Index] }
                $Index++
                $width = [int](ConvertFrom-GnuPrintfInteger -Context $Context -Text $widthArgument)
                if ($width -lt 0) { $flags += '-'; $width = -$width }
            }
            else { $width = [int]$directive.Groups[2].Value }
        }
        $precision = -1
        if ($directive.Groups[3].Success) {
            if ($directive.Groups[3].Value -eq '*') {
                $precisionArgument = '0'
                if ($Index -lt $Arguments.Count) { $precisionArgument = $Arguments[$Index] }
                $Index++
                $precision = [int](ConvertFrom-GnuPrintfInteger -Context $Context -Text $precisionArgument)
            }
            elseif ($directive.Groups[3].Value.Length -gt 0) { $precision = [int]$directive.Groups[3].Value }
            else { $precision = 0 }
        }

        $argument = $null
        if ($Index -lt $Arguments.Count) { $argument = $Arguments[$Index] }
        $Index++
        switch -CaseSensitive ($conversion) {
            'b' {
                $text = ''
                if ($null -ne $argument) {
                    $escaped = ConvertFrom-GnuPrintfEscape -Context $Context -Text $argument -Start 0 -All -OctalZero
                    $text = $escaped.Text
                    if ($escaped.Stop) { return @{ Text = $builder.ToString() + $text; Index = $Index; Stop = $true } }
                }
                [void]$builder.Append((Format-GnuPrintfPad -Text $text -Width $width -Flags $flags))
            }
            'c' {
                $text = [string][char]0
                if (-not [string]::IsNullOrEmpty($argument)) { $text = [string]$argument[0] }
                [void]$builder.Append((Format-GnuPrintfPad -Text $text -Width $width -Flags $flags))
            }
            's' {
                $text = [string]$argument
                if ($precision -ge 0 -and $precision -lt $text.Length) { $text = $text.Substring(0, $precision) }
                [void]$builder.Append((Format-GnuPrintfPad -Text $text -Width $width -Flags $flags))
            }
            'q' { [void]$builder.Append((Format-GnuPrintfPad -Text (ConvertTo-GnuShellQuote -Text ([string]$argument)) -Width $width -Flags $flags)) }
            { 'diouxX'.IndexOf($_, [System.StringComparison]::Ordinal) -ge 0 } {
                $text = '0'
                if ($null -ne $argument) { $text = $argument }
                $value = ConvertFrom-GnuPrintfInteger -Context $Context -Text $text -Unsigned:('ouxX'.IndexOf($conversion, [System.StringComparison]::Ordinal) -ge 0)
                [void]$builder.Append((Format-GnuPrintfInteger -Value $value -Conversion $conversion -Flags $flags -Width $width -Precision $precision))
            }
            default {
                $text = '0'
                if ($null -ne $argument) { $text = $argument }
                $value = ConvertFrom-GnuPrintfFloat -Context $Context -Text $text
                [void]$builder.Append((Format-GnuFloat -Value $value -Conversion $conversion -Precision $precision -Flags $flags.Replace("'", '') -Width $width))
            }
        }
    }
    @{ Text = $builder.ToString(); Index = $Index; Stop = $false }
}

function ConvertFrom-GnuPrintfEscape {
    <#
    .SYNOPSIS
    Interprets the escape at Text[Start] (or, with -All, every escape of Text). Returns @{ Text; Next; Stop }.
    .PARAMETER OctalZero
    %b rules: octal escapes are \0NNN (the 0 is not one of the up to 3 digits).
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][int]$Start,
        [switch]$All,
        [switch]$OctalZero
    )

    $builder = New-Object System.Text.StringBuilder
    $i = $Start
    while ($i -lt $Text.Length) {
        if ($Text[$i] -ne '\') {
            # Only reached with -All: a single escape always starts at a backslash.
            [void]$builder.Append($Text[$i])
            $i++
            continue
        }
        if ($i + 1 -ge $Text.Length) { [void]$builder.Append('\'); $i++; if (-not $All) { break } else { continue } }
        $next = $Text[$i + 1]
        $i += 2
        $simple = @{ '"' = '"'; '\' = '\'; 'a' = [char]7; 'b' = [char]8; 'e' = [char]27; 'f' = [char]12; 'n' = "`n"; 'r' = "`r"; 't' = "`t"; 'v' = [char]11 }
        if ($next -ceq 'c') { return @{ Text = $builder.ToString(); Next = $i; Stop = $true } }
        if ($simple.ContainsKey([string]$next) -and [string]$next -cmatch '^["\\abefnrtv]$') { [void]$builder.Append($simple[[string]$next]) }
        elseif ('01234567'.IndexOf($next) -ge 0) {
            $i--
            if ($OctalZero -and $next -eq '0') { $i++ }
            $digits = ''
            while ($digits.Length -lt 3 -and $i -lt $Text.Length -and '01234567'.IndexOf($Text[$i]) -ge 0) { $digits += $Text[$i]; $i++ }
            $code = 0
            if ($digits.Length -gt 0) { $code = [System.Convert]::ToInt32($digits, 8) -band 255 }
            [void]$builder.Append([char]$code)
        }
        elseif ($next -ceq 'x' -or $next -ceq 'u' -or $next -ceq 'U') {
            $maximum = 8
            if ($next -ceq 'x') { $maximum = 2 } elseif ($next -ceq 'u') { $maximum = 4 }
            $digits = ''
            while ($digits.Length -lt $maximum -and $i -lt $Text.Length -and '0123456789abcdefABCDEF'.IndexOf($Text[$i]) -ge 0) { $digits += $Text[$i]; $i++ }
            if ($digits.Length -eq 0 -or ($next -cne 'x' -and $digits.Length -lt $maximum)) {
                Write-GnuError -Context $Context -Message 'missing hexadecimal number in escape'
                return @{ Text = $builder.ToString(); Next = $i; Stop = $true }
            }
            $code = [System.Convert]::ToInt32($digits, 16)
            if ($next -ceq 'x') { [void]$builder.Append([char]$code) }
            else { [void]$builder.Append([char]::ConvertFromUtf32($code)) }
        }
        else { [void]$builder.Append('\').Append($next) }
        if (-not $All) { break }
    }
    @{ Text = $builder.ToString(); Next = $i; Stop = $false }
}

function ConvertFrom-GnuPrintfInteger {
    <#
    .SYNOPSIS
    Converts a printf argument to an integer (decimal, 0x hex, 0 octal, 'c character code), reporting errors like GNU.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [switch]$Unsigned
    )

    if ($Text.Length -ge 2 -and ($Text[0] -eq "'" -or $Text[0] -eq '"')) { return [System.Numerics.BigInteger][int][char]::ConvertToUtf32($Text, 1) }
    $match = [regex]::Match($Text, '^\s*([+-]?)(0[xX][0-9a-fA-F]+|0[0-7]*|[1-9][0-9]*)')
    if (-not $match.Success) {
        Write-GnuError -Context $Context -Message "'$Text': expected a numeric value"
        return [System.Numerics.BigInteger]::Zero
    }
    $digits = $match.Groups[2].Value
    $value = [System.Numerics.BigInteger]::Zero
    if ($digits -match '^0[xX]') { foreach ($digit in $digits.Substring(2).ToCharArray()) { $value = $value * 16 + [System.Convert]::ToInt32([string]$digit, 16) } }
    elseif ($digits.StartsWith('0', [System.StringComparison]::Ordinal)) { foreach ($digit in $digits.ToCharArray()) { $value = $value * 8 + [int][string]$digit } }
    else { $value = [System.Numerics.BigInteger]::Parse($digits, [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($match.Groups[1].Value -eq '-') { $value = -$value }

    $minimum = [System.Numerics.BigInteger][long]::MinValue
    $maximum = [System.Numerics.BigInteger][long]::MaxValue
    if ($Unsigned) {
        $maximum = [System.Numerics.BigInteger][uint64]::MaxValue
        $minimum = -$maximum
    }
    if ($value -gt $maximum -or $value -lt $minimum) {
        Write-GnuError -Context $Context -Message "'$Text': Numerical result out of range"
        if ($value -gt $maximum -or $Unsigned) { $value = $maximum } else { $value = $minimum }
    }
    elseif ($match.Length -lt $Text.Length) {
        Write-GnuError -Context $Context -Message "'$Text': value not completely converted"
    }
    $value
}

function ConvertFrom-GnuPrintfFloat {
    <#
    .SYNOPSIS
    Converts a printf argument to a [double], reporting errors like GNU.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )

    if ($Text.Length -ge 2 -and ($Text[0] -eq "'" -or $Text[0] -eq '"')) { return [double][char]::ConvertToUtf32($Text, 1) }
    $match = [regex]::Match($Text, '^\s*([+-]?)((?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?|(?i:inf(?:inity)?|nan))')
    if (-not $match.Success) {
        Write-GnuError -Context $Context -Message "'$Text': expected a numeric value"
        return 0.0
    }
    $body = $match.Groups[2].Value.ToLowerInvariant()
    if ($body.StartsWith('inf', [System.StringComparison]::Ordinal)) { $value = [double]::PositiveInfinity }
    elseif ($body -eq 'nan') { $value = [double]::NaN }
    else { $value = [double]::Parse($body, [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($match.Groups[1].Value -eq '-') { $value = -$value }
    if ($match.Length -lt $Text.Length) { Write-GnuError -Context $Context -Message "'$Text': value not completely converted" }
    $value
}

function Format-GnuPrintfInteger {
    <#
    .SYNOPSIS
    Formats an integer like C printf (d i o u x X with flags, width and precision).
    #>
    param(
        [Parameter(Mandatory)][System.Numerics.BigInteger]$Value,
        [Parameter(Mandatory)][string]$Conversion,
        [AllowEmptyString()][string]$Flags = '',
        [int]$Width = 0,
        [int]$Precision = -1
    )

    $sign = ''
    $prefix = ''
    if ($Conversion -eq 'd' -or $Conversion -eq 'i') {
        if ($Value -lt 0) { $sign = '-' } elseif ($Flags.Contains('+')) { $sign = '+' } elseif ($Flags.Contains(' ')) { $sign = ' ' }
        $digits = [System.Numerics.BigInteger]::Abs($Value).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
    else {
        if ($Value -lt 0) { $Value += [System.Numerics.BigInteger]::Pow(2, 64) }
        $base = 10
        if ($Conversion -eq 'o') { $base = 8 } elseif ($Conversion -ceq 'x' -or $Conversion -ceq 'X') { $base = 16 }
        $digits = ConvertTo-GnuRadixString -Value $Value -Base $base
        if ($Conversion -ceq 'X') { $digits = $digits.ToUpperInvariant() }
    }
    if ($Precision -eq 0 -and $Value -eq 0) { $digits = '' }
    if ($Precision -gt $digits.Length) { $digits = $digits.PadLeft($Precision, '0') }
    if ($Flags.Contains('#')) {
        if ($Conversion -eq 'o' -and -not $digits.StartsWith('0', [System.StringComparison]::Ordinal)) { $digits = '0' + $digits }
        elseif ($Conversion -ceq 'x' -and $Value -ne 0) { $prefix = '0x' }
        elseif ($Conversion -ceq 'X' -and $Value -ne 0) { $prefix = '0X' }
    }
    $text = $sign + $prefix + $digits
    if ($text.Length -ge $Width) { return $text }
    if ($Flags.Contains('-')) { return $text.PadRight($Width) }
    if ($Flags.Contains('0') -and $Precision -lt 0) { return $sign + $prefix + $digits.PadLeft($Width - $sign.Length - $prefix.Length, '0') }
    $text.PadLeft($Width)
}

function ConvertTo-GnuRadixString {
    <#
    .SYNOPSIS
    A non-negative BigInteger in base 8, 10 or 16 (lower case, no leading zeros).
    #>
    param([Parameter(Mandatory)][System.Numerics.BigInteger]$Value, [Parameter(Mandatory)][int]$Base)

    if ($Value -eq 0) { return '0' }
    $builder = New-Object System.Text.StringBuilder
    while ($Value -gt 0) {
        [void]$builder.Insert(0, '0123456789abcdef'[[int]($Value % $Base)])
        $Value = [System.Numerics.BigInteger]::Divide($Value, $Base)
    }
    $builder.ToString()
}

function Format-GnuPrintfPad {
    <#
    .SYNOPSIS
    Pads a string conversion to Width (left aligned with the '-' flag).
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [int]$Width = 0, [AllowEmptyString()][string]$Flags = '')
    if ($Text.Length -ge $Width) { return $Text }
    if ($Flags.Contains('-')) { return $Text.PadRight($Width) }
    $Text.PadLeft($Width)
}

function ConvertTo-GnuShellQuote {
    <#
    .SYNOPSIS
    Quotes a string for reuse as shell input, like GNU's shell-escape quoting (printf %q, ls -Q style).
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    if ($Text.Length -eq 0) { return "''" }
    $special = '\s!"$&''()*;<>?\[\\\]`{|}'
    if ($Text -cmatch "^[^~#$special][^$special]*`$" -and $Text -cnotmatch '[\x00-\x1f\x7f]') { return $Text }
    if ($Text -cnotmatch '[\x00-\x1f\x7f]') {
        if ($Text.Contains("'") -and $Text -cnotmatch '[$`\\"!]') { return '"' + $Text + '"' }
        return "'" + $Text.Replace("'", "'\''") + "'"
    }
    # Control characters: printable runs in single quotes, control characters as $'\t'.
    $names = @{ 7 = 'a'; 8 = 'b'; 9 = 't'; 10 = 'n'; 11 = 'v'; 12 = 'f'; 13 = 'r' }
    $builder = New-Object System.Text.StringBuilder
    foreach ($run in [regex]::Matches($Text, '[\x00-\x1f\x7f]+|[^\x00-\x1f\x7f]+')) {
        if ($run.Value -cmatch '^[\x00-\x1f\x7f]') {
            [void]$builder.Append("`$'")
            foreach ($char in $run.Value.ToCharArray()) {
                if ($names.ContainsKey([int]$char)) { [void]$builder.Append('\' + $names[[int]$char]) }
                else { [void]$builder.Append('\' + [System.Convert]::ToString([int]$char, 8).PadLeft(3, '0')) }
            }
            [void]$builder.Append("'")
        }
        else { [void]$builder.Append("'" + $run.Value.Replace("'", "'\''") + "'") }
    }
    $builder.ToString()
}
