Register-GnuUtil @{
    Name                   = 'factor'
    Category               = 'Shell helpers'
    Synopsis               = 'Factor numbers.'
    Usage                  = @('factor [NUMBER]...', 'factor OPTION')
    Description            = @(
        'Print the prime factors of each specified integer NUMBER.  If none',
        'are specified on the command line, read them from standard input.'
    )
    NegativeNumberOperands = $true
    Options                = @(
        @{ Short = 'h'; Long = 'exponents'; Help = 'print repeated factors in form p^e unless e is 1' }
    )
    Notes                  = @(
        'Numbers of any size are accepted (System.Numerics.BigInteger, Miller-Rabin, Pollard rho).',
        'PowerShell note: much slower than GNU; numbers whose two smallest prime factors both have',
        'more than about 12 digits can take very long.'
    )
}

function Invoke-GnuFactor {
    <#
    .SYNOPSIS
    GNU factor: print the prime factors of numbers.

    .DESCRIPTION
    Prints "N: p1 p2 ..." for every NUMBER (or every whitespace separated number of the pipeline
    input). -h prints repeated factors as p^e.
    Enable the GNU name with: Enable-GnuUtil factor

    .EXAMPLE
    Invoke-GnuFactor 84 1000000007

    84: 2 2 3 7
    1000000007: 1000000007
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'factor' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) {
            $numbers = @($ctx.Operands)
            if ($numbers.Count -eq 0) {
                $numbers = @(@(Read-GnuStdinLine -Context $ctx) | ForEach-Object { $_ -split '\s+' } | Where-Object { -not [string]::IsNullOrEmpty($_) })
            }
            foreach ($text in $numbers) {
                $value = [System.Numerics.BigInteger]::Zero
                $clean = $text.Trim()
                if ($clean.StartsWith('+', [System.StringComparison]::Ordinal)) { $clean = $clean.Substring(1) }
                if ($clean -notmatch '^\d+$' -or -not [System.Numerics.BigInteger]::TryParse($clean, [ref]$value)) {
                    Write-GnuError -Context $ctx -Message "'$text' is not a valid positive integer"
                    continue
                }
                $factors = @(Get-GnuPrimeFactor -Value $value)
                $parts = New-Object 'System.Collections.Generic.List[string]'
                if (Test-GnuOption -Context $ctx -Key 'exponents') {
                    $i = 0
                    while ($i -lt $factors.Count) {
                        $j = $i
                        while ($j -lt $factors.Count -and $factors[$j] -eq $factors[$i]) { $j++ }
                        if ($j - $i -gt 1) { $parts.Add("$($factors[$i])^$($j - $i)") } else { $parts.Add([string]$factors[$i]) }
                        $i = $j
                    }
                }
                else {
                    foreach ($factor in $factors) { $parts.Add([string]$factor) }
                }
                ("$($value):" + (($parts | ForEach-Object { " $_" }) -join '')).TrimEnd()
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}

function Test-GnuProbablePrime {
    <#
    .SYNOPSIS
    Miller-Rabin test; deterministic for numbers below 3.3e24 with these bases.
    #>
    param([Parameter(Mandatory)][System.Numerics.BigInteger]$Value)

    if ($Value -lt 2) { return $false }
    foreach ($small in @(2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41)) {
        if ($Value -eq $small) { return $true }
        if ($Value % $small -eq 0) { return $false }
    }
    $d = $Value - 1
    $r = 0
    while ($d % 2 -eq 0) { $d = $d / 2; $r++ }
    foreach ($base in @(2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41)) {
        $x = [System.Numerics.BigInteger]::ModPow($base, $d, $Value)
        if ($x -eq 1 -or $x -eq $Value - 1) { continue }
        $composite = $true
        for ($i = 1; $i -lt $r; $i++) {
            $x = [System.Numerics.BigInteger]::ModPow($x, 2, $Value)
            if ($x -eq $Value - 1) { $composite = $false; break }
        }
        if ($composite) { return $false }
    }
    $true
}

function Find-GnuFactorPollard {
    <#
    .SYNOPSIS
    Finds a non-trivial factor of a composite number with Pollard's rho (Floyd cycle detection).
    #>
    param([Parameter(Mandatory)][System.Numerics.BigInteger]$Value)

    for ($c = 1; ; $c++) {
        $x = [System.Numerics.BigInteger]2
        $y = [System.Numerics.BigInteger]2
        $d = [System.Numerics.BigInteger]::One
        while ($d -eq 1) {
            $x = ($x * $x + $c) % $Value
            $y = ($y * $y + $c) % $Value
            $y = ($y * $y + $c) % $Value
            $d = [System.Numerics.BigInteger]::GreatestCommonDivisor([System.Numerics.BigInteger]::Abs($x - $y), $Value)
        }
        if ($d -ne $Value) { return $d }
    }
}

function Get-GnuPrimeFactor {
    <#
    .SYNOPSIS
    The prime factors of a number in ascending order (with repetition).
    #>
    param([Parameter(Mandatory)][System.Numerics.BigInteger]$Value)

    $factors = New-Object 'System.Collections.Generic.List[System.Numerics.BigInteger]'
    $n = $Value
    foreach ($p in @(2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47)) {
        while ($n -gt 1 -and $n % $p -eq 0) { $factors.Add($p); $n = $n / $p }
    }
    $pending = New-Object 'System.Collections.Generic.Stack[System.Numerics.BigInteger]'
    if ($n -gt 1) { $pending.Push($n) }
    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        if (Test-GnuProbablePrime -Value $current) { $factors.Add($current); continue }
        $divisor = Find-GnuFactorPollard -Value $current
        $pending.Push($divisor)
        $pending.Push($current / $divisor)
    }
    $factors.Sort()
    foreach ($factor in $factors) { $factor }
}
