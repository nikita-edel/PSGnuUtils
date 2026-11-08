Register-GnuUtil @{
    Name         = 'find'
    Category     = 'Searching and comparing'
    Synopsis     = 'Search for files in a directory hierarchy.'
    Usage        = @('find [-H] [-L] [-P] [-Olevel] [starting-point...] [expression]')
    Description  = @(
        'Default path is the current directory; default expression is -print.',
        'Expression may consist of: operators, options, tests, and actions.',
        '',
        'Operators (decreasing precedence; -and is implicit where no others are given):',
        '      ( EXPR )   ! EXPR   -not EXPR   EXPR1 -a EXPR2   EXPR1 -and EXPR2',
        '      EXPR1 -o EXPR2   EXPR1 -or EXPR2   EXPR1 , EXPR2',
        '',
        'Positional options (always true):',
        '      -daystart -follow -nowarn -regextype -warn',
        '',
        'Normal options (always true, specified before other expressions):',
        '      -depth -files0-from FILE -maxdepth LEVELS -mindepth LEVELS',
        '      -mount -noleaf -xdev -ignore_readdir_race -noignore_readdir_race',
        '',
        'Tests (N can be +N or -N or N):',
        '      -amin N -anewer FILE -atime N -cmin N -cnewer FILE -ctime N -empty -false',
        '      -ilname PATTERN -iname PATTERN -ipath PATTERN -iregex PATTERN',
        '      -iwholename PATTERN -lname PATTERN -mmin N -mtime N -name PATTERN -newer FILE',
        '      -path PATTERN -regex PATTERN -size N[bcwkMG] -true -type [bcdpflsD]',
        '      -wholename PATTERN -xtype [bcdpfls]',
        '',
        'Actions:',
        '      -delete -print0 -printf FORMAT -fprintf FILE FORMAT -print -fprint FILE -fprint0 FILE',
        '      -prune -quit',
        '      -exec COMMAND ; -exec COMMAND {} + -ok COMMAND ;',
        '      -execdir COMMAND ; -execdir COMMAND {} + -okdir COMMAND ;'
    )
    RawArguments = $true
    Notes        = @(
        'PowerShell notes: quote the ; that ends -exec (''; or `;) - unquoted it ends the PowerShell',
        'statement; ''\;'' works as well, and an unquoted {} is fine. COMMAND can be a program, a',
        'PowerShell command or a util of this module (echo, cat run the utils). Entries of a directory',
        'are visited in name order. -ctime and -cmin use the modification time (.NET has no status',
        'change time; on Linux .NET often reports the modification time as creation time), -xdev only stops at',
        'drive and mount roots. Not supported: -ls',
        '-fls -perm -user -group -uid -gid -nouser -nogroup -links -inum -samefile -newerXY -used',
        '-readable -writable -executable -context -files0-from. -printf: %n is 1, %i and %D are 0, %b and',
        '%k assume 4 KiB clusters, %Z is not supported.'
    )
}

function Invoke-GnuFind {
    <#
    .SYNOPSIS
    GNU find: search for files in a directory hierarchy.

    .DESCRIPTION
    Walks each starting point (default .) and evaluates the expression for every file: tests such
    as -name, -type, -size, -mtime, -newer, -regex, operators ( ) ! -a -o , and actions -print,
    -print0, -exec, -execdir, -ok, -delete, -prune, -quit. Without an action, matches are printed.
    Enable the GNU name with: Enable-GnuAlias find

    .EXAMPLE
    Invoke-GnuFind . -name '*.log' -mtime +7 -delete

    .EXAMPLE
    Invoke-GnuFind src -type f -name '*.ps1' -exec grep -l TODO {} +
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'find' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) { Invoke-GnuFindSearch -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function Get-GnuFindToken {
    <#
    .SYNOPSIS
    The current token without consuming it, or $null at the end.
    #>
    param([Parameter(Mandatory)][hashtable]$Parser)
    if ($Parser.Pos -ge $Parser.Tokens.Count) { return $null }
    $Parser.Tokens[$Parser.Pos]
}

function Read-GnuFindArgument {
    <#
    .SYNOPSIS
    The argument of a predicate, or GNU's error when it is missing.
    #>
    param([Parameter(Mandatory)][hashtable]$Parser, [Parameter(Mandatory)][string]$Name)
    if ($Parser.Pos -ge $Parser.Tokens.Count) { throw [System.FormatException]::new("missing argument to ``$Name'") }
    $Parser.Pos++
    $Parser.Tokens[$Parser.Pos - 1]
}

function ConvertFrom-GnuFindNumber {
    <#
    .SYNOPSIS
    A numeric test argument (+N, -N, N) as @{ Sign; Number }, or $null.
    #>
    param([AllowEmptyString()][string]$Text)
    if ($Text -notmatch '^([+-]?)(\d+(?:\.\d*)?|\.\d+)$') { return $null }
    @{ Sign = $Matches[1]; Number = [double]::Parse($Matches[2], [System.Globalization.CultureInfo]::InvariantCulture) }
}

function New-GnuFindRegex {
    <#
    .SYNOPSIS
    A -regex pattern for the current -regextype, matched against the whole path.
    #>
    param([Parameter(Mandatory)][hashtable]$Parser, [AllowEmptyString()][string]$Pattern, [bool]$IgnoreCase)

    $source = $Pattern
    $extended = $Parser.RegexType -ceq 'extended'
    if ($Parser.RegexType -ceq 'emacs') {
        # Emacs syntax: + and ? are operators, \+ \? \{ \} are plain characters; otherwise it reads like a BRE.
        $builder = New-Object System.Text.StringBuilder
        $inBracket = $false
        for ($i = 0; $i -lt $Pattern.Length; $i++) {
            $char = [string]$Pattern[$i]
            if ($inBracket) { if ($char -ceq ']') { $inBracket = $false }; [void]$builder.Append($char); continue }
            if ($char -ceq '[') { $inBracket = $true; [void]$builder.Append($char); continue }
            if ($char -ceq '\' -and $i + 1 -lt $Pattern.Length) {
                $next = [string]$Pattern[$i + 1]
                $i++
                if ('+', '?', '{', '}' -ccontains $next) { [void]$builder.Append($next) } else { [void]$builder.Append('\').Append($next) }
                continue
            }
            if ($char -ceq '+' -or $char -ceq '?') { [void]$builder.Append('\').Append($char); continue }
            [void]$builder.Append($char)
        }
        $source = $builder.ToString()
    }
    $converted = ConvertTo-GnuDotNetRegex -Pattern $source -Extended:$extended -AbsoluteEnd
    if ($converted.ContainsKey('Error')) { throw [System.FormatException]::new("failed to compile regular expression '$Pattern': $($converted.Error)") }
    $options = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant -bor [System.Text.RegularExpressions.RegexOptions]::Singleline
    if ($IgnoreCase) { $options = $options -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }
    $text = '^(?:' + $converted.Regex + ')\z'
    try { New-Object System.Text.RegularExpressions.Regex -ArgumentList $text, $options }
    catch {
        $message = 'Invalid regular expression'
        switch (Get-GnuParenthesisBalance -Regex $converted.Regex) {
            'open' { $message = 'Unmatched ( or \(' }
            'close' { $message = 'Unmatched ) or \)' }
        }
        throw [System.FormatException]::new("failed to compile regular expression '$Pattern': $message")
    }
}

function New-GnuFindPattern {
    <#
    .SYNOPSIS
    A compiled shell pattern for -name, -path and -lname.
    #>
    param([AllowEmptyString()][string]$Pattern, [bool]$IgnoreCase)
    $options = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant -bor [System.Text.RegularExpressions.RegexOptions]::Singleline
    if ($IgnoreCase) { $options = $options -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }
    New-Object System.Text.RegularExpressions.Regex -ArgumentList (ConvertTo-GnuGlobRegex -Pattern $Pattern), $options
}

function ConvertFrom-GnuFindTypeList {
    <#
    .SYNOPSIS
    The letters of a -type / -xtype argument (f,d,l), with GNU's messages for bad lists.
    #>
    param([Parameter(Mandatory)][string]$Name, [AllowEmptyString()][string]$Text)

    $valid = 'bcdpfls'
    $letters = New-Object 'System.Collections.Generic.List[string]'
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $letter = [string]$Text[$i]
        if ($letter -ceq 'D') { throw [System.FormatException]::new("$Name D is not supported because Solaris doors are not supported on the platform find was compiled on.") }
        if (-not $valid.Contains($letter)) { throw [System.FormatException]::new("Unknown argument to $($Name): $letter") }
        if ($letters.Contains($letter)) { throw [System.FormatException]::new("Duplicate file type '$letter' in the argument list to $Name.") }
        $letters.Add($letter)
        if ($i + 1 -lt $Text.Length) {
            if ($Text[$i + 1] -ne ',') { throw [System.FormatException]::new("Must separate multiple arguments to $Name using: ','") }
            $i++
            if ($i + 1 -ge $Text.Length) { throw [System.FormatException]::new("Last file type in list argument to $Name is missing, i.e., list is ending on: ','") }
        }
    }
    , $letters.ToArray()
}

function Read-GnuFindExec {
    <#
    .SYNOPSIS
    The command of -exec, -execdir, -ok and -okdir up to ; or {} +.
    #>
    param([Parameter(Mandatory)][hashtable]$Parser, [Parameter(Mandatory)][hashtable]$Node)

    $words = New-Object 'System.Collections.Generic.List[string]'
    while ($true) {
        $token = Get-GnuFindToken -Parser $Parser
        if ($null -eq $token) { throw [System.FormatException]::new("missing argument to ``$($Node.Name)'") }
        $Parser.Pos++
        if ($token -ceq ';' -or $token -ceq '\;') { break }
        if ($token -ceq '+' -and $words.Count -gt 0 -and $words[$words.Count - 1] -ceq '{}' -and $Node.Name -cnotlike '-ok*') {
            $Node.Batch = $true
            $words.RemoveAt($words.Count - 1)
            if (@($words | Where-Object { $_.Contains('{}') }).Count -gt 0) { throw [System.FormatException]::new("Only one instance of {} is supported with $($Node.Name) ... +") }
            break
        }
        $words.Add($token)
    }
    if ($words.Count -eq 0) {
        if ($Parser.Tokens[$Parser.Pos - 1] -ceq ';') { throw [System.FormatException]::new("invalid argument ``;' to ``$($Node.Name)'") }
        throw [System.FormatException]::new("missing argument to ``$($Node.Name)'")
    }
    $Node.Words = $words.ToArray()
    $Node.Pending = New-Object 'System.Collections.Generic.List[string]'
    $Node.PendingDir = $null
}

function ConvertFrom-GnuFindFormat {
    <#
    .SYNOPSIS
    Parses a -printf format into literal text and directives (@{ Text } / @{ Flags; Width; Precision; Letter; Kind }).
    Unknown directives and escapes are kept as written, with GNU's warning.
    #>
    param([Parameter(Mandatory)][hashtable]$Parser, [AllowEmptyString()][string]$Format)

    $parts = New-Object 'System.Collections.Generic.List[hashtable]'
    $literal = New-Object System.Text.StringBuilder
    $flush = { if ($literal.Length -gt 0) { $parts.Add(@{ Text = $literal.ToString() }); [void]$literal.Clear() } }
    $escapes = @{ a = 7; b = 8; f = 12; n = 10; r = 13; t = 9; v = 11 }
    $i = 0
    while ($i -lt $Format.Length) {
        $char = [string]$Format[$i]
        if ($char -ceq '\' -and $i + 1 -lt $Format.Length) {
            $next = [string]$Format[$i + 1]
            $octal = [regex]::Match($Format.Substring($i + 1), '^[0-7]{1,3}').Value
            if ($octal.Length -gt 0) { [void]$literal.Append([char]([Convert]::ToInt32($octal, 8) -band 255)); $i += 1 + $octal.Length; continue }
            if ($escapes.ContainsKey($next) -and $next -cmatch '^[a-z]$') { [void]$literal.Append([char]$escapes[$next]); $i += 2; continue }
            if ($next -ceq '\') { [void]$literal.Append('\'); $i += 2; continue }
            if ($next -ceq 'c') { . $flush; $parts.Add(@{ Stop = $true }); $i += 2; continue }
            $Parser.Warnings.Add("warning: unrecognized escape ``\$next'")
            [void]$literal.Append('\').Append($next)
            $i += 2
            continue
        }
        if ($char -cne '%' -or $i + 1 -ge $Format.Length) { [void]$literal.Append($char); $i++; continue }
        $match = [regex]::Match($Format.Substring($i + 1), '^([-+ #0]*)(\d*)(?:\.(\d*))?([ACT]?)(.?)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $kind = $match.Groups[4].Value
        $letter = $match.Groups[5].Value
        $valid = $true
        if ($kind.Length -gt 0) { $valid = $letter.Length -gt 0 -and ($letter -cmatch '^[aAbBcCdDeFgGhHIjklmMnprsStTuUVwWxXyYzZ+@]$') }
        elseif ($letter -ceq '%') { [void]$literal.Append('%'); $i += 2; continue }
        else { $valid = $letter -cmatch '^[abcdDfFgGhHiklmMnpPsStuUyY]$' -or ($letter -cmatch '^[ACT]$') }
        if (-not $valid -or $letter.Length -eq 0) {
            # GNU prints an unknown directive as written, including the character after it.
            $shown = $kind + $letter
            $Parser.Warnings.Add("warning: unrecognized format directive ``%$shown'")
            [void]$literal.Append('%').Append($shown)
            $i += 1 + $match.Groups[1].Length + $match.Groups[2].Length + $match.Groups[3].Length + [int]$match.Groups[3].Success + $shown.Length
            continue
        }
        . $flush
        $parts.Add(@{ Flags = $match.Groups[1].Value; Width = $match.Groups[2].Value; Precision = $match.Groups[3].Value; Precise = $match.Groups[3].Success; Kind = $kind; Letter = $letter })
        $i += 1 + $match.Length
    }
    . $flush
    , $parts.ToArray()
}

function Format-GnuFindTime {
    <#
    .SYNOPSIS
    A time for %a %c %t and %Ak %Ck %Tk; seconds carry GNU's ten fraction digits.
    #>
    param([Parameter(Mandatory)][datetime]$Time, [AllowEmptyString()][string]$Letter)

    $local = [System.DateTimeOffset]::new($Time.ToLocalTime())
    $fraction = (($Time.Ticks % 10000000).ToString('0000000', [System.Globalization.CultureInfo]::InvariantCulture)) + '000'
    switch -CaseSensitive ($Letter) {
        '' { return (Format-GnuDate -Time $local -Format '%a %b %e %H:%M:%S') + ".$fraction " + (Format-GnuDate -Time $local -Format '%Y') }
        '@' { return [string]$local.ToUnixTimeSeconds() + ".$fraction" }
        '+' { return (Format-GnuDate -Time $local -Format '%Y-%m-%d+%H:%M:%S') + ".$fraction" }
        'S' { return (Format-GnuDate -Time $local -Format '%S') + ".$fraction" }
        'T' { return (Format-GnuDate -Time $local -Format '%H:%M:%S') + ".$fraction" }
    }
    Format-GnuDate -Time $local -Format "%$Letter"
}

function Get-GnuFindDirective {
    <#
    .SYNOPSIS
    The text of one -printf directive for an entry.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][hashtable]$Entry, [Parameter(Mandatory)][hashtable]$Part)

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $item = Get-GnuFindItem -Entry $Entry
    $key = $Part.Letter
    if ($Part.Kind.Length -gt 0) { $key = $Part.Kind }
    if ('a', 'A', 't', 'T', 'c', 'C' -ccontains $key) {
        if ($null -eq $item) { return '' }
        $field = $key.ToLowerInvariant()
        if ($field -ceq 't') { $field = 'm' }
        $time = Get-GnuFindTime -Item $item -Field $field
        $letter = ''
        if ($Part.Kind.Length -gt 0) { $letter = $Part.Letter }
        return Format-GnuFindTime -Time $time -Letter $letter
    }
    $size = Get-GnuFindSize -Entry $Entry
    $blocks = [Math]::Ceiling($size / 4096) * 8
    if ((Get-GnuFindType -Entry $Entry -Follow $Entry.Follow) -ceq 'd' -and (Test-GnuWindows)) { $blocks = 0 }
    $trimmed = $Entry.Path.TrimEnd('/', '\')
    switch -CaseSensitive ($Part.Letter) {
        'p' { return $Entry.Path }
        'f' { return $Entry.Name }
        'h' {
            $cut = $trimmed.LastIndexOf('/')
            if ($trimmed.Length -eq 0 -and $Entry.Path.StartsWith('/', [System.StringComparison]::Ordinal)) { return '/' }
            if ($cut -lt 0) { return '.' }
            if ($cut -eq 0) { return '/' }
            return $trimmed.Substring(0, $cut)
        }
        'H' { return $Entry.Start }
        'P' {
            if ($Entry.Depth -eq 0) { return '' }
            return $Entry.Path.Substring($Entry.Start.TrimEnd('/', '\').Length + 1)
        }
        'd' { return [string]$Entry.Depth }
        's' { return ([long]$size).ToString($invariant) }
        'k' { return ([long]($blocks / 2)).ToString($invariant) }
        'b' { return ([long]$blocks).ToString($invariant) }
        'S' {
            if ($size -eq 0) { return '1' }
            return ($blocks * 512 / $size).ToString('0.######', $invariant)
        }
        'y' { return Get-GnuFindType -Entry $Entry -Follow $false }
        'Y' {
            $type = Get-GnuFindType -Entry $Entry -Follow $true
            if ($type -ceq 'l') { return 'N' }
            return $type
        }
        'l' { return [string](Get-GnuLinkTarget -Path $Entry.Full) }
        'n' { return '1' }
        'i' { return '0' }
        'D' { return '0' }
        'F' {
            $volume = Get-GnuFindVolume -State $State -Path ([System.IO.Path]::GetFullPath($Entry.Full).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar)
            foreach ($drive in [System.IO.DriveInfo]::GetDrives()) { if ($drive.Name -eq $volume -and $drive.IsReady) { return ([string]$drive.DriveFormat).ToLowerInvariant() } }
            return 'unknown'
        }
        { 'm', 'M', 'u', 'U', 'g', 'G' -ccontains $_ } {
            if ($null -eq $item) { return '' }
            if ($_ -ceq 'M') { return Get-GnuLsMode -Item $item }
            if ($_ -ceq 'm') {
                $mode = Get-GnuLsMode -Item $item
                $value = 0
                for ($k = 1; $k -lt 10; $k++) { if ($mode[$k] -ne '-') { $value += [int][Math]::Pow(2, 9 - $k) } }
                return [Convert]::ToString($value, 8)
            }
            $owner = Get-GnuLsOwner -Item $item
            switch -CaseSensitive ($_) {
                'u' { return $owner.Owner }
                'g' { return $owner.Group }
                'U' { return Get-GnuStatId -Name $owner.Owner }
            }
            return Get-GnuStatId -Name $owner.Group -Group
        }
    }
    ''
}

function Format-GnuFindPrintf {
    <#
    .SYNOPSIS
    The text -printf writes for an entry.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][hashtable]$Entry, [Parameter(Mandatory)][hashtable[]]$Parts)

    $builder = New-Object System.Text.StringBuilder
    foreach ($part in $Parts) {
        if ($part.ContainsKey('Stop')) { break }
        if ($part.ContainsKey('Text')) { [void]$builder.Append($part.Text); continue }
        $text = Get-GnuFindDirective -State $State -Entry $Entry -Part $part
        if ($part.Precise) {
            $precision = 0
            if ($part.Precision.Length -gt 0) { $precision = [int]$part.Precision }
            if ($text.Length -gt $precision) { $text = $text.Substring(0, $precision) }
        }
        if ($part.Width.Length -gt 0) {
            $width = [int]$part.Width
            if ($part.Flags.Contains('-')) { $text = $text.PadRight($width) }
            elseif ($part.Flags.Contains('0') -and $text -match '^\d+$') { $text = $text.PadLeft($width, '0') }
            else { $text = $text.PadLeft($width) }
        }
        [void]$builder.Append($text)
    }
    $builder.ToString()
}

function Get-GnuFindTime {
    <#
    .SYNOPSIS
    The access, modification or change time of an item. .NET has no change time: the later of creation and modification.
    #>
    param([Parameter(Mandatory)][System.IO.FileSystemInfo]$Item, [Parameter(Mandatory)][string]$Field)
    switch -CaseSensitive ($Field) {
        'a' { return $Item.LastAccessTimeUtc }
        'c' {
            if ($Item.CreationTimeUtc -gt $Item.LastWriteTimeUtc) { return $Item.CreationTimeUtc }
            return $Item.LastWriteTimeUtc
        }
    }
    $Item.LastWriteTimeUtc
}

function Read-GnuFindPredicate {
    <#
    .SYNOPSIS
    One test, action or option of the expression.
    #>
    param([Parameter(Mandatory)][hashtable]$Parser)

    $name = Get-GnuFindToken -Parser $Parser
    if ($name.Length -lt 2 -or $name[0] -ne '-') {
        throw [System.FormatException]::new("paths must precede expression: ``$name'")
    }
    $Parser.Pos++
    $node = @{ Kind = 'test'; Name = $name; Value = $null }
    switch -CaseSensitive -Regex ($name) {
        '^-(true|false)$' { }
        '^-(name|iname|lname|ilname)$' {
            $pattern = Read-GnuFindArgument -Parser $Parser -Name $name
            $node.Value = New-GnuFindPattern -Pattern $pattern -IgnoreCase ($name -clike '-i*')
        }
        '^-(path|ipath|wholename|iwholename)$' {
            $pattern = Read-GnuFindArgument -Parser $Parser -Name $name
            $node.Value = New-GnuFindPattern -Pattern $pattern -IgnoreCase ($name -clike '-i*')
        }
        '^-(regex|iregex)$' {
            $pattern = Read-GnuFindArgument -Parser $Parser -Name $name
            $node.Value = New-GnuFindRegex -Parser $Parser -Pattern $pattern -IgnoreCase ($name -ceq '-iregex')
        }
        '^-(type|xtype)$' {
            $text = Read-GnuFindArgument -Parser $Parser -Name $name
            if ($text.Length -eq 0) { throw [System.FormatException]::new("missing argument to ``$name'") }
            $node.Value = ConvertFrom-GnuFindTypeList -Name $name -Text $text
        }
        '^-size$' {
            $text = Read-GnuFindArgument -Parser $Parser -Name $name
            # Like GNU: a last character that is not a digit is the unit, the rest must be a number.
            if ($text.Length -gt 0 -and $text[$text.Length - 1] -notmatch '\d' -and 'bcwkMG'.IndexOf($text[$text.Length - 1]) -lt 0) {
                throw [System.FormatException]::new("invalid -size type ``$($text[$text.Length - 1])'")
            }
            if ($text -cnotmatch '^([+-]?)(\d+)([bcwkMG]?)$') { throw [System.FormatException]::new("Invalid argument ``$text' to -size") }
            $units = @{ '' = 512; b = 512; c = 1; w = 2; k = 1024; M = 1048576; G = 1073741824 }
            $node.Value = @{ Sign = $Matches[1]; Number = [long]$Matches[2]; Unit = [double]$units[$Matches[3]] }
        }
        '^-[amc](time|min)$' {
            $text = Read-GnuFindArgument -Parser $Parser -Name $name
            $number = ConvertFrom-GnuFindNumber -Text $text
            if ($null -eq $number) { throw [System.FormatException]::new("invalid argument ``$text' to ``$name'") }
            $number.Unit = 86400
            if ($name -clike '*min') { $number.Unit = 60 }
            $number.Field = $name.Substring(1, 1)
            $number.Reference = $Parser.Now
            if ($Parser.DayStart -and $number.Unit -eq 86400) { $number.Reference = $Parser.Tomorrow }
            $node.Value = $number
        }
        '^-[ac]?newer$' {
            $file = Read-GnuFindArgument -Parser $Parser -Name $name
            $path = Resolve-GnuPath -Path $file
            if (-not ([System.IO.File]::Exists($path) -or [System.IO.Directory]::Exists($path))) { throw [System.FormatException]::new("'$file': No such file or directory") }
            $node.Value = (Get-Item -LiteralPath $path -Force).LastWriteTimeUtc
        }
        '^-empty$' { }
        '^-(print|print0|prune|quit|delete)$' {
            $node.Kind = 'action'
            if ($name -ceq '-delete') { $Parser.Delete = $true; $Parser.Depth = $true }
            if ($name -ceq '-prune') { $Parser.Prune = $true }
            if ($name -ceq '-print0') { $Parser.Nul = $true }
        }
        '^-printf$' {
            $node.Kind = 'action'
            $node.Value = ConvertFrom-GnuFindFormat -Parser $Parser -Format (Read-GnuFindArgument -Parser $Parser -Name $name)
        }
        '^-fprintf$' {
            $node.Kind = 'action'
            $file = Read-GnuFindArgument -Parser $Parser -Name $name
            $format = Read-GnuFindArgument -Parser $Parser -Name $name
            try { $writer = New-Object System.IO.StreamWriter -ArgumentList (Resolve-GnuPath -Path $file), $false, $script:GnuUtf8 }
            catch { throw [System.FormatException]::new("$($file): $(Get-GnuErrorReason -Exception $_.Exception)") }
            $Parser.Writers.Add($writer)
            $node.Value = @{ Writer = $writer; Parts = (ConvertFrom-GnuFindFormat -Parser $Parser -Format $format) }
        }
        '^-fprint0?$' {
            $node.Kind = 'action'
            $file = Read-GnuFindArgument -Parser $Parser -Name $name
            $path = Resolve-GnuPath -Path $file
            try { $node.Value = New-Object System.IO.StreamWriter -ArgumentList $path, $false, $script:GnuUtf8 }
            catch { throw [System.FormatException]::new("$($file): $(Get-GnuErrorReason -Exception $_.Exception)") }
            $Parser.Writers.Add($node.Value)
        }
        '^-(exec|execdir|ok|okdir)$' {
            $node.Kind = 'action'
            $node.Batch = $false
            Read-GnuFindExec -Parser $Parser -Node $node
            $Parser.Execs.Add($node)
        }
        '^-(maxdepth|mindepth)$' {
            $text = Read-GnuFindArgument -Parser $Parser -Name $name
            if ($text -notmatch '^\+?\d+$') { throw [System.FormatException]::new("Expected a positive decimal integer argument to $name, but got '$text'") }
            $Parser[$name.Substring(1)] = [int]$text
            $node.Kind = 'option'
        }
        '^-(depth|d)$' { $Parser.Depth = $true; $Parser.ExplicitDepth = $true; $node.Kind = 'option' }
        '^-(xdev|mount)$' { $Parser.Xdev = $true; $node.Kind = 'option' }
        '^-follow$' { $Parser.Follow = 'L'; $node.Kind = 'option' }
        '^-daystart$' { $Parser.DayStart = $true; $node.Kind = 'option' }
        '^-regextype$' {
            $type = Read-GnuFindArgument -Parser $Parser -Name $name
            $types = @{
                'findutils-default' = 'emacs'; 'emacs' = 'emacs'; 'gnu-awk' = 'extended'; 'awk' = 'extended'; 'posix-awk' = 'extended'; 'egrep' = 'extended'
                'posix-egrep' = 'extended'; 'posix-extended' = 'extended'; 'ed' = 'basic'; 'grep' = 'basic'; 'posix-basic' = 'basic'; 'posix-minimal-basic' = 'basic'; 'sed' = 'basic'
            }
            if (-not $types.ContainsKey($type)) {
                throw [System.FormatException]::new("Unknown regular expression type '$type'; valid types are 'findutils-default', 'awk', 'ed', 'egrep', 'emacs', 'gnu-awk', 'grep', 'posix-awk', 'posix-basic', 'posix-egrep', 'posix-extended', 'posix-minimal-basic', 'sed'.")
            }
            $Parser.RegexType = $types[$type]
            $node.Kind = 'option'
        }
        '^-(noleaf|warn|nowarn|ignore_readdir_race|noignore_readdir_race)$' { $node.Kind = 'option' }
        '^-(ls|fls|perm|user|group|uid|gid|nouser|nogroup|links|inum|samefile|used|readable|writable|executable|context|files0-from|newer[amcBt][amcBt])$' {
            throw [System.FormatException]::new("$name is not supported by PSGnuUtils")
        }
        default { throw [System.FormatException]::new("unknown predicate ``$name'") }
    }
    $node
}

function Read-GnuFindPrimary {
    <#
    .SYNOPSIS
    ( EXPR ), ! EXPR or a predicate.
    #>
    param([Parameter(Mandatory)][hashtable]$Parser)

    $token = Get-GnuFindToken -Parser $Parser
    if ($token -ceq '!' -or $token -ceq '-not') {
        $Parser.Pos++
        $next = Get-GnuFindToken -Parser $Parser
        if ($null -eq $next -or $next -ceq ')') { throw [System.FormatException]::new("expected an expression after '$token'") }
        return @{ Kind = 'not'; Child = (Read-GnuFindPrimary -Parser $Parser) }
    }
    if ($token -ceq '(') {
        $Parser.Pos++
        if ((Get-GnuFindToken -Parser $Parser) -ceq ')') { throw [System.FormatException]::new('invalid expression; empty parentheses are not allowed.') }
        if ($null -eq (Get-GnuFindToken -Parser $Parser)) { throw [System.FormatException]::new("invalid expression; expected to find a ')' but didn't see one. Perhaps you need an extra predicate after '('") }
        $inner = Read-GnuFindComma -Parser $Parser
        if ((Get-GnuFindToken -Parser $Parser) -cne ')') { throw [System.FormatException]::new("invalid expression; expected to find a ')' but didn't see one. Perhaps you need an extra predicate after '('") }
        $Parser.Pos++
        return $inner
    }
    if ('-o', '-or', '-a', '-and', ',' -ccontains $token) { throw [System.FormatException]::new("invalid expression; you have used a binary operator '$token' with nothing before it.") }
    Read-GnuFindPredicate -Parser $Parser
}

function Read-GnuFindAnd {
    <#
    .SYNOPSIS
    EXPR -a EXPR, and adjacent expressions (implicit -a).
    #>
    param([Parameter(Mandatory)][hashtable]$Parser)

    $left = Read-GnuFindPrimary -Parser $Parser
    while ($true) {
        $token = Get-GnuFindToken -Parser $Parser
        if ($null -eq $token -or ')', '-o', '-or', ',' -ccontains $token) { return $left }
        if ($token -ceq '-a' -or $token -ceq '-and') {
            $Parser.Pos++
            $next = Get-GnuFindToken -Parser $Parser
            if ($null -eq $next) { throw [System.FormatException]::new("expected an expression after '$token'") }
            if (')', '-o', '-or', ',' -ccontains $next) { throw [System.FormatException]::new("invalid expression; you have used a binary operator '$token' with nothing after it.") }
        }
        $left = @{ Kind = 'and'; Left = $left; Right = (Read-GnuFindPrimary -Parser $Parser) }
    }
}

function Read-GnuFindOr {
    <#
    .SYNOPSIS
    EXPR -o EXPR.
    #>
    param([Parameter(Mandatory)][hashtable]$Parser)

    $left = Read-GnuFindAnd -Parser $Parser
    while ((Get-GnuFindToken -Parser $Parser) -ceq '-o' -or (Get-GnuFindToken -Parser $Parser) -ceq '-or') {
        $token = Get-GnuFindToken -Parser $Parser
        $Parser.Pos++
        $next = Get-GnuFindToken -Parser $Parser
        if ($null -eq $next) { throw [System.FormatException]::new("expected an expression after '$token'") }
        if (')', ',' -ccontains $next) { throw [System.FormatException]::new("invalid expression; you have used a binary operator '$token' with nothing after it.") }
        $left = @{ Kind = 'or'; Left = $left; Right = (Read-GnuFindAnd -Parser $Parser) }
    }
    $left
}

function Read-GnuFindComma {
    <#
    .SYNOPSIS
    EXPR , EXPR: both are evaluated, the value is the right one.
    #>
    param([Parameter(Mandatory)][hashtable]$Parser)

    $left = Read-GnuFindOr -Parser $Parser
    while ((Get-GnuFindToken -Parser $Parser) -ceq ',') {
        $Parser.Pos++
        $next = Get-GnuFindToken -Parser $Parser
        if ($null -eq $next) { throw [System.FormatException]::new("expected an expression after ','") }
        if ($next -ceq ')') { throw [System.FormatException]::new("invalid expression; you have used a binary operator ',' with nothing after it.") }
        $left = @{ Kind = 'comma'; Left = $left; Right = (Read-GnuFindOr -Parser $Parser) }
    }
    $left
}

function Test-GnuFindAction {
    <#
    .SYNOPSIS
    $true if the expression has an action that prints or runs something (then there is no default -print).
    #>
    param([Parameter(Mandatory)][hashtable]$Node)
    switch ($Node.Kind) {
        'not' { return Test-GnuFindAction -Node $Node.Child }
        { 'and', 'or', 'comma' -ccontains $_ } { return (Test-GnuFindAction -Node $Node.Left) -or (Test-GnuFindAction -Node $Node.Right) }
        'action' { return '-prune', '-quit' -cnotcontains $Node.Name }
    }
    $false
}

function Get-GnuFindType {
    <#
    .SYNOPSIS
    The type letter of an entry (f d l p s b c), following a link when Follow is set.
    #>
    param([Parameter(Mandatory)][hashtable]$Entry, [bool]$Follow)

    $key = "Type$Follow"
    if ($Entry.ContainsKey($key)) { return $Entry[$key] }
    $type = 'l'
    $isLink = $null -ne (Get-GnuLinkTarget -Path $Entry.Full)
    # A dangling link stays a link when followed (File.Exists says true for one on Unix).
    $dangling = $isLink -and $Follow -and (Get-GnuCanonicalPath -Path $Entry.Full -Require 'all').ContainsKey('Error')
    if (-not ($isLink -and -not $Follow) -and -not $dangling) {
        if ([System.IO.Directory]::Exists($Entry.Full)) { $type = 'd' }
        elseif ([System.IO.File]::Exists($Entry.Full)) {
            $type = 'f'
            if (-not $isLink) {
                $mode = Get-GnuUnixModeString -Path $Entry.Full
                if (-not [string]::IsNullOrEmpty($mode) -and 'p', 's', 'b', 'c' -ccontains [string]$mode[0]) { $type = [string]$mode[0] }
            }
        }
    }
    $Entry[$key] = $type
    $type
}

function Get-GnuFindItem {
    <#
    .SYNOPSIS
    The FileSystemInfo for size and time tests: the link itself, or its target when following.
    #>
    param([Parameter(Mandatory)][hashtable]$Entry)

    if ($Entry.ContainsKey('Item')) { return $Entry.Item }
    $item = $null
    $path = $Entry.Full
    if ($Entry.Follow -and $null -ne (Get-GnuLinkTarget -Path $path)) {
        $resolved = Get-GnuCanonicalPath -Path $path -Require 'all'
        if ($resolved.ContainsKey('Path')) { $path = $resolved.Path }
    }
    $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    $Entry.Item = $item
    $item
}

function Get-GnuFindSize {
    <#
    .SYNOPSIS
    The size -size and -empty see: a file's length, a link's target text, 4096 for directories off Windows.
    #>
    param([Parameter(Mandatory)][hashtable]$Entry)

    $type = Get-GnuFindType -Entry $Entry -Follow $Entry.Follow
    if ($type -ceq 'l') { return [double]"$(Get-GnuLinkTarget -Path $Entry.Full)".Length }
    if ($type -ceq 'd') {
        if (Test-GnuWindows) { return [double]0 }
        return [double]4096
    }
    $item = Get-GnuFindItem -Entry $Entry
    if ($null -eq $item -or $item -isnot [System.IO.FileInfo]) { return [double]0 }
    [double]$item.Length
}

function Test-GnuFindNumber {
    <#
    .SYNOPSIS
    Compares a value with +N, -N or N.
    #>
    param([Parameter(Mandatory)][hashtable]$Test, [double]$Value)
    switch ($Test.Sign) {
        '+' { return $Value -gt $Test.Number }
        '-' { return $Value -lt $Test.Number }
    }
    $Value -eq $Test.Number
}

function Invoke-GnuFindCommand {
    <#
    .SYNOPSIS
    Runs one -exec / -execdir / -ok command. Returns $true if it exited with 0.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][string[]]$Words, [AllowNull()][string]$Directory)

    Clear-GnuFindOutput -State $State
    $command = Resolve-GnuExecCommand -Name $Words[0]
    if ($null -eq $command) {
        # In GNU the child process fails, not find: the test is false and find's exit status stays.
        Write-GnuError -Context $State.Context -Message "'$($Words[0])': No such file or directory" -ExitCode 0
        return $false
    }
    $rest = @()
    if ($Words.Count -gt 1) { $rest = @($Words[1..($Words.Count - 1)]) }
    $child = $State.Context.Clone()
    $child.ExitCode = 0
    $pushed = $false
    try {
        if (-not [string]::IsNullOrEmpty($Directory)) { Push-Location -LiteralPath $Directory; $pushed = $true }
        # Collected, not written: output inside the evaluation would become the value of the expression.
        foreach ($item in @(Invoke-GnuChildCommand -Context $child -Command $command -Arguments $rest -InputObject $null)) { $State.Lines.Add($item) }
    }
    finally { if ($pushed) { Pop-Location } }
    $child.ExitCode -eq 0
}

function Invoke-GnuFindExec {
    <#
    .SYNOPSIS
    The -exec family for one entry.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][hashtable]$Node, [Parameter(Mandatory)][hashtable]$Entry)

    $inDirectory = $Node.Name -clike '*dir'
    $directory = $null
    $name = $Entry.Path
    if ($inDirectory) {
        $directory = [System.IO.Path]::GetDirectoryName($Entry.Full)
        if ([string]::IsNullOrEmpty($directory)) { $directory = $Entry.Full }
        $name = './' + [System.IO.Path]::GetFileName($Entry.Full.TrimEnd('\', '/'))
        if ($Entry.Depth -eq 0 -and [System.IO.Directory]::Exists($Entry.Full) -and $Entry.Path -match '^\.?/?$') { $directory = $Entry.Full; $name = '.' }
    }
    if ($Node.Batch) {
        if ($inDirectory -and $null -ne $Node.PendingDir -and $Node.PendingDir -cne $directory) { Send-GnuFindBatch -State $State -Node $Node }
        $Node.PendingDir = $directory
        $Node.Pending.Add($name)
        $length = 0
        foreach ($item in $Node.Pending) { $length += $item.Length + 1 }
        if ($length -gt $State.Limit) { Send-GnuFindBatch -State $State -Node $Node }
        return $true
    }
    $words = [string[]]@($Node.Words | ForEach-Object { $_.Replace('{}', $name) })
    if ($Node.Name -clike '-ok*') {
        Clear-GnuFindOutput -State $State
        if (-not (Read-GnuFindAnswer -Question "< $($Node.Words[0]) ... $name > ? ")) { return $false }
    }
    Invoke-GnuFindCommand -State $State -Words $words -Directory $directory
}

function Read-GnuFindAnswer {
    <#
    .SYNOPSIS
    The -ok prompt on standard error; $true if the answer starts with y.
    #>
    param([Parameter(Mandatory)][string]$Question)
    [System.Console]::Error.Write($Question)
    $answer = [System.Console]::In.ReadLine()
    $null -ne $answer -and $answer -match '^\s*[yY]'
}

function Send-GnuFindBatch {
    <#
    .SYNOPSIS
    Runs a collected -exec ... + command; a failure makes find exit with 1.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][hashtable]$Node)
    if ($Node.Pending.Count -eq 0) { return }
    $words = [string[]](@($Node.Words) + $Node.Pending.ToArray())
    $Node.Pending.Clear()
    if (-not (Invoke-GnuFindCommand -State $State -Words $words -Directory $Node.PendingDir)) { $State.Context.ExitCode = 1 }
}

function Add-GnuFindOutput {
    <#
    .SYNOPSIS
    Collects a path with its terminator: lines for the walk to write, NUL-terminated output as one string.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string]$Terminator)
    if (-not $State.Nul -and $State.Buffer.Length -eq 0) { $State.Lines.Add($Text); return }
    [void]$State.Buffer.Append($Text).Append($Terminator)
}

function Add-GnuFindRaw {
    <#
    .SYNOPSIS
    Collects -printf text, which carries its own line ends.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [AllowEmptyString()][string]$Text)
    [void]$State.Buffer.Append($Text)
    if (-not $State.Nul -and $State.Buffer.ToString().EndsWith("`n", [System.StringComparison]::Ordinal)) { Clear-GnuFindOutput -State $State }
}

function Write-GnuFindLine {
    <#
    .SYNOPSIS
    Writes what the last evaluation collected.
    #>
    param([Parameter(Mandatory)][hashtable]$State)
    foreach ($line in $State.Lines) { $line }
    $State.Lines.Clear()
}

function Clear-GnuFindOutput {
    <#
    .SYNOPSIS
    Moves collected NUL-terminated output to the lines, before a command adds its own output.
    #>
    param([Parameter(Mandatory)][hashtable]$State)
    if ($State.Buffer.Length -eq 0) { return }
    foreach ($line in @(ConvertTo-GnuOutputLine -Text $State.Buffer.ToString())) { $State.Lines.Add($line) }
    [void]$State.Buffer.Clear()
}

function Test-GnuFindNode {
    <#
    .SYNOPSIS
    Evaluates the expression for one entry.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][hashtable]$Node, [Parameter(Mandatory)][hashtable]$Entry)

    if ($State.Quit) { return $false }
    switch -CaseSensitive ($Node.Kind) {
        'and' { return (Test-GnuFindNode -State $State -Node $Node.Left -Entry $Entry) -and (Test-GnuFindNode -State $State -Node $Node.Right -Entry $Entry) }
        'or' { return (Test-GnuFindNode -State $State -Node $Node.Left -Entry $Entry) -or (Test-GnuFindNode -State $State -Node $Node.Right -Entry $Entry) }
        'comma' { $null = Test-GnuFindNode -State $State -Node $Node.Left -Entry $Entry; return Test-GnuFindNode -State $State -Node $Node.Right -Entry $Entry }
        'not' { return -not (Test-GnuFindNode -State $State -Node $Node.Child -Entry $Entry) }
        'option' { return $true }
    }
    $value = $Node.Value
    switch -CaseSensitive -Regex ($Node.Name) {
        '^-true$' { return $true }
        '^-false$' { return $false }
        '^-i?name$' { return $value.IsMatch($Entry.Name) }
        '^-i?(path|wholename)$' { return $value.IsMatch($Entry.Path) }
        '^-i?regex$' { return $value.IsMatch($Entry.Path) }
        '^-i?lname$' {
            $target = Get-GnuLinkTarget -Path $Entry.Full
            return $null -ne $target -and $value.IsMatch([string]$target)
        }
        '^-type$' { return $value -ccontains (Get-GnuFindType -Entry $Entry -Follow $Entry.Follow) }
        '^-xtype$' { return $value -ccontains (Get-GnuFindType -Entry $Entry -Follow (-not $Entry.Follow)) }
        '^-size$' { return Test-GnuFindNumber -Test $value -Value ([Math]::Ceiling((Get-GnuFindSize -Entry $Entry) / $value.Unit)) }
        '^-empty$' {
            $type = Get-GnuFindType -Entry $Entry -Follow $Entry.Follow
            if ($type -ceq 'd') {
                try { return @(Get-GnuFindEntryName -Path $Entry.Full).Count -eq 0 }
                catch { return $false }
            }
            return $type -ceq 'f' -and (Get-GnuFindSize -Entry $Entry) -eq 0
        }
        '^-[amc](time|min)$' {
            $item = Get-GnuFindItem -Entry $Entry
            if ($null -eq $item) { return $false }
            $time = Get-GnuFindTime -Item $item -Field $value.Field
            return Test-GnuFindNumber -Test $value -Value ([Math]::Floor(($value.Reference - $time).TotalSeconds / $value.Unit))
        }
        '^-[ac]?newer$' {
            $item = Get-GnuFindItem -Entry $Entry
            if ($null -eq $item) { return $false }
            $time = Get-GnuFindTime -Item $item -Field 'm'
            if ($Node.Name -ceq '-anewer') { $time = Get-GnuFindTime -Item $item -Field 'a' }
            if ($Node.Name -ceq '-cnewer') { $time = Get-GnuFindTime -Item $item -Field 'c' }
            return $time -gt $value
        }
        '^-print$' { Add-GnuFindOutput -State $State -Text $Entry.Path -Terminator "`n"; return $true }
        '^-print0$' { Add-GnuFindOutput -State $State -Text $Entry.Path -Terminator "`0"; return $true }
        '^-fprint$' { $value.Write($Entry.Path + "`n"); return $true }
        '^-printf$' { Add-GnuFindRaw -State $State -Text (Format-GnuFindPrintf -State $State -Entry $Entry -Parts $value); return $true }
        '^-fprintf$' { $value.Writer.Write((Format-GnuFindPrintf -State $State -Entry $Entry -Parts $value.Parts)); return $true }
        '^-fprint0$' { $value.Write($Entry.Path + "`0"); return $true }
        '^-prune$' { if (-not $State.Depth) { $State.Pruned = $true }; return $true }
        '^-quit$' { $State.Quit = $true; return $true }
        '^-delete$' { return Remove-GnuFindEntry -State $State -Entry $Entry }
        '^-(exec|execdir|ok|okdir)$' { return Invoke-GnuFindExec -State $State -Node $Node -Entry $Entry }
    }
}

function Remove-GnuFindEntry {
    <#
    .SYNOPSIS
    The -delete action. The starting point '.' is left alone, as in GNU.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][hashtable]$Entry)

    if ($Entry.Path -ceq '.') { return $true }
    try {
        $isLink = $null -ne (Get-GnuLinkTarget -Path $Entry.Full)
        if ([System.IO.Directory]::Exists($Entry.Full)) {
            if (-not $isLink -and @([System.IO.Directory]::EnumerateFileSystemEntries($Entry.Full) | Select-Object -First 1).Count -gt 0) {
                Write-GnuError -Context $State.Context -Message "cannot delete '$($Entry.Path)': Directory not empty"
                return $false
            }
            [System.IO.Directory]::Delete($Entry.Full, $false)
        }
        else {
            $attributes = [System.IO.File]::GetAttributes($Entry.Full)
            if (($attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0 -and (Test-GnuWindows)) { [System.IO.File]::SetAttributes($Entry.Full, $attributes -bxor [System.IO.FileAttributes]::ReadOnly) }
            [System.IO.File]::Delete($Entry.Full)
        }
        $true
    }
    catch {
        Write-GnuError -Context $State.Context -Message "cannot delete '$($Entry.Path)': $(Get-GnuErrorReason -Exception $_.Exception)"
        $false
    }
}

function Get-GnuFindVolume {
    <#
    .SYNOPSIS
    The drive or mount root a path is on (-xdev): the longest one that contains it.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][string]$Path)
    $best = ''
    foreach ($root in $State.Volumes) {
        if ($Path.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase) -and $root.Length -gt $best.Length) { $best = $root }
    }
    $best
}

function Get-GnuFindEntryName {
    <#
    .SYNOPSIS
    The names in a directory, in ordinal order (GNU uses the order of the file system, which differs everywhere).
    #>
    param([Parameter(Mandatory)][string]$Path)
    $names = [string[]]@([System.IO.Directory]::GetFileSystemEntries($Path) | ForEach-Object { [System.IO.Path]::GetFileName($_) })
    [Array]::Sort($names, [System.StringComparer]::Ordinal)
    $names
}

function Invoke-GnuFindWalk {
    <#
    .SYNOPSIS
    Visits one entry and, for directories, everything below it.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Full, [int]$Depth, [string]$Name)

    $follow = $State.Follow -ceq 'L' -or ($State.Follow -ceq 'H' -and $Depth -eq 0)
    $entry = @{ Path = $Path; Full = $Full; Depth = $Depth; Name = $Name; Follow = $follow; Start = $State.Start }
    $type = Get-GnuFindType -Entry $entry -Follow $follow
    $evaluate = $Depth -ge $State.MinDepth
    $State.Pruned = $false
    if ($evaluate -and -not $State.Depth) {
        $null = Test-GnuFindNode -State $State -Node $State.Expression -Entry $entry
        Write-GnuFindLine -State $State
    }
    if ($type -ceq 'd' -and -not $State.Pruned -and -not $State.Quit -and $Depth -lt $State.MaxDepth) {
        $canonical = $Full
        if ($follow) {
            $resolved = Get-GnuCanonicalPath -Path $Full -Require 'all'
            if ($resolved.ContainsKey('Path')) { $canonical = $resolved.Path }
            if ($State.Active.ContainsKey($canonical)) {
                Write-GnuError -Context $State.Context -Message "File system loop detected; '$Path' is part of the same file system loop as '$($State.Active[$canonical])'."
                return
            }
        }
        $skip = $State.Xdev -and $Depth -gt 0 -and (Get-GnuFindVolume -State $State -Path ($canonical.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar)) -cne $State.Volume
        if (-not $skip) {
            $State.Active[$canonical] = $Path
            try {
                foreach ($child in @(Get-GnuFindEntryName -Path $Full)) {
                    if ($State.Quit) { break }
                    Invoke-GnuFindWalk -State $State -Path (Join-GnuDisplayPath -Directory $Path -Leaf $child) -Full ([System.IO.Path]::Combine($Full, $child)) -Depth ($Depth + 1) -Name $child
                }
            }
            catch { Write-GnuError -Context $State.Context -Message "'$Path': $(Get-GnuErrorReason -Exception $_.Exception)" }
            finally { $State.Active.Remove($canonical) }
        }
    }
    if ($evaluate -and $State.Depth -and -not $State.Quit) {
        $null = Test-GnuFindNode -State $State -Node $State.Expression -Entry $entry
        Write-GnuFindLine -State $State
    }
}

function Invoke-GnuFindSearch {
    <#
    .SYNOPSIS
    Implementation of find.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $tokens = [string[]]@($Context.Operands)
    $position = 0
    $follow = 'P'
    while ($position -lt $tokens.Count -and ($tokens[$position] -cmatch '^-[HLP]+$' -or $tokens[$position] -cmatch '^-O\d*$')) {
        if ($tokens[$position] -cmatch '^-[HLP]+$') { $follow = [string]$tokens[$position][$tokens[$position].Length - 1] }
        $position++
    }
    if ($position -lt $tokens.Count -and $tokens[$position] -ceq '--') { $position++ }
    $starts = New-Object 'System.Collections.Generic.List[string]'
    # As in GNU, ')' and ',' are file names here: only '-', '(' and '!' start the expression.
    while ($position -lt $tokens.Count -and -not (($tokens[$position].Length -gt 1 -and $tokens[$position][0] -eq '-') -or '(', '!' -ccontains $tokens[$position])) {
        $starts.Add($tokens[$position])
        $position++
    }
    if ($starts.Count -eq 0) { $starts.Add('.') }

    $now = [System.DateTime]::UtcNow
    $parser = @{
        Tokens = [string[]]@($tokens | Select-Object -Skip $position); Pos = 0; Follow = $follow; maxdepth = [int]::MaxValue; mindepth = 0; Depth = $false; Xdev = $false
        DayStart = $false; Now = $now; Tomorrow = [System.DateTime]::Today.AddDays(1).ToUniversalTime(); RegexType = 'emacs'; ExplicitDepth = $false; Warnings = New-Object 'System.Collections.Generic.List[string]'; Delete = $false; Prune = $false; Nul = $false
        Writers = New-Object 'System.Collections.Generic.List[System.IO.StreamWriter]'; Execs = New-Object 'System.Collections.Generic.List[hashtable]'
    }
    try {
        try {
            $expression = @{ Kind = 'test'; Name = '-true'; Value = $null }
            if ($parser.Tokens.Count -gt 0) { $expression = Read-GnuFindComma -Parser $parser }
            # The parser only stops early at a ')' without its '('.
            if ($parser.Pos -lt $parser.Tokens.Count) { throw [System.FormatException]::new("invalid expression; you have too many ')'") }
            if ($parser.Delete -and $parser.Prune -and -not $parser.ExplicitDepth) {
                throw [System.FormatException]::new('The -delete action automatically turns on -depth, but -prune does nothing when -depth is in effect.  If you want to carry on anyway, just explicitly use the -depth option.')
            }
        }
        catch [System.FormatException] {
            Write-GnuError -Context $Context -Message $_.Exception.Message
            return
        }
        foreach ($warning in $parser.Warnings) { Write-GnuWarning -Context $Context -Message $warning }
        if (-not (Test-GnuFindAction -Node $expression)) { $expression = @{ Kind = 'and'; Left = $expression; Right = @{ Kind = 'action'; Name = '-print'; Value = $null } } }

        $limit = [long]131072
        if (Test-GnuWindows) { $limit = [long]32000 }
        $state = @{
            Context = $Context; Expression = $expression; Follow = $parser.Follow; MaxDepth = $parser.maxdepth; MinDepth = $parser.mindepth; Depth = $parser.Depth
            Xdev = $parser.Xdev; Volumes = @([System.IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name }); Volume = ''; Pruned = $false; Quit = $false
            Nul = $parser.Nul; Buffer = New-Object System.Text.StringBuilder; Lines = New-Object 'System.Collections.Generic.List[object]'; Active = @{}; Limit = $limit; Start = ''
        }
        foreach ($start in $starts) {
            if ($state.Quit) { break }
            $full = Resolve-GnuPath -Path $start
            $exists = [System.IO.File]::Exists($full) -or [System.IO.Directory]::Exists($full) -or $null -ne (Get-GnuLinkTarget -Path $full)
            if ([string]::IsNullOrEmpty($start) -or -not $exists) {
                Write-GnuError -Context $Context -Message "'$start': No such file or directory"
                continue
            }
            $state.Volume = Get-GnuFindVolume -State $state -Path ([System.IO.Path]::GetFullPath($full).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar)
            $name = $start
            if ($start.TrimEnd('/', '\').Length -gt 0) { $name = [System.IO.Path]::GetFileName($start.TrimEnd('/', '\')) }
            $state.Start = $start
            Invoke-GnuFindWalk -State $state -Path $start -Full $full -Depth 0 -Name $name
        }
        foreach ($node in $parser.Execs) { if ($node.Batch) { Send-GnuFindBatch -State $state -Node $node } }
        Clear-GnuFindOutput -State $state
        Write-GnuFindLine -State $state
    }
    finally { foreach ($writer in $parser.Writers) { $writer.Dispose() } }
}
