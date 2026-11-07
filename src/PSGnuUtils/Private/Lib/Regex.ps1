# POSIX basic (BRE) and extended (ERE) regular expressions -> .NET regular expressions (grep, later sed).

$script:GnuPosixClasses = @{
    alpha  = '\p{L}'
    digit  = '0-9'
    alnum  = '\p{L}\p{Nd}'
    upper  = '\p{Lu}'
    lower  = '\p{Ll}'
    space  = '\s'
    blank  = ' \t'
    punct  = '\p{P}\p{S}'
    print  = '\P{C}'
    graph  = '\p{L}\p{M}\p{N}\p{P}\p{S}'
    cntrl  = '\p{Cc}'
    xdigit = '0-9A-Fa-f'
}

function ConvertFrom-GnuBracketExpression {
    <#
    .SYNOPSIS
    Converts the POSIX bracket expression starting at Pattern[Index] ('['). Returns @{ Regex; Next } or @{ Error }.
    .NOTES
    Inside brackets a backslash is an ordinary character in POSIX; ']' right after '[' or '[^' is literal.
    #>
    param([Parameter(Mandatory)][string]$Pattern, [Parameter(Mandatory)][int]$Index)

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('[')
    $i = $Index + 1
    if ($i -lt $Pattern.Length -and $Pattern[$i] -eq '^') { [void]$builder.Append('^'); $i++ }
    $first = $true
    while ($i -lt $Pattern.Length) {
        $char = $Pattern[$i]
        if ($char -eq ']' -and -not $first) { return @{ Regex = $builder.Append(']').ToString(); Next = $i + 1 } }
        $first = $false
        if ($char -eq '[' -and $i + 1 -lt $Pattern.Length -and ':=.'.IndexOf($Pattern[$i + 1]) -ge 0) {
            $kind = $Pattern[$i + 1]
            $close = $Pattern.IndexOf([string]$kind + ']', $i + 2, [System.StringComparison]::Ordinal)
            if ($close -lt 0) { return @{ Error = 'Unmatched [, [^, [:, [., or [=' } }
            $name = $Pattern.Substring($i + 2, $close - $i - 2)
            if ($kind -eq ':') {
                if (-not $script:GnuPosixClasses.ContainsKey($name)) { return @{ Error = 'Invalid character class name' } }
                [void]$builder.Append($script:GnuPosixClasses[$name])
            }
            else {
                # [=a=] and [.a.]: equivalence classes and collating symbols, treated as the literal text.
                foreach ($literal in $name.ToCharArray()) { [void]$builder.Append([regex]::Escape([string]$literal).Replace(']', '\]').Replace('-', '\-')) }
            }
            $i = $close + 2
            continue
        }
        switch ($char) {
            '\' { [void]$builder.Append('\\') }
            '[' { [void]$builder.Append('\[') }
            '^' { [void]$builder.Append('\^') }
            default { [void]$builder.Append($char) }
        }
        $i++
    }
    @{ Error = 'Unmatched [, [^, [:, [., or [=' }
}

function ConvertTo-GnuDotNetRegex {
    <#
    .SYNOPSIS
    Converts a POSIX BRE (default) or ERE (-Extended) to .NET syntax. Returns @{ Regex } or @{ Error }.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Pattern, [switch]$Extended)

    $builder = New-Object System.Text.StringBuilder
    $atStart = $true      # where '*' is literal and a BRE '^' is an anchor
    $i = 0
    while ($i -lt $Pattern.Length) {
        $char = $Pattern[$i]

        if ($char -eq '[') {
            $bracket = ConvertFrom-GnuBracketExpression -Pattern $Pattern -Index $i
            if ($bracket.ContainsKey('Error')) { return @{ Error = $bracket.Error } }
            [void]$builder.Append($bracket.Regex)
            $i = $bracket.Next
            $atStart = $false
            continue
        }

        if ($char -eq '\' -and $i + 1 -lt $Pattern.Length) {
            $next = [string]$Pattern[$i + 1]
            $i += 2
            if (-not $Extended -and '(){}|+?'.Contains($next)) {
                [void]$builder.Append($next)
                $atStart = $next -eq '(' -or $next -eq '|'
                continue
            }
            switch -CaseSensitive ($next) {
                '<' { [void]$builder.Append('\b(?=\w)') }
                '>' { [void]$builder.Append('\b(?<=\w)') }
                '`' { [void]$builder.Append('\A') }
                "'" { [void]$builder.Append('\z') }
                default {
                    if ('wWsSbB123456789'.Contains($next)) { [void]$builder.Append('\' + $next) }
                    else { [void]$builder.Append([regex]::Escape($next)) }
                }
            }
            $atStart = $false
            continue
        }
        if ($char -eq '\') { return @{ Error = 'Trailing backslash' } }
        $i++

        if (-not $Extended -and '(){}|+?'.Contains([string]$char)) {
            [void]$builder.Append([regex]::Escape([string]$char).Replace('}', '\}'))
            $atStart = $false
            continue
        }
        if ($char -eq '*' -and $atStart) {
            [void]$builder.Append('\*')
            $atStart = $false
            continue
        }
        if ($char -eq '^') {
            if ($Extended -or $atStart) { [void]$builder.Append('^') } else { [void]$builder.Append('\^') }
            continue   # a '*' right after '^' is still literal
        }
        if ($char -eq '$') {
            $rest = $Pattern.Substring($i)
            $anchor = $Extended -or $rest.Length -eq 0 -or $rest.StartsWith('\)', [System.StringComparison]::Ordinal) -or $rest.StartsWith('\|', [System.StringComparison]::Ordinal)
            if ($anchor) { [void]$builder.Append('$') } else { [void]$builder.Append('\$') }
            $atStart = $false
            continue
        }
        if ($Extended -and ($char -eq '(' -or $char -eq '|')) {
            [void]$builder.Append($char)
            $atStart = $true
            continue
        }
        if ($Extended -and $char -eq '{') {
            # An ERE '{' only starts an interval when one follows; otherwise it is literal (like GNU).
            if ($Pattern.Substring($i) -match '^\d+(,\d*)?\}') { [void]$builder.Append('{') } else { [void]$builder.Append('\{') }
            $atStart = $false
            continue
        }
        if ('.*+?)}'.Contains([string]$char)) { [void]$builder.Append($char) }
        else { [void]$builder.Append([regex]::Escape([string]$char)) }
        $atStart = $false
    }
    @{ Regex = $builder.ToString() }
}

function Get-GnuParenthesisBalance {
    <#
    .SYNOPSIS
    'open' if a .NET pattern has unclosed groups, 'close' if it closes groups that were never opened, else 'ok'.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Regex)

    $depth = 0
    $inClass = $false
    for ($i = 0; $i -lt $Regex.Length; $i++) {
        $char = $Regex[$i]
        if ($char -eq [char]92) { $i++; continue }   # backslash: skip the escaped character
        if ($inClass) {
            if ($char -eq ']') { $inClass = $false }
            continue
        }
        if ($char -eq '[') {
            $inClass = $true
            if ($i + 1 -lt $Regex.Length -and $Regex[$i + 1] -eq '^') { $i++ }
            if ($i + 1 -lt $Regex.Length -and $Regex[$i + 1] -eq ']') { $i++ }
            continue
        }
        if ($char -eq '(') { $depth++ }
        elseif ($char -eq ')') {
            $depth--
            if ($depth -lt 0) { return 'close' }
        }
    }
    if ($depth -gt 0) { return 'open' }
    'ok'
}
