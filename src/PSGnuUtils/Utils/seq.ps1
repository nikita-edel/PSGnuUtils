Register-GnuUtil @{
    Name                   = 'seq'
    Category               = 'Shell helpers'
    Synopsis               = 'Print a sequence of numbers.'
    Usage                  = @('seq [OPTION]... LAST', 'seq [OPTION]... FIRST LAST', 'seq [OPTION]... FIRST INCREMENT LAST')
    Description            = @('Print numbers from FIRST to LAST, in steps of INCREMENT.')
    NegativeNumberOperands = $true
    Options                = @(
        @{ Short = 'f'; Long = 'format'; Arg = 'FORMAT'; Help = 'use printf style floating-point FORMAT' }
        @{ Short = 's'; Long = 'separator'; Arg = 'STRING'; Help = 'use STRING to separate numbers (default: \n)' }
        @{ Short = 'w'; Long = 'equal-width'; Help = 'equalize width by padding with leading zeroes' }
    )
    Notes                  = @(
        'If FIRST or INCREMENT is omitted, it defaults to 1.  That is, an',
        'omitted INCREMENT defaults to 1 even when LAST is smaller than FIRST.',
        'The sequence of numbers ends when the sum of the current number and',
        'INCREMENT would become greater than LAST.',
        'FIRST, INCREMENT, and LAST are interpreted as floating point values.',
        'INCREMENT is usually positive if FIRST is smaller than LAST, and',
        'INCREMENT is usually negative if FIRST is greater than LAST.',
        'INCREMENT must not be 0; none of FIRST, INCREMENT and LAST may be NaN.',
        'FORMAT must be suitable for printing one argument of type ''double'';',
        'it defaults to %.PRECf if FIRST, INCREMENT, and LAST are all fixed point',
        'decimal numbers with maximum precision PREC, and to %g otherwise.',
        '',
        'PowerShell note: inf and hexadecimal numbers are not supported yet.'
    )
}

function Invoke-GnuSeq {
    <#
    .SYNOPSIS
    GNU seq: print a sequence of numbers.

    .DESCRIPTION
    Prints FIRST (default 1) to LAST in steps of INCREMENT (default 1). Decimal arithmetic is
    used, so 'seq 0 0.1 1' has no rounding drift. -w pads with zeros, -s joins with a
    separator, -f formats with a printf floating point directive (%f %e %g).
    Enable the GNU name with: Enable-GnuUtil seq

    .EXAMPLE
    Invoke-GnuSeq 3

    1
    2
    3

    .EXAMPLE
    Invoke-GnuSeq -w -s ',' 8 2 12

    08,10,12
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'seq' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) { Invoke-GnuSequence -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function ConvertFrom-GnuSeqFormat {
    <#
    .SYNOPSIS
    Parses a seq FORMAT into prefix, directive and suffix. Returns @{ Error } on invalid formats.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Format)

    $pattern = '^(?<pre>(?:[^%]|%%)*)%(?<flags>[-+ #0'']*)(?<width>\d*)(?:\.(?<precision>\d*))?(?<conversion>[a-zA-Z]?)(?<post>.*)$'
    if ($Format -notmatch $pattern) { return @{ Error = "format '$Format' has no % directive" } }
    $parsed = @{
        Prefix     = $Matches['pre'].Replace('%%', '%')
        Flags      = $Matches['flags'].Replace("'", '')
        Width      = 0
        Precision  = -1
        Conversion = $Matches['conversion']
        Suffix     = $Matches['post']
        Error      = $null
    }
    if ($Matches['width']) { $parsed.Width = [int]$Matches['width'] }
    if ($Matches.ContainsKey('precision')) {
        $parsed.Precision = 0
        if ($Matches['precision']) { $parsed.Precision = [int]$Matches['precision'] }
    }
    if ($parsed.Conversion -cnotmatch '^[eEfFgG]$') {
        $directive = '%' + $Matches['flags'] + $Matches['width'] + $parsed.Conversion
        return @{ Error = "format '$Format' has unknown $directive directive" }
    }
    if ($parsed.Suffix -match '%(?!%)') { return @{ Error = "format '$Format' has too many % directives" } }
    $parsed.Suffix = $parsed.Suffix.Replace('%%', '%')
    $parsed
}

function Invoke-GnuSequence {
    <#
    .SYNOPSIS
    Implementation of seq.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $operands = @($Context.Operands)
    if ($operands.Count -eq 0) { Write-GnuUsageError -Context $Context -Message 'missing operand'; return }
    if ($operands.Count -gt 3) { Write-GnuUsageError -Context $Context -Message "extra operand '$($operands[3])'"; return }

    $numbers = @()
    foreach ($operand in $operands) {
        $value = [decimal]0
        $styles = [System.Globalization.NumberStyles]::Float
        if (-not [decimal]::TryParse($operand, $styles, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$value)) {
            Write-GnuUsageError -Context $Context -Message "invalid floating point argument: '$operand'"
            return
        }
        $numbers += $value
    }

    $first = [decimal]1
    $step = [decimal]1
    $last = $numbers[$numbers.Count - 1]
    if ($numbers.Count -ge 2) { $first = $numbers[0] }
    if ($numbers.Count -eq 3) { $step = $numbers[1] }
    if ($step -eq 0) {
        Write-GnuUsageError -Context $Context -Message "invalid Zero increment value: '$($operands[1])'"
        return
    }

    $format = $null
    if (Test-GnuOption -Context $Context -Key 'format') {
        if (Test-GnuOption -Context $Context -Key 'equal-width') {
            Write-GnuUsageError -Context $Context -Message 'format string may not be specified when printing equal width strings'
            return
        }
        $format = ConvertFrom-GnuSeqFormat -Format ([string](Get-GnuOptionValue -Context $Context -Key 'format'))
        if ($format.Error) { Write-GnuError -Context $Context -Message $format.Error; return }
    }

    $precision = [Math]::Max((Get-GnuDecimalScale -Value $first), (Get-GnuDecimalScale -Value $step))
    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $width = 0
    if (Test-GnuOption -Context $Context -Key 'equal-width') {
        # Width includes the sign, like GNU: seq -w -1 1 prints -1 00 01.
        $width = [Math]::Max($first.ToString('F' + $precision, $invariant).Length, $last.ToString('F' + $precision, $invariant).Length)
    }

    $values = New-Object 'System.Collections.Generic.List[string]'
    for ($i = [decimal]0; ; $i++) {
        $current = $first + $i * $step
        if (($step -gt 0 -and $current -gt $last) -or ($step -lt 0 -and $current -lt $last)) { break }
        if ($null -ne $format) {
            $values.Add($format.Prefix + (Format-GnuFloat -Value ([double]$current) -Conversion $format.Conversion -Precision $format.Precision -Flags $format.Flags -Width $format.Width) + $format.Suffix)
        }
        else {
            $text = [Math]::Abs($current).ToString('F' + $precision, $invariant)
            if ($current -lt 0) {
                if ($width -gt 0) { $text = $text.PadLeft($width - 1, '0') }
                $text = '-' + $text
            }
            elseif ($width -gt 0) {
                $text = $text.PadLeft($width, '0')
            }
            $values.Add($text)
        }
    }

    $separator = "`n"
    if (Test-GnuOption -Context $Context -Key 'separator') { $separator = [string](Get-GnuOptionValue -Context $Context -Key 'separator') }
    if ($values.Count -eq 0) { return }
    if ($separator -eq "`n") {
        $values
        return
    }
    ConvertTo-GnuOutputLine -Text (($values -join $separator) + "`n")
}
