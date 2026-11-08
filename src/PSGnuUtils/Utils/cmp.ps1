Register-GnuUtil @{
    Name          = 'cmp'
    Category      = 'Searching and comparing'
    Synopsis      = 'Compare two files byte by byte.'
    Usage         = @('cmp [OPTION]... FILE1 [FILE2 [SKIP1 [SKIP2]]]')
    Description   = @(
        'Compare two files byte by byte.',
        '',
        'The optional SKIP1 and SKIP2 specify the number of bytes to skip',
        'at the beginning of each file (zero by default).'
    )
    FileOperands  = $true
    UsageExitCode = 2
    UsageHintHasName = $true
    Options       = @(
        @{ Short = 'b'; Long = 'print-bytes'; Help = 'print differing bytes' }
        @{ Short = 'i'; Long = 'ignore-initial'; Arg = 'SKIP'; Help = 'skip first SKIP bytes of both inputs; or SKIP1:SKIP2 for each input' }
        @{ Short = 'l'; Long = 'verbose'; Help = 'output byte numbers and differing byte values' }
        @{ Short = 'n'; Long = 'bytes'; Arg = 'LIMIT'; Help = 'compare at most LIMIT bytes' }
        @{ Short = 's'; Long = 'quiet'; Key = 'quiet'; Help = 'suppress all normal output' }
        @{ Long = 'silent'; Key = 'quiet'; Help = 'suppress all normal output' }
    )
    Notes         = @(
        'SKIP values may be followed by the following multiplicative suffixes:',
        'kB 1000, K 1024, MB 1,000,000, M 1,048,576,',
        'GB 1,000,000,000, G 1,073,741,824, and so on for T, P, E, Z, Y.',
        '',
        'If a FILE is ''-'' or missing, read standard input.',
        'Exit status is 0 if inputs are the same, 1 if different, 2 if trouble.'
    )
}

function Invoke-GnuCmp {
    <#
    .SYNOPSIS
    GNU cmp: compare two files byte by byte.

    .DESCRIPTION
    Reports the first differing byte and line ("a b differ: char 15, line 2"), every
    difference with -l, the differing bytes with -b, or nothing with -s. The exit code is 0
    for identical inputs, 1 if they differ, 2 on trouble.
    Enable the GNU name with: Enable-GnuAlias cmp

    .EXAMPLE
    Invoke-GnuCmp -s old.bin new.bin; if ($LASTEXITCODE -eq 0) { 'same' }
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'cmp' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuCmpCompare -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function ConvertTo-GnuCmpCharacter {
    <#
    .SYNOPSIS
    A byte as cat -v shows it (^A, M-x, M-^?).
    #>
    param([Parameter(Mandatory)][int]$Byte)
    $prefix = ''
    if ($Byte -ge 128) { $prefix = 'M-'; $Byte -= 128 }
    if ($Byte -lt 32) { return "$prefix^$([char]($Byte + 64))" }
    if ($Byte -eq 127) { return "$prefix^?" }
    "$prefix$([char]$Byte)"
}

function ConvertFrom-GnuCmpSkip {
    <#
    .SYNOPSIS
    A SKIP or LIMIT value (decimal, 0x hex, size suffixes), or $null if invalid.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    if ($Text -match '^0[xX]([0-9a-fA-F]+)$') { return [System.Convert]::ToInt64($Matches[1], 16) }
    $value = ConvertFrom-GnuSize -Text $Text
    if ($null -eq $value) { return $null }
    ConvertTo-GnuInt64 -Value $value
}

function Invoke-GnuCmpCompare {
    <#
    .SYNOPSIS
    Implementation of cmp.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $verbose = Test-GnuOption -Context $Context -Key 'verbose'
    $quiet = Test-GnuOption -Context $Context -Key 'quiet'
    $printBytes = Test-GnuOption -Context $Context -Key 'print-bytes'
    if ($verbose -and $quiet) { Write-GnuUsageError -Context $Context -Message 'options -l and -s are incompatible'; return }
    $operands = @($Context.Operands)
    if ($operands.Count -eq 0) { Write-GnuUsageError -Context $Context -Message "missing operand after 'cmp'"; return }

    $skips = @([long]0, [long]0)
    if (Test-GnuOption -Context $Context -Key 'ignore-initial') {
        $text = [string](Get-GnuOptionValue -Context $Context -Key 'ignore-initial')
        $parts = @($text.Split(':'))
        if ($parts.Count -gt 2) { $parts = @('') }
        for ($k = 0; $k -lt 2; $k++) {
            $value = ConvertFrom-GnuCmpSkip -Text $parts[[Math]::Min($k, $parts.Count - 1)]
            if ($null -eq $value) { Write-GnuUsageError -Context $Context -Message "invalid --ignore-initial value '$text'"; return }
            $skips[$k] = $value
        }
    }
    for ($k = 2; $k -lt [Math]::Min(4, $operands.Count); $k++) {
        $value = ConvertFrom-GnuCmpSkip -Text $operands[$k]
        if ($null -eq $value) { Write-GnuUsageError -Context $Context -Message "invalid --ignore-initial value '$($operands[$k])'"; return }
        $skips[$k - 2] = $value
    }
    if ($operands.Count -gt 4) { Write-GnuUsageError -Context $Context -Message "extra operand '$($operands[4])'"; return }
    $limit = [long]::MaxValue
    if (Test-GnuOption -Context $Context -Key 'bytes') {
        $text = [string](Get-GnuOptionValue -Context $Context -Key 'bytes')
        $value = ConvertFrom-GnuCmpSkip -Text $text
        if ($null -eq $value) { Write-GnuUsageError -Context $Context -Message "invalid --bytes value '$text'"; return }
        $limit = $value
    }

    $names = @($operands[0], '-')
    if ($operands.Count -ge 2) { $names[1] = $operands[1] }
    $data = @()
    foreach ($name in $names) {
        $bytes = Get-GnuInputBytes -Context $Context -Operand $name
        if ($null -eq $bytes) { $Context.ExitCode = 2; return }
        $data += , ([byte[]]$bytes)
    }
    $starts = @([Math]::Min($skips[0], [long]$data[0].Length), [Math]::Min($skips[1], [long]$data[1].Length))
    $lengths = @(($data[0].Length - $starts[0]), ($data[1].Length - $starts[1]))
    $common = [long][Math]::Min([Math]::Min($lengths[0], $lengths[1]), $limit)
    $offsetWidth = ([string][Math]::Min([Math]::Min($lengths[0], $lengths[1]), $limit)).Length

    $line = 1
    $different = $false
    for ($i = [long]0; $i -lt $common; $i++) {
        $a = $data[0][$starts[0] + $i]
        $b = $data[1][$starts[1] + $i]
        if ($a -ne $b) {
            $different = $true
            if ($quiet) { break }
            if (-not $verbose) {
                $message = "$($names[0]) $($names[1]) differ: "
                if ($printBytes) {
                    $message += "byte $($i + 1), line $line is " + ('{0,3} {1} {2,3} {3}' -f [System.Convert]::ToString([int]$a, 8), (ConvertTo-GnuCmpCharacter -Byte $a), [System.Convert]::ToString([int]$b, 8), (ConvertTo-GnuCmpCharacter -Byte $b))
                }
                else { $message += "char $($i + 1), line $line" }
                $message
                break
            }
            $entry = ([string]($i + 1)).PadLeft($offsetWidth) + ' ' + [System.Convert]::ToString([int]$a, 8).PadLeft(3)
            if ($printBytes) { $entry += ' ' + (ConvertTo-GnuCmpCharacter -Byte $a).PadRight(4) }
            $entry += ' ' + [System.Convert]::ToString([int]$b, 8).PadLeft(3)
            if ($printBytes) { $entry += ' ' + (ConvertTo-GnuCmpCharacter -Byte $b) }
            $entry
        }
        if ($a -eq 10) { $line++ }
    }

    if ($different) { $Context.ExitCode = 1 }
    if ((-not $different -or $verbose) -and $lengths[0] -ne $lengths[1] -and $common -lt $limit) {
        # One input ended first.
        $short = 0
        if ($lengths[1] -lt $lengths[0]) { $short = 1 }
        $Context.ExitCode = 1
        if ($quiet) { return }
        if ($common -eq 0) { Write-GnuError -Context $Context -Message "EOF on '$($names[$short])' which is empty"; return }
        $where = ''
        if (-not $verbose) {
            $lastByte = $data[$short][$starts[$short] + $common - 1]
            if ($lastByte -eq 10) { $where = ", line $($line - 1)" } else { $where = ", in line $line" }
        }
        Write-GnuError -Context $Context -Message "EOF on '$($names[$short])' after byte $common$where"
    }
}
