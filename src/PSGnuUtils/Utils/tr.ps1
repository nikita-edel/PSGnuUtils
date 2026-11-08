Register-GnuUtil @{
    Name        = 'tr'
    Category    = 'Text processing'
    Synopsis    = 'Translate or delete characters.'
    Usage       = @('tr [OPTION]... STRING1 [STRING2]')
    Description = @('Translate, squeeze, and/or delete characters from standard input,', 'writing to standard output.  STRING1 and STRING2 specify arrays of', 'characters ARRAY1 and ARRAY2 that control the action.')
    Options     = @(
        @{ Short = 'c'; Long = 'complement'; Key = 'complement'; Help = 'use the complement of ARRAY1' }
        @{ Short = 'C'; Key = 'complement'; Help = 'use the complement of ARRAY1' }
        @{ Short = 'd'; Long = 'delete'; Help = 'delete characters in ARRAY1, do not translate' }
        @{ Short = 's'; Long = 'squeeze-repeats'; Help = 'replace each sequence of a repeated character that is listed in the last specified ARRAY, with a single occurrence of that character' }
        @{ Short = 't'; Long = 'truncate-set1'; Help = 'first truncate ARRAY1 to length of ARRAY2' }
    )
    Notes       = @(
        'ARRAYs are specified as strings of characters.  Most represent themselves.',
        'Interpreted sequences are:',
        '',
        '  \NNN            character with octal value NNN (1 to 3 octal digits)',
        '  \\              backslash',
        '  \a              audible BEL',
        '  \b              backspace',
        '  \f              form feed',
        '  \n              new line',
        '  \r              return',
        '  \t              horizontal tab',
        '  \v              vertical tab',
        '  CHAR1-CHAR2     all characters from CHAR1 to CHAR2 in ascending order',
        '  [CHAR*]         in ARRAY2, copies of CHAR until length of ARRAY1',
        '  [CHAR*REPEAT]   REPEAT copies of CHAR, REPEAT octal if starting with 0',
        '  [:alnum:]       all letters and digits',
        '  [:alpha:]       all letters',
        '  [:blank:]       all horizontal whitespace',
        '  [:cntrl:]       all control characters',
        '  [:digit:]       all digits',
        '  [:graph:]       all printable characters, not including space',
        '  [:lower:]       all lower case letters',
        '  [:print:]       all printable characters, including space',
        '  [:punct:]       all punctuation characters',
        '  [:space:]       all horizontal or vertical whitespace',
        '  [:upper:]       all upper case letters',
        '  [:xdigit:]      all hexadecimal digits',
        '  [=CHAR=]        all characters which are equivalent to CHAR',
        '',
        'Translation occurs if -d is not given and both STRING1 and STRING2 appear.',
        '-t may be used only when translating.  ARRAY2 is extended to length of',
        'ARRAY1 by repeating its last character as necessary.  Excess characters',
        'of ARRAY2 are ignored.  Character classes expand in unspecified order;',
        'while translating, [:lower:] and [:upper:] may be used in pairs to',
        'specify case conversion.  Squeezing occurs after translation or deletion.',
        '',
        'PowerShell note: tr reads only the pipeline or the console (no FILE). Classes',
        'are the ASCII classes of the C locale; with -c, characters above U+00FF',
        'are translated to the last character of ARRAY2.'
    )
}

function Invoke-GnuTr {
    <#
    .SYNOPSIS
    GNU tr: translate, squeeze or delete characters.

    .DESCRIPTION
    Reads the pipeline (or the console) and translates the characters of STRING1 to those of
    STRING2, deletes them (-d), squeezes repeats (-s) or works on the complement (-c).
    Sets support ranges (a-z), classes ([:upper:]), repeats ([x*4]) and escapes (\n, \033).
    Enable the GNU name with: Enable-GnuUtil tr

    .EXAMPLE
    'Hello' | Invoke-GnuTr a-z A-Z

    .EXAMPLE
    Get-Content notes.txt | Invoke-GnuTr -s ' '
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'tr' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuTranslate -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

$script:GnuTrClasses = @{
    alnum  = '0-9A-Za-z'
    alpha  = 'A-Za-z'
    blank  = "`t "
    cntrl  = "`0-$([char]31)$([char]127)"
    digit  = '0-9'
    graph  = '!-~'
    lower  = 'a-z'
    print  = ' -~'
    punct  = '!-/:-@[-`{-~'
    space  = "`t-$([char]13) "
    upper  = 'A-Z'
    xdigit = '0-9A-Fa-f'
}

function ConvertFrom-GnuTrSet {
    <#
    .SYNOPSIS
    Parses a tr STRING into elements: @{ Type = 'char'|'class'|'repeat'; ... }. Returns @{ Elements } or @{ Error }.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    # First pass: characters with escapes resolved, keeping bracket constructs whole.
    $tokens = New-Object 'System.Collections.Generic.List[hashtable]'
    $i = 0
    while ($i -lt $Text.Length) {
        $char = $Text[$i]
        if ($char -eq '[') {
            $rest = $Text.Substring($i)
            if ($rest -cmatch '^\[:(\w+):\]') {
                if (-not $script:GnuTrClasses.ContainsKey($Matches[1])) { return @{ Error = "invalid character class '$($Matches[1])'" } }
                $tokens.Add(@{ Type = 'class'; Name = $Matches[1] })
                $i += $Matches[0].Length
                continue
            }
            if ($rest -cmatch '^\[=(\\?.)=\]') {
                $tokens.Add(@{ Type = 'char'; Char = (ConvertFrom-GnuTrEscape -Text $Matches[1]).Char; Escaped = $true })
                $i += $Matches[0].Length
                continue
            }
            if ($rest -cmatch '^\[(\\[0-7]{1,3}|\\.|[^\\])\*(\d*)\]') {
                $countText = $Matches[2]
                $count = -1
                if ($countText.Length -gt 0) {
                    try {
                        if ($countText.StartsWith('0', [System.StringComparison]::Ordinal)) { $count = [System.Convert]::ToInt32($countText, 8) }
                        else { $count = [int]$countText }
                    }
                    catch { return @{ Error = "invalid repeat count '$countText' in [c*n] construct" } }
                    if ($count -eq 0) { $count = -1 }
                }
                $tokens.Add(@{ Type = 'repeat'; Char = (ConvertFrom-GnuTrEscape -Text $Matches[1]).Char; Count = $count })
                $i += $Matches[0].Length
                continue
            }
        }
        if ($char -eq '\' -and $i + 1 -lt $Text.Length) {
            $escape = ConvertFrom-GnuTrEscape -Text $Text.Substring($i)
            $tokens.Add(@{ Type = 'char'; Char = $escape.Char; Escaped = $true })
            $i += $escape.Length
            continue
        }
        $tokens.Add(@{ Type = 'char'; Char = $char; Escaped = $false })
        $i++
    }

    # Second pass: ranges CHAR1-CHAR2.
    $elements = New-Object 'System.Collections.Generic.List[hashtable]'
    for ($k = 0; $k -lt $tokens.Count; $k++) {
        $token = $tokens[$k]
        if ($token.Type -eq 'char' -and $k + 2 -lt $tokens.Count -and $tokens[$k + 1].Type -eq 'char' -and $tokens[$k + 1].Char -eq '-' -and
            -not $tokens[$k + 1].Escaped -and $tokens[$k + 2].Type -eq 'char') {
            $low = [int]$token.Char
            $high = [int]$tokens[$k + 2].Char
            if ($high -lt $low) {
                return @{ Error = "range-endpoints of '$(ConvertTo-GnuTrDisplay $token.Char)-$(ConvertTo-GnuTrDisplay $tokens[$k + 2].Char)' are in reverse collating sequence order" }
            }
            for ($code = $low; $code -le $high; $code++) { $elements.Add(@{ Type = 'char'; Char = [char]$code }) }
            $k += 2
            continue
        }
        $elements.Add($token)
    }
    @{ Elements = $elements }
}

function ConvertFrom-GnuTrEscape {
    <#
    .SYNOPSIS
    Resolves the escape at the start of Text ('\n', '\101', '\\', '\q' -> 'q'). Returns @{ Char; Length }.
    #>
    param([Parameter(Mandatory)][string]$Text)

    if ($Text.Length -lt 2 -or $Text[0] -ne '\') { return @{ Char = $Text[0]; Length = 1 } }
    if ($Text -match '^\\([0-7]{1,3})') {
        $digits = $Matches[1]
        # GNU: a 3-digit octal above \377 uses only two digits.
        if ($digits.Length -eq 3 -and [System.Convert]::ToInt32($digits, 8) -gt 255) { $digits = $digits.Substring(0, 2) }
        return @{ Char = [char][System.Convert]::ToInt32($digits, 8); Length = 1 + $digits.Length }
    }
    $map = @{ a = 7; b = 8; f = 12; n = 10; r = 13; t = 9; v = 11 }
    $next = [string]$Text[1]
    if ($map.ContainsKey($next) -and $next -cmatch '^[a-z]$') { return @{ Char = [char]$map[$next]; Length = 2 } }
    @{ Char = $Text[1]; Length = 2 }
}

function ConvertTo-GnuTrDisplay {
    <#
    .SYNOPSIS
    A character as GNU tr shows it in messages (octal escape for control characters).
    #>
    param([Parameter(Mandatory)][char]$Char)
    if ([int]$Char -lt 32 -or [int]$Char -eq 127) { return '\' + [System.Convert]::ToString([int]$Char, 8).PadLeft(3, '0') }
    [string]$Char
}

function Expand-GnuTrSet {
    <#
    .SYNOPSIS
    Expands parsed elements into a list of characters; a fill repeat ([c*]) takes FillLength minus the rest.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[hashtable]]$Elements,
        [int]$FillLength = 0
    )

    $fixed = 0
    foreach ($element in $Elements) {
        switch ($element.Type) {
            'char' { $fixed++ }
            'class' { $fixed += (Expand-GnuTrClass -Name $element.Name).Count }
            'repeat' { if ($element.Count -gt 0) { $fixed += $element.Count } }
        }
    }
    $chars = New-Object 'System.Collections.Generic.List[char]'
    foreach ($element in $Elements) {
        switch ($element.Type) {
            'char' { $chars.Add($element.Char) }
            'class' { foreach ($char in (Expand-GnuTrClass -Name $element.Name)) { $chars.Add($char) } }
            'repeat' {
                $count = $element.Count
                if ($count -lt 0) { $count = [Math]::Max(0, $FillLength - $fixed) }
                for ($n = 0; $n -lt $count; $n++) { $chars.Add($element.Char) }
            }
        }
    }
    , $chars
}

function Get-GnuTrCaseClassOffset {
    <#
    .SYNOPSIS
    Positions (in the expanded set) where a [:upper:] or [:lower:] class starts, as hashtable keys.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[hashtable]]$Elements,
        [int]$FillLength = 0
    )

    $offsets = @{}
    $prefix = New-Object 'System.Collections.Generic.List[hashtable]'
    foreach ($element in $Elements) {
        if ($element.Type -eq 'class' -and ($element.Name -eq 'upper' -or $element.Name -eq 'lower')) {
            $offsets[(Expand-GnuTrSet -Elements $prefix -FillLength $FillLength).Count] = $element.Name
        }
        $prefix.Add($element)
    }
    $offsets
}

function Expand-GnuTrClass {
    <#
    .SYNOPSIS
    The characters of a [:class:] in ascending order.
    #>
    param([Parameter(Mandatory)][string]$Name)

    $set = (ConvertFrom-GnuTrSet -Text $script:GnuTrClasses[$Name]).Elements
    $chars = New-Object 'System.Collections.Generic.List[char]'
    foreach ($element in $set) { $chars.Add($element.Char) }
    $chars.Sort()
    , $chars
}

function Invoke-GnuTranslate {
    <#
    .SYNOPSIS
    Implementation of tr.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $operands = @($Context.Operands)
    $delete = Test-GnuOption -Context $Context -Key 'delete'
    $squeeze = Test-GnuOption -Context $Context -Key 'squeeze-repeats'
    $complement = Test-GnuOption -Context $Context -Key 'complement'
    $truncate = Test-GnuOption -Context $Context -Key 'truncate-set1'

    if ($operands.Count -eq 0) { Write-GnuUsageError -Context $Context -Message 'missing operand'; return }
    $translate = -not $delete -and $operands.Count -ge 2
    $maxOperands = 2
    if ($delete -and -not $squeeze) { $maxOperands = 1 }
    if ($operands.Count -gt $maxOperands) {
        $message = "extra operand '$($operands[$maxOperands])'"
        if ($maxOperands -eq 1) { $message += "`nOnly one string may be given when deleting without squeezing repeats." }
        Write-GnuUsageError -Context $Context -Message $message
        return
    }
    if ($operands.Count -eq 1 -and -not $delete -and -not $squeeze) {
        Write-GnuUsageError -Context $Context -Message "missing operand after '$($operands[0])'`nTwo strings must be given when translating."
        return
    }
    if ($delete -and $squeeze -and $operands.Count -lt 2) {
        Write-GnuUsageError -Context $Context -Message "missing operand after '$($operands[0])'`nTwo strings must be given when both deleting and squeezing repeats."
        return
    }

    $parsed1 = ConvertFrom-GnuTrSet -Text $operands[0]
    if ($parsed1.ContainsKey('Error')) { Write-GnuError -Context $Context -Message $parsed1.Error; return }
    if (@($parsed1.Elements | Where-Object { $_.Type -eq 'repeat' }).Count -gt 0) {
        Write-GnuError -Context $Context -Message 'the [c*] repeat construct may not appear in string1'
        return
    }
    $set1 = Expand-GnuTrSet -Elements $parsed1.Elements
    $member1 = New-Object 'System.Collections.Generic.HashSet[char]'
    foreach ($char in $set1) { [void]$member1.Add($char) }
    if ($complement) {
        $set1 = New-Object 'System.Collections.Generic.List[char]'
        for ($code = 0; $code -le 255; $code++) { if (-not $member1.Contains([char]$code)) { $set1.Add([char]$code) } }
    }

    $set2 = New-Object 'System.Collections.Generic.List[char]'
    if ($operands.Count -ge 2) {
        $parsed2 = ConvertFrom-GnuTrSet -Text $operands[1]
        if ($parsed2.ContainsKey('Error')) { Write-GnuError -Context $Context -Message $parsed2.Error; return }
        if ($translate) {
            $badClass = @($parsed2.Elements | Where-Object { $_.Type -eq 'class' -and $_.Name -ne 'upper' -and $_.Name -ne 'lower' })
            if ($badClass.Count -gt 0) {
                Write-GnuError -Context $Context -Message "when translating, the only character classes that may appear in string2 are 'upper' and 'lower'"
                return
            }
        }
        $set2 = Expand-GnuTrSet -Elements $parsed2.Elements -FillLength $set1.Count
        if ($translate) {
            # [:upper:] / [:lower:] in STRING2 must line up with [:lower:] / [:upper:] in STRING1.
            $offsets1 = Get-GnuTrCaseClassOffset -Elements $parsed1.Elements
            $offsets2 = Get-GnuTrCaseClassOffset -Elements $parsed2.Elements -FillLength $set1.Count
            foreach ($offset in $offsets2.Keys) {
                if ($complement -or -not $offsets1.ContainsKey($offset)) {
                    Write-GnuError -Context $Context -Message 'misaligned [:upper:] and/or [:lower:] construct'
                    return
                }
            }
        }
    }

    $map = New-Object 'System.Collections.Generic.Dictionary[char,char]'
    if ($translate) {
        if ($set2.Count -eq 0 -and $set1.Count -gt 0 -and -not $truncate) {
            Write-GnuError -Context $Context -Message 'when not truncating set1, string2 must be non-empty'
            return
        }
        $length = $set1.Count
        if ($truncate) { $length = [Math]::Min($set1.Count, $set2.Count) }
        for ($n = 0; $n -lt $length; $n++) {
            $target = $set2[[Math]::Min($n, $set2.Count - 1)]
            $map[$set1[$n]] = $target
        }
    }

    $squeezeSet = New-Object 'System.Collections.Generic.HashSet[char]'
    $squeezeOutsideLatin1 = $false
    if ($squeeze) {
        if ($operands.Count -ge 2) { foreach ($char in $set2) { [void]$squeezeSet.Add($char) } }
        else {
            foreach ($char in $set1) { [void]$squeezeSet.Add($char) }
            $squeezeOutsideLatin1 = $complement
        }
    }
    $fallback = $null
    if ($translate -and $complement -and $set2.Count -gt 0 -and -not $truncate) { $fallback = $set2[$set2.Count - 1] }

    $text = Get-GnuInputText -Context $Context -Operand '-'
    if ($null -eq $text) { return }
    $builder = New-Object System.Text.StringBuilder
    $hasLast = $false
    $last = [char]0
    foreach ($char in $text.ToCharArray()) {
        $outside = $complement -and [int]$char -gt 255 -and -not $member1.Contains($char)
        if ($delete) {
            $inSet1 = $member1.Contains($char) -xor $complement
            if ($inSet1) { continue }
        }
        elseif ($translate) {
            if ($map.ContainsKey($char)) { $char = $map[$char] }
            elseif ($outside -and $null -ne $fallback) { $char = $fallback }
        }
        if ($squeeze -and $hasLast -and $char -ceq $last -and ($squeezeSet.Contains($char) -or ($squeezeOutsideLatin1 -and $outside))) { continue }
        [void]$builder.Append($char)
        $hasLast = $true
        $last = $char
    }
    ConvertTo-GnuOutputLine -Text $builder.ToString()
}
