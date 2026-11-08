Register-GnuUtil @{
    Name        = 'sed'
    Category    = 'Searching and comparing'
    Synopsis    = 'Stream editor for filtering and transforming text.'
    Usage       = @('sed [OPTION]... {script-only-if-no-other-script} [input-file]...')
    Description = @(
        'If no -e, --expression, -f, or --file option is given, then the first non-option',
        'argument is taken as the sed script to interpret.  All remaining arguments are names',
        'of input files; if no input files are specified, then the standard input is read.'
    )
    Options     = @(
        @{ Short = 'n'; Long = 'quiet'; Key = 'quiet'; Help = 'suppress automatic printing of pattern space' }
        @{ Long = 'silent'; Key = 'quiet'; Help = 'same as --quiet' }
        @{ Short = 'e'; Long = 'expression'; Key = 'script'; Arg = 'script'; Multi = $true; Prefix = 'e:'; Help = 'add the script to the commands to be executed' }
        @{ Short = 'f'; Long = 'file'; Key = 'script'; Arg = 'script-file'; Multi = $true; Prefix = 'f:'; Help = 'add the contents of script-file to the commands to be executed' }
        @{ Long = 'follow-symlinks'; Help = 'follow symlinks when processing in place (always done)' }
        @{ Short = 'i'; Long = 'in-place'; Arg = 'SUFFIX'; OptionalArg = $true; Help = 'edit files in place (makes backup if SUFFIX supplied)' }
        @{ Short = 'b'; Long = 'binary'; Help = 'keep carriage returns: CR+LF is not treated as a line end' }
        @{ Short = 'l'; Long = 'line-length'; Arg = 'N'; Help = 'specify the desired line-wrap length for the `l'' command' }
        @{ Long = 'posix'; Help = 'accepted; GNU extensions stay enabled' }
        @{ Short = 'E'; Long = 'regexp-extended'; Key = 'extended'; Help = 'use extended regular expressions in the script' }
        @{ Short = 'r'; Key = 'extended'; Help = 'same as -E' }
        @{ Short = 's'; Long = 'separate'; Help = 'consider files as separate rather than as a single, continuous long stream' }
        @{ Long = 'sandbox'; Help = 'operate in sandbox mode (disable r/w commands)' }
        @{ Short = 'u'; Long = 'unbuffered'; Help = 'accepted; output is written line by line anyway' }
        @{ Short = 'z'; Long = 'null-data'; Help = 'separate lines by NUL characters' }
    )
    Notes       = @(
        'PowerShell notes: regular expressions run on .NET (POSIX syntax is translated). Input is read',
        'before the script starts, so `sed q` does not stop an endless pipeline. On Windows a line ending',
        'in CR+LF loses the CR unless -b is given, and -i writes CR+LF back. The e command and the e flag',
        'of s are not supported. Without a script the short usage is printed instead of the full help.'
    )
}

function Invoke-GnuSed {
    <#
    .SYNOPSIS
    GNU sed: stream editor for filtering and transforming text.

    .DESCRIPTION
    Runs a sed script over files or the pipeline. Supports addresses (N, $, /re/, first~step,
    addr,+N, addr,~N, 0,/re/, !), all editing commands including hold space and branching
    (s y d D p P n N g G h H x a i c = l q Q r R w W b t T : { } F z), and -n -e -f -E -r -i -s -z -l.
    Enable the GNU name with: Enable-GnuUtil sed

    .EXAMPLE
    Invoke-GnuSed -i.bak 's/foo/bar/g' notes.txt

    .EXAMPLE
    Get-Content log.txt | Invoke-GnuSed -n '/ERROR/,/^$/p'
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'sed' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuSedEdit -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function New-GnuSedRegex {
    <#
    .SYNOPSIS
    Compiles a sed pattern; $null for the empty pattern (meaning: the last one used). Throws FormatException for bad patterns.
    #>
    param([Parameter(Mandatory)][hashtable]$Parser, [AllowEmptyString()][string]$Pattern, [bool]$IgnoreCase, [bool]$Multiline)

    if ([string]::IsNullOrEmpty($Pattern)) { return $null }
    $converted = ConvertTo-GnuDotNetRegex -Pattern (ConvertFrom-GnuSedEscape -Text $Pattern) -Extended:$Parser.Extended -AbsoluteEnd:(-not $Multiline)
    if ($converted.ContainsKey('Error')) { throw [System.FormatException]::new($converted.Error) }
    $options = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant -bor [System.Text.RegularExpressions.RegexOptions]::Singleline
    if ($IgnoreCase) { $options = $options -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }
    if ($Multiline) { $options = $options -bor [System.Text.RegularExpressions.RegexOptions]::Multiline }
    try { return New-Object System.Text.RegularExpressions.Regex -ArgumentList $converted.Regex, $options }
    catch {
        # .NET messages are localized, so classify the error ourselves.
        $message = 'Invalid preceding regular expression'
        switch (Get-GnuParenthesisBalance -Regex $converted.Regex) {
            'open' { $message = 'Unmatched ( or \(' }
            'close' { $message = 'Unmatched ) or \)' }
            default { if ($converted.Regex -match '\\[1-9]') { $message = 'Invalid back reference' } }
        }
        throw [System.FormatException]::new($message)
    }
}

function Read-GnuSedEscapeCode {
    <#
    .SYNOPSIS
    Decodes the escape after the backslash at Text[Index] (\a \f \t \v \cX \dNNN \oNNN \xHH): @{ Text; Next }, or $null.
    #>
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][int]$Index)

    $letter = [string]$Text[$Index + 1]
    $single = ''
    switch -CaseSensitive ($letter) {
        'a' { $single = [string][char]7 }
        'f' { $single = [string][char]12 }
        'r' { $single = "`r" }
        't' { $single = "`t" }
        'v' { $single = [string][char]11 }
    }
    if ($single.Length -gt 0) { return @{ Text = $single; Next = $Index + 2 } }
    if ($letter -ceq 'c' -and $Index + 2 -lt $Text.Length) {
        return @{ Text = [string][char]([int][char]([string]$Text[$Index + 2]).ToUpperInvariant() -bxor 64); Next = $Index + 3 }
    }
    $rules = @{ d = @('^\d{1,3}', 10); o = @('^[0-7]{1,3}', 8); x = @('^[0-9A-Fa-f]{1,2}', 16) }
    if ('d', 'o', 'x' -ccontains $letter) {
        $digits = [regex]::Match($Text.Substring($Index + 2), $rules[$letter][0]).Value
        if ($digits.Length -gt 0) { return @{ Text = [string][char]([Convert]::ToInt32($digits, $rules[$letter][1]) -band 255); Next = $Index + 2 + $digits.Length } }
    }
    $null
}

function ConvertFrom-GnuSedEscape {
    <#
    .SYNOPSIS
    Replaces sed's character escapes in a pattern by the characters; a produced special character stays literal.
    #>
    param([Parameter(Mandatory)][string]$Text)

    $builder = New-Object System.Text.StringBuilder
    $inBracket = $false
    $i = 0
    while ($i -lt $Text.Length) {
        $char = [string]$Text[$i]
        if ($inBracket -and $char -ceq ']') { $inBracket = $false }
        elseif ($char -ceq '[' -and -not $inBracket) {
            $inBracket = $true
            [void]$builder.Append($char)
            $i++
            # A ']' right after '[' or '[^' is an ordinary member.
            if ($i -lt $Text.Length -and $Text[$i] -eq '^') { [void]$builder.Append('^'); $i++ }
            if ($i -lt $Text.Length -and $Text[$i] -eq ']') { [void]$builder.Append(']'); $i++ }
            continue
        }
        if ($char -ceq '\' -and $i + 1 -lt $Text.Length) {
            if ($inBracket -and $Text[$i + 1] -ceq 'n') { [void]$builder.Append("`n"); $i += 2; continue }
            $code = Read-GnuSedEscapeCode -Text $Text -Index $i
            if ($null -ne $code) {
                if (-not $inBracket -and '$*.[\]^'.Contains($code.Text)) { [void]$builder.Append('\') }
                [void]$builder.Append($code.Text)
                $i = $code.Next
                continue
            }
            if (-not $inBracket) {
                # An escaped pair stays together: '\\n' is a backslash and an n.
                [void]$builder.Append($char).Append($Text[$i + 1])
                $i += 2
                continue
            }
        }
        [void]$builder.Append($char)
        $i++
    }
    $builder.ToString()
}

function Skip-GnuSedSpace {
    <#
    .SYNOPSIS
    Moves past blanks; with -Newlines also past newlines and semicolons.
    #>
    param([Parameter(Mandatory)][hashtable]$Parser, [switch]$Newlines)
    $text = $Parser.Text
    while ($Parser.Pos -lt $text.Length) {
        $char = $text[$Parser.Pos]
        $blank = $char -eq ' ' -or $char -eq "`t"
        if (-not ($blank -or ($Newlines -and ($char -eq "`n" -or $char -eq ';')))) { break }
        $Parser.Pos++
    }
}

function Get-GnuSedPeek {
    <#
    .SYNOPSIS
    The next script character as a string, or '' at the end.
    #>
    param([Parameter(Mandatory)][hashtable]$Parser)
    if ($Parser.Pos -ge $Parser.Text.Length) { return '' }
    [string]$Parser.Text[$Parser.Pos]
}

function Read-GnuSedNumber {
    <#
    .SYNOPSIS
    Reads digits and returns their value, or $Default when there are none.
    #>
    param([Parameter(Mandatory)][hashtable]$Parser, [long]$Default = 0)
    $digits = [regex]::Match($Parser.Text.Substring($Parser.Pos), '^\d+').Value
    if ($digits.Length -eq 0) { return $Default }
    $Parser.Pos += $digits.Length
    [long]$digits
}

function Read-GnuSedDelimited {
    <#
    .SYNOPSIS
    Reads up to the unescaped Delimiter (port of GNU's match_slash), or returns $null when it is missing.
    #>
    param([Parameter(Mandatory)][hashtable]$Parser, [Parameter(Mandatory)][string]$Delimiter, [switch]$Regex)

    $text = $Parser.Text
    $builder = New-Object System.Text.StringBuilder
    while ($Parser.Pos -lt $text.Length) {
        $char = [string]$text[$Parser.Pos]
        if ($char -ceq "`n") { return $null }
        $Parser.Pos++
        if ($char -ceq $Delimiter) { return $builder.ToString() }
        if ($char -ceq '[' -and $Regex) {
            # A delimiter inside a bracket expression does not end the pattern.
            [void]$builder.Append($char)
            foreach ($first in '^', ']') {
                if ((Get-GnuSedPeek -Parser $Parser) -ceq $first) { [void]$builder.Append($first); $Parser.Pos++ }
            }
            while ($Parser.Pos -lt $text.Length -and $text[$Parser.Pos] -ne ']' -and $text[$Parser.Pos] -ne "`n") {
                [void]$builder.Append($text[$Parser.Pos])
                $Parser.Pos++
            }
            continue
        }
        if ($char -ceq '\') {
            if ($Parser.Pos -ge $text.Length) { return $null }
            $next = [string]$text[$Parser.Pos]
            $Parser.Pos++
            if ($next -ceq 'n' -and $Regex) { [void]$builder.Append("`n"); continue }
            if ($next -cne "`n" -and ($next -cne $Delimiter -or (-not $Regex -and $next -ceq '&'))) { [void]$builder.Append('\') }
            [void]$builder.Append($next)
            continue
        }
        [void]$builder.Append($char)
    }
    $null
}

function Read-GnuSedAddress {
    <#
    .SYNOPSIS
    Parses one address, or returns $null if there is none here.
    #>
    param([Parameter(Mandatory)][hashtable]$Parser, [switch]$Second)

    $char = Get-GnuSedPeek -Parser $Parser
    if ($char -ceq '/' -or $char -ceq '\') {
        $Parser.Pos++
        $delimiter = $char
        if ($char -ceq '\') {
            $delimiter = Get-GnuSedPeek -Parser $Parser
            if ($delimiter.Length -eq 0) { throw [System.FormatException]::new('unterminated address regex') }
            $Parser.Pos++
        }
        $pattern = Read-GnuSedDelimited -Parser $Parser -Delimiter $delimiter -Regex
        if ($null -eq $pattern) { throw [System.FormatException]::new('unterminated address regex') }
        $ignore = $false
        $multi = $false
        while ($true) {
            $flag = Get-GnuSedPeek -Parser $Parser
            if ($flag -ceq 'I') { $ignore = $true } elseif ($flag -ceq 'M') { $multi = $true } else { break }
            $Parser.Pos++
        }
        return @{ Type = 'regex'; Regex = (New-GnuSedRegex -Parser $Parser -Pattern $pattern -IgnoreCase $ignore -Multiline $multi); Number = [long]0; Step = [long]0 }
    }
    if ($char -match '^\d$') {
        $number = Read-GnuSedNumber -Parser $Parser
        if ((Get-GnuSedPeek -Parser $Parser) -ceq '~') {
            $Parser.Pos++
            return @{ Type = 'step'; Regex = $null; Number = $number; Step = (Read-GnuSedNumber -Parser $Parser) }
        }
        return @{ Type = 'line'; Regex = $null; Number = $number; Step = [long]0 }
    }
    if ($char -ceq '$') {
        $Parser.Pos++
        return @{ Type = 'last'; Regex = $null; Number = [long]0; Step = [long]0 }
    }
    if ($Second -and ($char -ceq '+' -or $char -ceq '~')) {
        $Parser.Pos++
        Skip-GnuSedSpace -Parser $Parser
        return @{ Type = @{ '+' = 'plus'; '~' = 'multiple' }[$char]; Regex = $null; Number = (Read-GnuSedNumber -Parser $Parser); Step = [long]0 }
    }
    $null
}

function Read-GnuSedCommandEnd {
    <#
    .SYNOPSIS
    Checks that nothing but a command separator follows.
    #>
    param([Parameter(Mandatory)][hashtable]$Parser)
    Skip-GnuSedSpace -Parser $Parser
    $char = Get-GnuSedPeek -Parser $Parser
    if ($char.Length -eq 0 -or $char -ceq '}' -or $char -ceq '#') { return }
    $Parser.Pos++
    if ($char -cne "`n" -and $char -cne ';') { throw [System.FormatException]::new('extra characters after command') }
}

function Read-GnuSedText {
    <#
    .SYNOPSIS
    Reads the text of a, i or c, including GNU's one-line forms.
    #>
    param([Parameter(Mandatory)][hashtable]$Parser)

    Skip-GnuSedSpace -Parser $Parser
    if ((Get-GnuSedPeek -Parser $Parser).Length -eq 0) { throw [System.FormatException]::new('expected \ after `a'', `c'' or `i''') }
    if ((Get-GnuSedPeek -Parser $Parser) -ceq '\') {
        $Parser.Pos++
        $saved = $Parser.Pos
        Skip-GnuSedSpace -Parser $Parser
        if ((Get-GnuSedPeek -Parser $Parser).Length -eq 0) { return '' }
        if ((Get-GnuSedPeek -Parser $Parser) -ceq "`n") { $Parser.Pos++ } else { $Parser.Pos = $saved }
    }
    $text = $Parser.Text
    $builder = New-Object System.Text.StringBuilder
    while ($Parser.Pos -lt $text.Length) {
        $char = [string]$text[$Parser.Pos]
        $Parser.Pos++
        if ($char -ceq "`n") { break }
        if ($char -ceq '\' -and $Parser.Pos -lt $text.Length) {
            $char = [string]$text[$Parser.Pos]
            $Parser.Pos++
        }
        [void]$builder.Append($char)
    }
    $builder.Append("`n").ToString()
}

function Read-GnuSedFileName {
    <#
    .SYNOPSIS
    Reads the file name of r, R, w, W or the w flag: the rest of the line.
    #>
    param([Parameter(Mandatory)][hashtable]$Parser)
    if ($Parser.Sandbox) { throw [System.FormatException]::new('e/r/w commands disabled in sandbox mode') }
    Skip-GnuSedSpace -Parser $Parser
    $rest = $Parser.Text.Substring($Parser.Pos)
    $end = $rest.IndexOf("`n")
    if ($end -ge 0) { $rest = $rest.Substring(0, $end) }
    if ($rest.Length -eq 0) { throw [System.FormatException]::new('missing filename in r/R/w/W commands') }
    $Parser.Pos += $rest.Length
    $rest
}

function Read-GnuSedLabel {
    <#
    .SYNOPSIS
    Reads a label: up to whitespace or a semicolon.
    #>
    param([Parameter(Mandatory)][hashtable]$Parser)
    Skip-GnuSedSpace -Parser $Parser
    $label = [regex]::Match($Parser.Text.Substring($Parser.Pos), '^[^\s;]*').Value
    $Parser.Pos += $label.Length
    $label
}

function ConvertFrom-GnuSedReplacement {
    <#
    .SYNOPSIS
    Parses the replacement of s into parts: @{ Kind = text | group | case; Value }. Returns @{ Parts; MaxGroup }.
    #>
    param([AllowEmptyString()][string]$Text)

    $parts = New-Object 'System.Collections.Generic.List[hashtable]'
    $literal = New-Object System.Text.StringBuilder
    $flush = { if ($literal.Length -gt 0) { $parts.Add(@{ Kind = 'text'; Value = $literal.ToString() }); [void]$literal.Clear() } }
    $maxGroup = 0
    $i = 0
    while ($i -lt $Text.Length) {
        $char = [string]$Text[$i]
        if ($char -ceq '&') {
            . $flush
            $parts.Add(@{ Kind = 'group'; Value = 0 })
            $i++
            continue
        }
        if ($char -cne '\' -or $i + 1 -ge $Text.Length) {
            [void]$literal.Append($char)
            $i++
            continue
        }
        $next = [string]$Text[$i + 1]
        if ($next -match '^[0-9]$') {
            . $flush
            $parts.Add(@{ Kind = 'group'; Value = [int]$next })
            $maxGroup = [Math]::Max($maxGroup, [int]$next)
            $i += 2
            continue
        }
        if ('L', 'U', 'l', 'u', 'E' -ccontains $next) {
            . $flush
            $parts.Add(@{ Kind = 'case'; Value = $next })
            $i += 2
            continue
        }
        if ($next -ceq 'n') {
            [void]$literal.Append("`n")
            $i += 2
            continue
        }
        $code = Read-GnuSedEscapeCode -Text $Text -Index $i
        if ($null -ne $code) {
            [void]$literal.Append($code.Text)
            $i = $code.Next
            continue
        }
        [void]$literal.Append($next)
        $i += 2
    }
    . $flush
    @{ Parts = $parts.ToArray(); MaxGroup = $maxGroup }
}

function Read-GnuSedSubstitution {
    <#
    .SYNOPSIS
    Parses the s command after its name into Command.
    #>
    param([Parameter(Mandatory)][hashtable]$Parser, [Parameter(Mandatory)][hashtable]$Command)

    $unterminated = 'unterminated `s'' command'
    $delimiter = Get-GnuSedPeek -Parser $Parser
    if ($delimiter.Length -eq 0 -or $delimiter -ceq "`n" -or $delimiter -ceq '\') { throw [System.FormatException]::new($unterminated) }
    $Parser.Pos++
    $pattern = Read-GnuSedDelimited -Parser $Parser -Delimiter $delimiter -Regex
    if ($null -eq $pattern) { throw [System.FormatException]::new($unterminated) }
    $replacement = Read-GnuSedDelimited -Parser $Parser -Delimiter $delimiter
    if ($null -eq $replacement) { throw [System.FormatException]::new($unterminated) }

    $ignore = $false
    $multi = $false
    $done = $false
    while (-not $done) {
        $flag = Get-GnuSedPeek -Parser $Parser
        if ($flag.Length -eq 0 -or $flag -ceq '}' -or $flag -ceq '#') { break }
        $Parser.Pos++
        switch -CaseSensitive -Regex ($flag) {
            '^[iI]$' { $ignore = $true }
            '^[mM]$' { $multi = $true }
            '^p$' {
                if ($Command.Print) { throw [System.FormatException]::new('multiple `p'' options to `s'' command') }
                $Command.Print = $true
            }
            '^g$' {
                if ($Command.Global) { throw [System.FormatException]::new('multiple `g'' options to `s'' command') }
                $Command.Global = $true
            }
            '^\d$' {
                if ($Command.Number -gt 0) { throw [System.FormatException]::new('multiple number options to `s'' command') }
                $Parser.Pos--
                $Command.Number = Read-GnuSedNumber -Parser $Parser
                if ($Command.Number -eq 0) { throw [System.FormatException]::new('number option to `s'' command may not be zero') }
            }
            '^w$' { $Command.File = Read-GnuSedFileName -Parser $Parser; $done = $true }
            '^[\n;]$' { $done = $true }
            '^[ \t]$' { }
            default { throw [System.FormatException]::new('unknown option to `s''') }
        }
    }
    $Command.Regex = New-GnuSedRegex -Parser $Parser -Pattern $pattern -IgnoreCase $ignore -Multiline $multi
    $parsed = ConvertFrom-GnuSedReplacement -Text $replacement
    $Command.Parts = $parsed.Parts
    if ($null -ne $Command.Regex -and $parsed.MaxGroup -gt $Command.Regex.GetGroupNumbers().Count - 1) {
        throw [System.FormatException]::new("invalid reference \$($parsed.MaxGroup) on ``s' command's RHS")
    }
}

function Read-GnuSedTransliteration {
    <#
    .SYNOPSIS
    Parses the y command after its name into Command.Map.
    #>
    param([Parameter(Mandatory)][hashtable]$Parser, [Parameter(Mandatory)][hashtable]$Command)

    $unterminated = 'unterminated `y'' command'
    $delimiter = Get-GnuSedPeek -Parser $Parser
    if ($delimiter.Length -eq 0 -or $delimiter -ceq "`n" -or $delimiter -ceq '\') { throw [System.FormatException]::new($unterminated) }
    $Parser.Pos++
    $source = Read-GnuSedDelimited -Parser $Parser -Delimiter $delimiter
    if ($null -eq $source) { throw [System.FormatException]::new($unterminated) }
    $target = Read-GnuSedDelimited -Parser $Parser -Delimiter $delimiter
    if ($null -eq $target) { throw [System.FormatException]::new($unterminated) }
    $from = $source.Replace('\\', [string][char]1).Replace('\n', "`n").Replace([string][char]1, '\')
    $to = $target.Replace('\\', [string][char]1).Replace('\n', "`n").Replace([string][char]1, '\')
    if ($from.Length -ne $to.Length) { throw [System.FormatException]::new('strings for `y'' command are different lengths') }
    $map = New-Object 'System.Collections.Generic.Dictionary[char,char]'
    for ($i = 0; $i -lt $from.Length; $i++) { $map[$from[$i]] = $to[$i] }
    $Command.Map = $map
    Read-GnuSedCommandEnd -Parser $Parser
}

function ConvertFrom-GnuSedScript {
    <#
    .SYNOPSIS
    Compiles the script text into a flat list of commands. Throws FormatException for invalid scripts; Parser.Pos tells where.
    #>
    param([Parameter(Mandatory)][hashtable]$Parser)

    $commands = New-Object 'System.Collections.Generic.List[hashtable]'
    $labels = @{}
    $blocks = New-Object 'System.Collections.Generic.Stack[int]'
    while ($true) {
        Skip-GnuSedSpace -Parser $Parser -Newlines
        if ($Parser.Pos -ge $Parser.Text.Length) { break }
        $command = @{
            Name = ''; A1 = $null; A2 = $null; Negate = $false; Active = $false; End = [long]0; Text = ''; Label = ''; Target = -1; File = $null
            Regex = $null; Parts = @(); Print = $false; Global = $false; Number = [long]0; Map = $null; Value = [long]-1
        }
        $command.A1 = Read-GnuSedAddress -Parser $Parser
        if ($null -ne $command.A1) {
            Skip-GnuSedSpace -Parser $Parser
            if ((Get-GnuSedPeek -Parser $Parser) -ceq ',') {
                $Parser.Pos++
                Skip-GnuSedSpace -Parser $Parser
                $command.A2 = Read-GnuSedAddress -Parser $Parser -Second
                if ($null -eq $command.A2) {
                    if ($Parser.Pos -lt $Parser.Text.Length) { $Parser.Pos++ }
                    throw [System.FormatException]::new('unexpected `,''')
                }
            }
            if ($command.A1.Type -ceq 'line' -and $command.A1.Number -eq 0 -and ($null -eq $command.A2 -or $command.A2.Type -cne 'regex')) {
                if ($Parser.Pos -lt $Parser.Text.Length) { $Parser.Pos++ }
                throw [System.FormatException]::new('invalid usage of line address 0')
            }
            # 0,/re/ starts active, so the first line can already end the range.
            if ($command.A1.Type -ceq 'line' -and $command.A1.Number -eq 0) { $command.Active = $true }
        }
        Skip-GnuSedSpace -Parser $Parser
        while ((Get-GnuSedPeek -Parser $Parser) -ceq '!') {
            if ($command.Negate) {
                $Parser.Pos++
                throw [System.FormatException]::new('multiple `!''s')
            }
            $command.Negate = $true
            $Parser.Pos++
            Skip-GnuSedSpace -Parser $Parser
        }
        $name = Get-GnuSedPeek -Parser $Parser
        if ($name.Length -eq 0) { throw [System.FormatException]::new('missing command') }
        $Parser.Pos++
        $command.Name = $name
        switch -CaseSensitive -Regex ($name) {
            '^#$' {
                if ($null -ne $command.A1) { throw [System.FormatException]::new('comments don''t accept any addresses') }
                $rest = $Parser.Text.IndexOf("`n", $Parser.Pos)
                if ($rest -lt 0) { $rest = $Parser.Text.Length }
                $Parser.Pos = $rest
                $command.Name = ''
            }
            '^:$' {
                if ($null -ne $command.A1) { throw [System.FormatException]::new(': doesn''t want any addresses') }
                $label = Read-GnuSedLabel -Parser $Parser
                if ($label.Length -eq 0) { throw [System.FormatException]::new('":" lacks a label') }
                $labels[$label] = $commands.Count
            }
            '^\{$' { $blocks.Push($commands.Count) }
            '^\}$' {
                if ($blocks.Count -eq 0) { throw [System.FormatException]::new('unexpected `}''') }
                if ($null -ne $command.A1) { throw [System.FormatException]::new('} doesn''t want any addresses') }
                $commands[$blocks.Pop()].Target = $commands.Count
                Read-GnuSedCommandEnd -Parser $Parser
            }
            '^[=dDFgGhHnNpPxz]$' { Read-GnuSedCommandEnd -Parser $Parser }
            '^[aic]$' { $command.Text = Read-GnuSedText -Parser $Parser }
            '^[btT]$' { $command.Label = Read-GnuSedLabel -Parser $Parser }
            '^[lqQ]$' {
                if ($name -cne 'l' -and $null -ne $command.A2) { throw [System.FormatException]::new('command only uses one address') }
                Skip-GnuSedSpace -Parser $Parser
                $command.Value = Read-GnuSedNumber -Parser $Parser -Default -1
                Read-GnuSedCommandEnd -Parser $Parser
            }
            '^[rRwW]$' { $command.File = Read-GnuSedFileName -Parser $Parser }
            '^s$' { Read-GnuSedSubstitution -Parser $Parser -Command $command }
            '^y$' { Read-GnuSedTransliteration -Parser $Parser -Command $command }
            default { throw [System.FormatException]::new("unknown command: ``$name'") }
        }
        if ($command.Name.Length -gt 0) { $commands.Add($command) }
    }
    if ($blocks.Count -gt 0) {
        $Parser.Pos = 0
        throw [System.FormatException]::new('unmatched `{''')
    }
    foreach ($command in $commands) {
        if ('b', 't', 'T' -cnotcontains $command.Name) { continue }
        if ($command.Label.Length -eq 0) { $command.Target = $commands.Count }
        elseif ($labels.ContainsKey($command.Label)) { $command.Target = $labels[$command.Label] }
        else {
            $Parser.Located = $false
            throw [System.FormatException]::new("can't find label for jump to ``$($command.Label)'")
        }
    }
    , $commands.ToArray()
}

function Get-GnuSedErrorPrefix {
    <#
    .SYNOPSIS
    GNU's location prefix for a script error: which -e or -f piece, and where.
    #>
    param([Parameter(Mandatory)][hashtable]$Parser)

    $position = $Parser.Pos
    $expression = 0
    foreach ($piece in $Parser.Pieces) {
        if ($piece.Kind -ceq 'e') { $expression++ }
        $isLast = [object]::ReferenceEquals($piece, $Parser.Pieces[$Parser.Pieces.Count - 1])
        if ($position -le $piece.Start + $piece.Text.Length -or $isLast) {
            if ($piece.Kind -ceq 'e') { return "-e expression #$expression, char $([Math]::Min($position - $piece.Start, $piece.Text.Length)): " }
            $consumed = $piece.Text.Substring(0, [Math]::Min($position - $piece.Start, $piece.Text.Length))
            return "file $($piece.Name) line $($consumed.Split("`n").Count): "
        }
    }
}

function Open-GnuSedNextFile {
    <#
    .SYNOPSIS
    Loads the next readable input into the state. Returns $false when no input is left.
    #>
    param([Parameter(Mandatory)][hashtable]$State)

    $context = $State.Context
    while ($State.Queue.Count -gt 0) {
        $name = $State.Queue.Dequeue()
        $text = $null
        if ($name -ceq '-' -and -not $State.InPlace) { $text = [string](Get-GnuInputText -Context $context -Operand '-') }
        else {
            $path = Resolve-GnuPath -Path $name
            if ([System.IO.Directory]::Exists($path)) {
                if ($State.InPlace) { Write-GnuError -Context $context -Message "couldn't edit $($name): not a regular file" -ExitCode 4; continue }
                Write-GnuError -Context $context -Message "read error on $($name): Is a directory" -ExitCode 4
                $State.Queue.Clear()
                return $false
            }
            if (-not [System.IO.File]::Exists($path)) { Write-GnuError -Context $context -Message "can't read $($name): No such file or directory" -ExitCode 2; continue }
            $file = Read-GnuTextFile -Path $path
            $text = $file.Text
            $State.Encoding = $file.Encoding
            $State.Path = $path
        }
        $State.FileName = $name
        $State.Index = 0
        $State.LastHasEnd = $text.Length -eq 0 -or $text.EndsWith($State.Separator, [System.StringComparison]::Ordinal)
        $State.Lines = @(Split-GnuRecord -Text $text -Separator $State.Separator)
        $State.Crlf = $false
        if ($State.StripCr -and $State.Separator -ceq "`n") {
            $State.Crlf = $text.Contains("`r`n")
            for ($i = 0; $i -lt $State.Lines.Count; $i++) {
                if ($State.Lines[$i].EndsWith("`r", [System.StringComparison]::Ordinal)) { $State.Lines[$i] = $State.Lines[$i].Substring(0, $State.Lines[$i].Length - 1) }
            }
        }
        if ($State.Lines.Count -gt 0) { return $true }
    }
    $false
}

function Test-GnuSedInputLeft {
    <#
    .SYNOPSIS
    $true if another input line exists, opening later files as needed.
    #>
    param([Parameter(Mandatory)][hashtable]$State)
    if ($State.Index -lt $State.Lines.Count) { return $true }
    Open-GnuSedNextFile -State $State
}

function Add-GnuSedOutput {
    <#
    .SYNOPSIS
    Writes a line (with its terminator unless the input's last line had none) to the current output.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [AllowEmptyString()][string]$Text, [bool]$Terminated = $true)

    if ($null -eq $State.Sink) {
        $State.Output.Add($Text)
        $State.OutputEnded = $Terminated
        return
    }
    if ($State.SinkMissingEnd) { [void]$State.Sink.Append($State.LineEnd); $State.SinkMissingEnd = $false }
    [void]$State.Sink.Append($Text)
    if ($Terminated) { [void]$State.Sink.Append($State.LineEnd) } else { $State.SinkMissingEnd = $true }
}

function Add-GnuSedRawOutput {
    <#
    .SYNOPSIS
    Writes text that carries its own line ends (a, i, c, r, =).
    #>
    param([Parameter(Mandatory)][hashtable]$State, [AllowEmptyString()][string]$Text)

    foreach ($line in @(Split-GnuRecord -Text $Text)) { Add-GnuSedOutput -State $State -Text $line }
}

function Invoke-GnuSedFlushAppend {
    <#
    .SYNOPSIS
    Writes what a, r and R queued for the end of the cycle.
    #>
    param([Parameter(Mandatory)][hashtable]$State)

    foreach ($item in $State.Append) {
        if ($item.Kind -ceq 'text') { Add-GnuSedRawOutput -State $State -Text $item.Value; continue }
        $operand = $item.Value
        if ($operand -ceq '/dev/stdin') { $operand = '-' }
        elseif (-not [System.IO.File]::Exists((Resolve-GnuPath -Path $operand))) { continue }
        $content = ''
        if ($operand -ceq '-') { $content = [string](Get-GnuInputText -Context $State.Context -Operand '-') }
        else { $content = (Read-GnuTextFile -Path (Resolve-GnuPath -Path $operand)).Text }
        Add-GnuSedRawOutput -State $State -Text $content
    }
    $State.Append.Clear()
}

function Read-GnuSedPatternSpace {
    <#
    .SYNOPSIS
    Reads the next line into the pattern space (appending with -Append). Returns $false at the end of the input.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [switch]$Append)

    Invoke-GnuSedFlushAppend -State $State
    if (-not (Test-GnuSedInputLeft -State $State)) { return $false }
    $line = $State.Lines[$State.Index]
    $State.Index++
    $State.LineNumber++
    $State.Replaced = $false
    $State.Terminated = $State.Index -lt $State.Lines.Count -or $State.LastHasEnd
    if ($Append) { $State.Pattern = $State.Pattern + $State.Separator + $line } else { $State.Pattern = $line }
    $true
}

function Get-GnuSedRegex {
    <#
    .SYNOPSIS
    The regex to run: the given one, or for an empty pattern the last one used.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [AllowNull()][System.Text.RegularExpressions.Regex]$Regex)
    if ($null -ne $Regex) { $State.LastRegex = $Regex; return $Regex }
    if ($null -eq $State.LastRegex) { throw [System.InvalidOperationException]::new('no previous regular expression') }
    $State.LastRegex
}

function Test-GnuSedAddress {
    <#
    .SYNOPSIS
    $true if one address matches the current line.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][hashtable]$Address)
    $line = $State.LineNumber
    switch -CaseSensitive ($Address.Type) {
        'line' { return $line -eq $Address.Number }
        'step' {
            if ($Address.Step -le 0) { return $line -eq $Address.Number }
            return $line -ge $Address.Number -and ($line - $Address.Number) % $Address.Step -eq 0
        }
        'last' { return -not (Test-GnuSedInputLeft -State $State) }
    }
    (Get-GnuSedRegex -State $State -Regex $Address.Regex).IsMatch($State.Pattern)
}

function Test-GnuSedSelected {
    <#
    .SYNOPSIS
    $true if a command applies to the current line (GNU's match_address_p), updating the state of ranges.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][hashtable]$Command)

    if ($null -eq $Command.A1) { return $true }
    if ($null -eq $Command.A2) { return Test-GnuSedAddress -State $State -Address $Command.A1 }
    $line = $State.LineNumber
    $a2 = $Command.A2
    if ($Command.Active) {
        if ($Command.End -gt 0 -or $a2.Type -ceq 'line') {
            if ($line -ge $Command.End) { $Command.Active = $false }
            return $line -le $Command.End
        }
        if (Test-GnuSedAddress -State $State -Address $a2) { $Command.Active = $false }
        return $true
    }
    if (-not (Test-GnuSedAddress -State $State -Address $Command.A1)) { return $false }
    $Command.End = [long]0
    switch -CaseSensitive ($a2.Type) {
        'line' { $Command.End = $a2.Number }
        'plus' { $Command.End = $line + $a2.Number }
        'multiple' {
            if ($a2.Number -le 0) { $Command.End = $line }
            else { $Command.End = $line - ($line % $a2.Number) + $a2.Number }
        }
        default {
            $Command.Active = $true
            return $true
        }
    }
    $Command.Active = $Command.End -gt $line
    $true
}

function Add-GnuSedCasedText {
    <#
    .SYNOPSIS
    Appends replacement text, applying the active \U \L \u \l conversions.
    #>
    param([Parameter(Mandatory)][System.Text.StringBuilder]$Builder, [AllowEmptyString()][string]$Text, [Parameter(Mandatory)][hashtable]$Case)

    if ($Text.Length -eq 0) { return }
    $rest = $Text
    if ($Case.Once.Length -gt 0) {
        $first = $Text.Substring(0, 1)
        if ($Case.Once -ceq 'u') { $first = $first.ToUpperInvariant() } else { $first = $first.ToLowerInvariant() }
        [void]$Builder.Append($first)
        $rest = $Text.Substring(1)
        $Case.Once = ''
    }
    if ($Case.Mode -ceq 'U') { $rest = $rest.ToUpperInvariant() }
    elseif ($Case.Mode -ceq 'L') { $rest = $rest.ToLowerInvariant() }
    [void]$Builder.Append($rest)
}

function Invoke-GnuSedSubstitute {
    <#
    .SYNOPSIS
    Runs an s command on the pattern space. Returns $true if something was replaced.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][hashtable]$Command)

    $regex = Get-GnuSedRegex -State $State -Regex $Command.Regex
    $text = $State.Pattern
    $wanted = [Math]::Max([long]1, $Command.Number)
    $builder = New-Object System.Text.StringBuilder
    $copied = 0
    $position = 0
    $count = [long]0
    $previousEnd = -1
    $replaced = $false
    while ($position -le $text.Length) {
        $match = $regex.Match($text, $position)
        if (-not $match.Success) { break }
        $end = $match.Index + $match.Length
        # An empty match right after the previous match does not count (s/a*/x/g on baaac is xbxcx).
        if ($match.Length -eq 0 -and $match.Index -eq $previousEnd) {
            $position = $match.Index + 1
            continue
        }
        $previousEnd = $end
        $count++
        if ($count -ge $wanted) {
            [void]$builder.Append($text, $copied, $match.Index - $copied)
            $case = @{ Mode = ''; Once = '' }
            foreach ($part in $Command.Parts) {
                switch -CaseSensitive ($part.Kind) {
                    'text' { Add-GnuSedCasedText -Builder $builder -Text $part.Value -Case $case }
                    'group' { Add-GnuSedCasedText -Builder $builder -Text $match.Groups[$part.Value].Value -Case $case }
                    'case' {
                        if ('U', 'L' -ccontains $part.Value) { $case.Mode = $part.Value; $case.Once = '' }
                        elseif ($part.Value -ceq 'E') { $case.Mode = ''; $case.Once = '' }
                        else { $case.Once = $part.Value }
                    }
                }
            }
            $copied = $end
            $replaced = $true
            if (-not $Command.Global) { break }
        }
        if ($match.Length -eq 0) { $position = $match.Index + 1 } else { $position = $end }
    }
    if (-not $replaced) { return $false }
    [void]$builder.Append($text, $copied, $text.Length - $copied)
    $State.Pattern = $builder.ToString()
    $true
}

function Format-GnuSedVisible {
    <#
    .SYNOPSIS
    The l command's lines: escapes for special bytes, wrapped at Width, ending in '$'.
    #>
    param([AllowEmptyString()][string]$Text, [long]$Width)

    $names = @{ 7 = '\a'; 8 = '\b'; 9 = '\t'; 10 = '\n'; 11 = '\v'; 12 = '\f'; 13 = '\r'; 92 = '\\' }
    $line = New-Object System.Text.StringBuilder
    foreach ($byte in $script:GnuUtf8.GetBytes($Text)) {
        $unit = [string][char]$byte
        if ($names.ContainsKey([int]$byte)) { $unit = $names[[int]$byte] }
        elseif ($byte -lt 32 -or $byte -gt 126) { $unit = '\' + [Convert]::ToString([int]$byte, 8).PadLeft(3, '0') }
        if ($Width -gt 0 -and $line.Length + $unit.Length -gt $Width - 1) {
            $line.ToString() + '\'
            [void]$line.Clear()
        }
        [void]$line.Append($unit)
    }
    $line.ToString() + '$'
}

function Write-GnuSedFile {
    <#
    .SYNOPSIS
    The w and W commands: /dev/stdout and /dev/stderr are the real streams, anything else was opened at the start.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][string]$Name, [AllowEmptyString()][string]$Text)
    switch -CaseSensitive ($Name) {
        '/dev/stdout' { $State.Output.Add($Text) }
        '/dev/stderr' { [System.Console]::Error.WriteLine($Text) }
        default { $State.Writers[$Name].Write($Text + $State.Separator) }
    }
}

function Invoke-GnuSedCycle {
    <#
    .SYNOPSIS
    Runs the script once on the pattern space. Returns 'print' (end of script), 'next' (no autoprint), 'restart' (D) or 'quit'.
    #>
    param([Parameter(Mandatory)][hashtable]$State)

    $commands = $State.Commands
    $pc = 0
    while ($pc -lt $commands.Count) {
        $command = $commands[$pc]
        $selected = Test-GnuSedSelected -State $State -Command $command
        if ($selected -eq $command.Negate) {
            if ($command.Name -ceq '{') { $pc = $command.Target + 1 } else { $pc++ }
            continue
        }
        $next = $pc + 1
        switch -CaseSensitive ($command.Name) {
            'a' { $State.Append.Add(@{ Kind = 'text'; Value = $command.Text }) }
            'b' { $next = $command.Target }
            'c' {
                if (-not $command.Active -or $null -eq $command.A2) { Add-GnuSedRawOutput -State $State -Text $command.Text }
                return 'next'
            }
            'd' { return 'next' }
            'D' {
                $newline = $State.Pattern.IndexOf($State.Separator, [System.StringComparison]::Ordinal)
                if ($newline -lt 0) { return 'next' }
                $State.Pattern = $State.Pattern.Substring($newline + 1)
                return 'restart'
            }
            'F' { Add-GnuSedOutput -State $State -Text $State.FileName }
            'g' { $State.Pattern = $State.Hold }
            'G' { $State.Pattern = $State.Pattern + $State.Separator + $State.Hold }
            'h' { $State.Hold = $State.Pattern }
            'H' { $State.Hold = $State.Hold + $State.Separator + $State.Pattern }
            'i' { Add-GnuSedRawOutput -State $State -Text $command.Text }
            'l' {
                $width = $State.ListWidth
                if ($command.Value -ge 0) { $width = $command.Value }
                foreach ($line in @(Format-GnuSedVisible -Text $State.Pattern -Width $width)) { Add-GnuSedOutput -State $State -Text $line }
            }
            'n' {
                if (-not (Test-GnuSedInputLeft -State $State)) { return 'print' }
                if (-not $State.Quiet) { Add-GnuSedOutput -State $State -Text $State.Pattern -Terminated $State.Terminated }
                $null = Read-GnuSedPatternSpace -State $State
            }
            'N' {
                if (-not (Test-GnuSedInputLeft -State $State)) { return 'print' }
                $null = Read-GnuSedPatternSpace -State $State -Append
            }
            'p' { Add-GnuSedOutput -State $State -Text $State.Pattern -Terminated $State.Terminated }
            'P' {
                $newline = $State.Pattern.IndexOf($State.Separator, [System.StringComparison]::Ordinal)
                if ($newline -lt 0) { Add-GnuSedOutput -State $State -Text $State.Pattern } else { Add-GnuSedOutput -State $State -Text $State.Pattern.Substring(0, $newline) }
            }
            'q' {
                if ($command.Value -ge 0) { $State.Context.ExitCode = [int]$command.Value }
                if (-not $State.Quiet) { Add-GnuSedOutput -State $State -Text $State.Pattern -Terminated $State.Terminated }
                Invoke-GnuSedFlushAppend -State $State
                return 'quit'
            }
            'Q' {
                if ($command.Value -ge 0) { $State.Context.ExitCode = [int]$command.Value }
                return 'quit'
            }
            'r' { $State.Append.Add(@{ Kind = 'file'; Value = $command.File }) }
            'R' {
                $line = Get-GnuSedNextFileLine -State $State -Name $command.File
                if ($null -ne $line) { $State.Append.Add(@{ Kind = 'text'; Value = $line + "`n" }) }
            }
            's' {
                if (Invoke-GnuSedSubstitute -State $State -Command $command) {
                    $State.Replaced = $true
                    if ($command.Print) { Add-GnuSedOutput -State $State -Text $State.Pattern -Terminated $State.Terminated }
                    if ($null -ne $command.File) { Write-GnuSedFile -State $State -Name $command.File -Text $State.Pattern }
                }
            }
            't' { if ($State.Replaced) { $State.Replaced = $false; $next = $command.Target } }
            'T' { if ($State.Replaced) { $State.Replaced = $false } else { $next = $command.Target } }
            'w' { Write-GnuSedFile -State $State -Name $command.File -Text $State.Pattern }
            'W' {
                $newline = $State.Pattern.IndexOf($State.Separator, [System.StringComparison]::Ordinal)
                $first = $State.Pattern
                if ($newline -ge 0) { $first = $State.Pattern.Substring(0, $newline) }
                Write-GnuSedFile -State $State -Name $command.File -Text $first
            }
            'x' {
                $swap = $State.Pattern
                $State.Pattern = $State.Hold
                $State.Hold = $swap
            }
            'y' {
                $chars = $State.Pattern.ToCharArray()
                for ($k = 0; $k -lt $chars.Length; $k++) {
                    if ($command.Map.ContainsKey($chars[$k])) { $chars[$k] = $command.Map[$chars[$k]] }
                }
                $State.Pattern = New-Object string -ArgumentList (, $chars)
            }
            'z' { $State.Pattern = '' }
            '=' { Add-GnuSedOutput -State $State -Text ([string]$State.LineNumber) }
        }
        $pc = $next
    }
    'print'
}

function Get-GnuSedNextFileLine {
    <#
    .SYNOPSIS
    The R command: the next line of a file, or $null at its end (missing files count as empty).
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][string]$Name)

    if (-not $State.Readers.ContainsKey($Name)) {
        $lines = @()
        $path = Resolve-GnuPath -Path $Name
        if ([System.IO.File]::Exists($path)) { $lines = @(Split-GnuRecord -Text (Read-GnuTextFile -Path $path).Text) }
        $State.Readers[$Name] = @{ Lines = $lines; Index = 0 }
    }
    $reader = $State.Readers[$Name]
    if ($reader.Index -ge $reader.Lines.Count) { return $null }
    $reader.Index++
    $reader.Lines[$reader.Index - 1]
}

function Save-GnuSedInPlace {
    <#
    .SYNOPSIS
    Replaces the edited file (after a backup when a suffix was given).
    #>
    param([Parameter(Mandatory)][hashtable]$State)

    $path = $State.Path
    $suffix = $State.Suffix
    if ($suffix.Length -gt 0) {
        $leaf = [System.IO.Path]::GetFileName($path)
        $backup = $leaf + $suffix
        if ($suffix.Contains('*')) { $backup = $suffix.Replace('*', $leaf) }
        if ($backup.Contains('/')) { $backup = Resolve-GnuPath -Path $backup }
        else { $backup = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($path), $backup) }
        [System.IO.File]::Copy($path, $backup, $true)
    }
    $bytes = $State.Encoding.GetPreamble() + $State.Encoding.GetBytes($State.Sink.ToString())
    [System.IO.File]::WriteAllBytes($path, [byte[]]$bytes)
}

function Invoke-GnuSedRun {
    <#
    .SYNOPSIS
    Processes the queued input until it ends or a q command runs; emits the output lines. Sets State.Quit.
    #>
    param([Parameter(Mandatory)][hashtable]$State)

    $reuse = $false
    while ($true) {
        if (-not $reuse -and -not (Read-GnuSedPatternSpace -State $State)) { break }
        $reuse = $false
        $outcome = Invoke-GnuSedCycle -State $State
        if ($outcome -ceq 'print' -and -not $State.Quiet) { Add-GnuSedOutput -State $State -Text $State.Pattern -Terminated $State.Terminated }
        if ($outcome -ceq 'restart') {
            Invoke-GnuSedFlushAppend -State $State
            $reuse = $true
        }
        if (-not $State.Zero) {
            foreach ($line in $State.Output) { ConvertTo-GnuSedLines -Text $line }
            $State.Output.Clear()
        }
        if ($outcome -ceq 'quit') {
            $State.Quit = $true
            return
        }
    }
    Invoke-GnuSedFlushAppend -State $State
    if (-not $State.Zero) {
        foreach ($line in $State.Output) { ConvertTo-GnuSedLines -Text $line }
        $State.Output.Clear()
    }
}

function ConvertTo-GnuSedLines {
    <#
    .SYNOPSIS
    One output string per line: a pattern space can hold several lines after N or G.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'It splits one text into lines.')]
    param([AllowEmptyString()][string]$Text)
    if ($Text.Contains("`n")) { $Text.Split("`n") } else { $Text }
}

function Invoke-GnuSedEdit {
    <#
    .SYNOPSIS
    Implementation of sed.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $operands = New-Object 'System.Collections.Generic.List[string]'
    foreach ($operand in @($Context.Operands)) { $operands.Add($operand) }
    $scripts = @(Get-GnuOptionValue -Context $Context -Key 'script' -Default @())
    if ($scripts.Count -eq 0) {
        if ($operands.Count -eq 0) {
            Write-GnuUsageError -Context $Context -Message 'Usage: sed [OPTION]... {script-only-if-no-other-script} [input-file]...'
            return
        }
        $scripts = @('e:' + $operands[0])
        $operands.RemoveAt(0)
    }

    $width = [long]70
    if (Test-GnuOption -Context $Context -Key 'line-length') {
        # GNU uses atoi here: text without leading digits counts as 0.
        $digits = [regex]::Match([string](Get-GnuOptionValue -Context $Context -Key 'line-length'), '^\d+').Value
        $width = [long]0
        if ($digits.Length -gt 0) { $width = [long]$digits }
    }

    $parser = @{ Text = ''; Pos = 0; Extended = Test-GnuOption -Context $Context -Key 'extended'; Sandbox = Test-GnuOption -Context $Context -Key 'sandbox'; Pieces = @(); Located = $true }
    $pieces = New-Object 'System.Collections.Generic.List[hashtable]'
    $builder = New-Object System.Text.StringBuilder
    foreach ($script in $scripts) {
        $kind = $script.Substring(0, 1)
        $body = $script.Substring(2)
        $name = ''
        if ($kind -ceq 'f') {
            $name = $body
            $body = $null
            if ($name -ceq '-' -or [System.IO.File]::Exists((Resolve-GnuPath -Path $name))) { $body = [string](Get-GnuInputText -Context $Context -Operand $name) }
            if ($null -eq $body) { Write-GnuError -Context $Context -Message "couldn't open file $($name): No such file or directory" -ExitCode 4; return }
            $body = $body.Replace("`r`n", "`n").TrimEnd("`n")
        }
        if ($pieces.Count -gt 0) { [void]$builder.Append("`n") }
        $pieces.Add(@{ Kind = $kind; Name = $name; Text = $body; Start = $builder.Length })
        [void]$builder.Append($body)
    }
    $parser.Pieces = $pieces.ToArray()
    $parser.Text = $builder.ToString()

    try { $commands = ConvertFrom-GnuSedScript -Parser $parser }
    catch [System.FormatException] {
        # A missing label is only found after parsing: GNU reports it without a location and as a fatal error.
        if ($parser.Located) { Write-GnuError -Context $Context -Message ((Get-GnuSedErrorPrefix -Parser $parser) + $_.Exception.Message) }
        else { Write-GnuError -Context $Context -Message $_.Exception.Message -ExitCode 4 }
        return
    }

    $quiet = Test-GnuOption -Context $Context -Key 'quiet'
    if ($parser.Text.StartsWith('#n', [System.StringComparison]::Ordinal)) { $quiet = $true }
    $inPlace = Test-GnuOption -Context $Context -Key 'in-place'
    $separate = $inPlace -or (Test-GnuOption -Context $Context -Key 'separate')
    $zero = Test-GnuOption -Context $Context -Key 'null-data'
    $separator = "`n"
    if ($zero) { $separator = "`0" }
    $files = @(Expand-GnuWildcard -Operands $operands.ToArray())
    if ($files.Count -eq 0) { $files = @('-') }

    $state = @{
        Context = $Context; Commands = $commands; Queue = New-Object 'System.Collections.Generic.Queue[string]'; Lines = @(); Index = 0; FileName = '-'
        Path = ''; Encoding = $script:GnuUtf8; LastHasEnd = $true; Crlf = $false; StripCr = (Test-GnuWindows) -and -not (Test-GnuOption -Context $Context -Key 'binary')
        Separator = $separator; Zero = $zero; InPlace = $inPlace; Suffix = [string](Get-GnuOptionValue -Context $Context -Key 'in-place' -Default ''); Quiet = $quiet
        ListWidth = $width; Pattern = ''; Hold = ''; LineNumber = [long]0; Replaced = $false; Terminated = $true; LastRegex = $null; Quit = $false
        Append = New-Object 'System.Collections.Generic.List[hashtable]'; Output = New-Object 'System.Collections.Generic.List[string]'; OutputEnded = $true; Sink = $null; SinkMissingEnd = $false; LineEnd = $separator
        Writers = @{}; Readers = @{}
    }
    try {
        foreach ($command in $commands) {
            if ('w', 'W', 's' -cnotcontains $command.Name -or $null -eq $command.File) { continue }
            if ('/dev/stdout', '/dev/stderr' -ccontains $command.File -or $state.Writers.ContainsKey($command.File)) { continue }
            try { $state.Writers[$command.File] = New-Object System.IO.StreamWriter -ArgumentList (Resolve-GnuPath -Path $command.File), $false, $script:GnuUtf8 }
            catch {
                Write-GnuError -Context $Context -Message "couldn't open file $($command.File): $(Get-GnuErrorReason -Exception $_.Exception)" -ExitCode 4
                return
            }
        }
        if (-not $separate) {
            foreach ($file in $files) { $state.Queue.Enqueue($file) }
            Invoke-GnuSedRun -State $state
        }
        else {
            foreach ($file in $files) {
                $state.Queue.Enqueue($file)
                $state.LineNumber = [long]0
                $state.Lines = @()
                $state.Index = 0
                foreach ($command in $commands) { $command.Active = $null -ne $command.A1 -and $command.A1.Type -ceq 'line' -and $command.A1.Number -eq 0 }
                if ($inPlace) {
                    $state.Sink = New-Object System.Text.StringBuilder
                    $state.SinkMissingEnd = $false
                    $state.Path = ''
                }
                Invoke-GnuSedRun -State $state
                if ($inPlace -and $state.Path.Length -gt 0) {
                    # CR+LF files keep their line ends: the CRs were removed when the lines were read.
                    if ($state.Crlf) { $state.Sink = New-Object System.Text.StringBuilder -ArgumentList ($state.Sink.ToString().Replace("`n", "`r`n")) }
                    Save-GnuSedInPlace -State $state
                }
                if ($state.Quit) { break }
            }
        }
        if ($zero -and $state.Output.Count -gt 0) {
            $joined = $state.Output.ToArray() -join "`0"
            if ($state.OutputEnded) { $joined += "`0" }
            $joined
        }
    }
    catch [System.InvalidOperationException] {
        $expressions = @($scripts | Where-Object { $_.StartsWith('e:', [System.StringComparison]::Ordinal) }).Count
        Write-GnuError -Context $Context -Message "-e expression #$expressions, char 0: $($_.Exception.Message)"
    }
    finally { foreach ($writer in $state.Writers.Values) { $writer.Dispose() } }
}
