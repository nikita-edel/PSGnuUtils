Register-GnuUtil @{
    Name          = 'expr'
    Category      = 'Shell helpers'
    Synopsis      = 'Evaluate expressions.'
    Usage         = @('expr EXPRESSION', 'expr OPTION')
    Description   = @('Print the value of EXPRESSION to standard output.  A blank line below', 'separates increasing precedence groups.  EXPRESSION may be:')
    RawArguments  = $true
    UsageExitCode = 2
    Notes         = @(
        '  ARG1 | ARG2       ARG1 if it is neither null nor 0, otherwise ARG2',
        '',
        '  ARG1 & ARG2       ARG1 if neither argument is null or 0, otherwise 0',
        '',
        '  ARG1 < ARG2       ARG1 is less than ARG2',
        '  ARG1 <= ARG2      ARG1 is less than or equal to ARG2',
        '  ARG1 = ARG2       ARG1 is equal to ARG2',
        '  ARG1 != ARG2      ARG1 is unequal to ARG2',
        '  ARG1 >= ARG2      ARG1 is greater than or equal to ARG2',
        '  ARG1 > ARG2       ARG1 is greater than ARG2',
        '',
        '  ARG1 + ARG2       arithmetic sum of ARG1 and ARG2',
        '  ARG1 - ARG2       arithmetic difference of ARG1 and ARG2',
        '',
        '  ARG1 * ARG2       arithmetic product of ARG1 and ARG2',
        '  ARG1 / ARG2       arithmetic quotient of ARG1 divided by ARG2',
        '  ARG1 % ARG2       arithmetic remainder of ARG1 divided by ARG2',
        '',
        '  STRING : REGEXP   anchored pattern match of REGEXP in STRING',
        '',
        '  match STRING REGEXP        same as STRING : REGEXP',
        '  substr STRING POS LENGTH   substring of STRING, POS counted from 1',
        '  index STRING CHARS         index in STRING where any CHARS is found, or 0',
        '  length STRING              length of STRING',
        '  + TOKEN                    interpret TOKEN as a string, even if it is a',
        '                               keyword like ''match'' or an operator like ''/''',
        '',
        '  ( EXPRESSION )             value of EXPRESSION',
        '',
        'Beware that many operators need to be escaped or quoted for shells.',
        'Comparisons are arithmetic if both ARGs are numbers, else lexicographical.',
        'Pattern matches return the string matched between \( and \) or null; if',
        '\( and \) are not used, they return the number of characters matched or 0.',
        '',
        'Exit status is 0 if EXPRESSION is neither null nor 0, 1 if EXPRESSION is null',
        'or 0, 2 if EXPRESSION is syntactically invalid, and 3 if an error occurred.',
        '',
        'PowerShell note: quote | & < > ( ) in PowerShell. String comparisons are ordinal.'
    )
}

function Invoke-GnuExpr {
    <#
    .SYNOPSIS
    GNU expr: evaluate an expression given as separate arguments.

    .DESCRIPTION
    Evaluates integer arithmetic (any size), comparisons, '|' / '&', regular expression matches
    (STRING : REGEXP) and the string functions match, substr, index and length. Prints the
    result; the exit code is 1 when it is null or 0, 2 for syntax errors and 3 for other errors.
    Enable the GNU name with: Enable-GnuUtil expr

    .EXAMPLE
    Invoke-GnuExpr 6 '*' 7

    .EXAMPLE
    Invoke-GnuExpr report-2024.txt : 'report-\([0-9]*\)'
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'expr' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            $arguments = [string[]]@($ctx.Operands)
            if ($arguments.Length -gt 0 -and $arguments[0] -ceq '--') { $arguments = [string[]]@($arguments | Select-Object -Skip 1) }
            if ($arguments.Length -eq 0) { Write-GnuUsageError -Context $ctx -Message 'missing operand' }
            else {
                $state = @{ Args = $arguments; Pos = 0 }
                try {
                    $value = Invoke-GnuExprOr -State $state -Evaluate $true
                    if ($state.Pos -lt $arguments.Length) { Stop-GnuExpr -Message "syntax error: unexpected argument '$($arguments[$state.Pos])'" -ExitCode 2 }
                    [string]$value
                    if (Test-GnuExprNull -Value $value) { $ctx.ExitCode = 1 }
                }
                catch {
                    $message = $_.Exception.Message
                    if ($message -notmatch '^GNUEXPR([23]):') { throw }
                    Write-GnuError -Context $ctx -Message $message.Substring(10) -ExitCode ([int]$Matches[1])
                }
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}

function Stop-GnuExpr {
    <#
    .SYNOPSIS
    Aborts the evaluation (exit code 2 for syntax errors, 3 for other errors).
    #>
    param([Parameter(Mandatory)][string]$Message, [Parameter(Mandatory)][int]$ExitCode)
    throw "GNUEXPR$($ExitCode): $Message"
}

function Test-GnuExprInteger {
    <#
    .SYNOPSIS
    $true if a value is an integer (BigInteger) or a string that looks like one.
    #>
    param([AllowNull()][object]$Value)
    $Value -is [System.Numerics.BigInteger] -or ([string]$Value -cmatch '^-?\d+$')
}

function ConvertTo-GnuExprInteger {
    <#
    .SYNOPSIS
    A value as BigInteger, or the "non-integer argument" error.
    #>
    param([AllowNull()][object]$Value)
    if ($Value -is [System.Numerics.BigInteger]) { return $Value }
    if (-not (Test-GnuExprInteger -Value $Value)) { Stop-GnuExpr -Message 'non-integer argument' -ExitCode 2 }
    [System.Numerics.BigInteger]::Parse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture)
}

function Test-GnuExprNull {
    <#
    .SYNOPSIS
    $true for the empty string and for zero ('0', '-0', '00', ...).
    #>
    param([AllowNull()][object]$Value)
    if ($Value -is [System.Numerics.BigInteger]) { return $Value -eq 0 }
    $text = [string]$Value
    [string]::IsNullOrEmpty($text) -or $text -cmatch '^-?0+$'
}

function Get-GnuExprToken {
    <#
    .SYNOPSIS
    The current argument if it equals Token (and moves past it), else $null.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][string[]]$Token)
    if ($State.Pos -lt $State.Args.Length -and $Token -ccontains $State.Args[$State.Pos]) {
        $State.Pos++
        return $State.Args[$State.Pos - 1]
    }
    $null
}

function Invoke-GnuExprOr {
    <#
    .SYNOPSIS
    ARG1 | ARG2 (lowest precedence).
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][bool]$Evaluate)
    $left = Invoke-GnuExprAnd -State $State -Evaluate $Evaluate
    while ($null -ne (Get-GnuExprToken -State $State -Token '|')) {
        $right = Invoke-GnuExprAnd -State $State -Evaluate ($Evaluate -and (Test-GnuExprNull -Value $left))
        if (Test-GnuExprNull -Value $left) {
            $left = $right
            if (Test-GnuExprNull -Value $left) { $left = [System.Numerics.BigInteger]::Zero }
        }
    }
    $left
}

function Invoke-GnuExprAnd {
    <#
    .SYNOPSIS
    ARG1 & ARG2.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][bool]$Evaluate)
    $left = Invoke-GnuExprCompare -State $State -Evaluate $Evaluate
    while ($null -ne (Get-GnuExprToken -State $State -Token '&')) {
        $right = Invoke-GnuExprCompare -State $State -Evaluate ($Evaluate -and -not (Test-GnuExprNull -Value $left))
        if ((Test-GnuExprNull -Value $left) -or (Test-GnuExprNull -Value $right)) { $left = [System.Numerics.BigInteger]::Zero }
    }
    $left
}

function Invoke-GnuExprCompare {
    <#
    .SYNOPSIS
    < <= = == != >= > (numeric if both sides are integers, else ordinal).
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][bool]$Evaluate)
    $left = Invoke-GnuExprSum -State $State -Evaluate $Evaluate
    while ($null -ne ($operator = Get-GnuExprToken -State $State -Token '<', '<=', '=', '==', '!=', '>=', '>')) {
        $right = Invoke-GnuExprSum -State $State -Evaluate $Evaluate
        if ((Test-GnuExprInteger -Value $left) -and (Test-GnuExprInteger -Value $right)) {
            $order = [System.Numerics.BigInteger]::Compare((ConvertTo-GnuExprInteger -Value $left), (ConvertTo-GnuExprInteger -Value $right))
        }
        else { $order = [string]::CompareOrdinal([string]$left, [string]$right) }
        $result = switch ($operator) {
            '<' { $order -lt 0 }
            '<=' { $order -le 0 }
            '!=' { $order -ne 0 }
            '>=' { $order -ge 0 }
            '>' { $order -gt 0 }
            default { $order -eq 0 }
        }
        $left = [System.Numerics.BigInteger][int]$result
    }
    $left
}

function Invoke-GnuExprSum {
    <#
    .SYNOPSIS
    ARG1 + ARG2, ARG1 - ARG2.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][bool]$Evaluate)
    $left = Invoke-GnuExprProduct -State $State -Evaluate $Evaluate
    while ($null -ne ($operator = Get-GnuExprToken -State $State -Token '+', '-')) {
        $right = Invoke-GnuExprProduct -State $State -Evaluate $Evaluate
        if (-not $Evaluate) { continue }
        $a = ConvertTo-GnuExprInteger -Value $left
        $b = ConvertTo-GnuExprInteger -Value $right
        if ($operator -eq '+') { $left = $a + $b } else { $left = $a - $b }
    }
    $left
}

function Invoke-GnuExprProduct {
    <#
    .SYNOPSIS
    ARG1 * ARG2, ARG1 / ARG2, ARG1 % ARG2 (truncating like C).
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][bool]$Evaluate)
    $left = Invoke-GnuExprMatch -State $State -Evaluate $Evaluate
    while ($null -ne ($operator = Get-GnuExprToken -State $State -Token '*', '/', '%')) {
        $right = Invoke-GnuExprMatch -State $State -Evaluate $Evaluate
        if (-not $Evaluate) { continue }
        $a = ConvertTo-GnuExprInteger -Value $left
        $b = ConvertTo-GnuExprInteger -Value $right
        if ($operator -eq '*') { $left = $a * $b; continue }
        if ($b -eq 0) { Stop-GnuExpr -Message 'division by zero' -ExitCode 2 }
        if ($operator -eq '/') { $left = [System.Numerics.BigInteger]::Divide($a, $b) } else { $left = [System.Numerics.BigInteger]::Remainder($a, $b) }
    }
    $left
}

function Invoke-GnuExprMatch {
    <#
    .SYNOPSIS
    STRING : REGEXP.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][bool]$Evaluate)
    $left = Invoke-GnuExprUnary -State $State -Evaluate $Evaluate
    while ($null -ne (Get-GnuExprToken -State $State -Token ':')) {
        $right = Invoke-GnuExprUnary -State $State -Evaluate $Evaluate
        if ($Evaluate) { $left = Get-GnuExprRegexMatch -Text ([string]$left) -Pattern ([string]$right) }
    }
    $left
}

function Get-GnuExprRegexMatch {
    <#
    .SYNOPSIS
    The anchored BRE match: group 1 (or '') if the pattern has \( \), else the matched length.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [Parameter(Mandatory)][AllowEmptyString()][string]$Pattern)
    $converted = ConvertTo-GnuDotNetRegex -Pattern $Pattern
    if ($converted.ContainsKey('Error')) { Stop-GnuExpr -Message $converted.Error -ExitCode 2 }
    # .NET messages are localized, so classify an invalid pattern ourselves (like grep).
    switch (Get-GnuParenthesisBalance -Regex $converted.Regex) {
        'open' { Stop-GnuExpr -Message 'Unmatched ( or \(' -ExitCode 2 }
        'close' { Stop-GnuExpr -Message 'Unmatched ) or \)' -ExitCode 2 }
    }
    $match = [regex]::Match($Text, '\A(?:' + $converted.Regex + ')')
    if ($Pattern.Contains('\(')) {
        if ($match.Success -and $match.Groups[1].Success) { return $match.Groups[1].Value }
        return ''
    }
    if ($match.Success) { return [System.Numerics.BigInteger]$match.Length }
    [System.Numerics.BigInteger]::Zero
}

function Invoke-GnuExprUnary {
    <#
    .SYNOPSIS
    + TOKEN, match, substr, index, length, or a primary.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][bool]$Evaluate)

    $keyword = Get-GnuExprToken -State $State -Token '+', 'length', 'match', 'index', 'substr'
    switch ($keyword) {
        '+' { return Read-GnuExprArgument -State $State }
        'length' { return [System.Numerics.BigInteger](Read-GnuExprArgument -State $State).Length }
        'match' {
            $text = Read-GnuExprArgument -State $State
            $pattern = Read-GnuExprArgument -State $State
            if (-not $Evaluate) { return '' }
            return Get-GnuExprRegexMatch -Text $text -Pattern $pattern
        }
        'index' {
            $text = Read-GnuExprArgument -State $State
            $chars = Read-GnuExprArgument -State $State
            return [System.Numerics.BigInteger]($text.IndexOfAny($chars.ToCharArray()) + 1)
        }
        'substr' {
            $text = Read-GnuExprArgument -State $State
            $position = Read-GnuExprArgument -State $State
            $length = Read-GnuExprArgument -State $State
            if (-not ((Test-GnuExprInteger -Value $position) -and (Test-GnuExprInteger -Value $length))) { return '' }
            $start = ConvertTo-GnuExprInteger -Value $position
            $count = ConvertTo-GnuExprInteger -Value $length
            if ($start -lt 1 -or $count -lt 1 -or $start -gt $text.Length) { return '' }
            $take = [int][System.Numerics.BigInteger]::Min($count, $text.Length - [int]$start + 1)
            return $text.Substring([int]$start - 1, $take)
        }
    }
    Invoke-GnuExprPrimary -State $State -Evaluate $Evaluate
}

function Read-GnuExprArgument {
    <#
    .SYNOPSIS
    The next argument taken literally, or the "missing argument" syntax error.
    #>
    param([Parameter(Mandatory)][hashtable]$State)
    if ($State.Pos -ge $State.Args.Length) { Stop-GnuExpr -Message "syntax error: missing argument after '$($State.Args[$State.Pos - 1])'" -ExitCode 2 }
    $State.Pos++
    $State.Args[$State.Pos - 1]
}

function Invoke-GnuExprPrimary {
    <#
    .SYNOPSIS
    ( EXPRESSION ) or a single argument.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][bool]$Evaluate)

    if ($State.Pos -ge $State.Args.Length) { Stop-GnuExpr -Message "syntax error: missing argument after '$($State.Args[$State.Pos - 1])'" -ExitCode 2 }
    $token = $State.Args[$State.Pos]
    if ($token -ceq ')') { Stop-GnuExpr -Message "syntax error: unexpected ')'" -ExitCode 2 }
    $State.Pos++
    if ($token -cne '(') { return $token }
    $value = Invoke-GnuExprOr -State $State -Evaluate $Evaluate
    if ($State.Pos -ge $State.Args.Length) { Stop-GnuExpr -Message "syntax error: expecting ')' after '$($State.Args[$State.Pos - 1])'" -ExitCode 2 }
    if ($State.Args[$State.Pos] -cne ')') { Stop-GnuExpr -Message "syntax error: expecting ')' instead of '$($State.Args[$State.Pos])'" -ExitCode 2 }
    $State.Pos++
    $value
}
