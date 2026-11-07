Register-GnuUtil @{
    Name          = 'grep'
    Category      = 'Searching and comparing'
    Synopsis      = 'Print lines that match patterns.'
    Usage         = @('grep [OPTION]... PATTERNS [FILE]...')
    Description   = @(
        'Search for PATTERNS in each FILE.',
        'Example: grep -i ''hello world'' menu.h main.c',
        'PATTERNS can contain multiple patterns separated by newlines.'
    )
    UsageExitCode = 2
    NumericOption = 'C'
    Options       = @(
        @{ Short = 'E'; Long = 'extended-regexp'; Key = 'syntax'; Value = 'extended'; Help = 'PATTERNS are extended regular expressions' }
        @{ Short = 'F'; Long = 'fixed-strings'; Key = 'syntax'; Value = 'fixed'; Help = 'PATTERNS are strings' }
        @{ Short = 'G'; Long = 'basic-regexp'; Key = 'syntax'; Value = 'basic'; Help = 'PATTERNS are basic regular expressions' }
        @{ Short = 'P'; Long = 'perl-regexp'; Key = 'syntax'; Value = 'perl'; Help = 'PATTERNS are Perl regular expressions' }
        @{ Short = 'e'; Long = 'regexp'; Arg = 'PATTERNS'; Multi = $true; Help = 'use PATTERNS for matching' }
        @{ Short = 'f'; Long = 'file'; Arg = 'FILE'; Multi = $true; Help = 'take PATTERNS from FILE' }
        @{ Short = 'i'; Long = 'ignore-case'; Key = 'case'; Value = 'ignore'; Help = 'ignore case distinctions in patterns and data' }
        @{ Long = 'no-ignore-case'; Key = 'case'; Value = 'match'; Help = 'do not ignore case distinctions (default)' }
        @{ Short = 'w'; Long = 'word-regexp'; Help = 'match only whole words' }
        @{ Short = 'x'; Long = 'line-regexp'; Help = 'match only whole lines' }
        @{ Short = 'z'; Long = 'null-data'; Help = 'a data line ends in 0 byte, not newline' }
        @{ Short = 's'; Long = 'no-messages'; Help = 'suppress error messages' }
        @{ Short = 'v'; Long = 'invert-match'; Help = 'select non-matching lines' }
        @{ Short = 'm'; Long = 'max-count'; Arg = 'NUM'; Help = 'stop after NUM selected lines' }
        @{ Short = 'b'; Long = 'byte-offset'; Help = 'print the byte offset with output lines' }
        @{ Short = 'n'; Long = 'line-number'; Help = 'print line number with output lines' }
        @{ Short = 'H'; Long = 'with-filename'; Key = 'filename'; Value = 'show'; Help = 'print file name with output lines' }
        @{ Short = 'h'; Long = 'no-filename'; Key = 'filename'; Value = 'hide'; Help = 'suppress the file name prefix on output' }
        @{ Long = 'label'; Arg = 'LABEL'; Help = 'use LABEL as the standard input file name prefix' }
        @{ Short = 'o'; Long = 'only-matching'; Help = 'show only nonempty parts of lines that match' }
        @{ Short = 'q'; Long = 'quiet'; Key = 'quiet'; Help = 'suppress all normal output' }
        @{ Long = 'silent'; Key = 'quiet'; Help = 'same as --quiet' }
        @{ Long = 'binary-files'; Arg = 'TYPE'; Help = 'assume that binary files are TYPE; TYPE is ''binary'', ''text'', or ''without-match''' }
        @{ Short = 'a'; Long = 'text'; Key = 'binary-files'; Value = 'text'; Help = 'equivalent to --binary-files=text' }
        @{ Short = 'I'; Key = 'binary-files'; Value = 'without-match'; Help = 'equivalent to --binary-files=without-match' }
        @{ Short = 'r'; Long = 'recursive'; Help = 'like --directories=recurse' }
        @{ Short = 'R'; Long = 'dereference-recursive'; Key = 'recursive'; Help = 'likewise, but follow all symlinks' }
        @{ Long = 'include'; Arg = 'GLOB'; Multi = $true; Help = 'search only files that match GLOB (a file pattern)' }
        @{ Long = 'exclude'; Arg = 'GLOB'; Multi = $true; Help = 'skip files that match GLOB' }
        @{ Long = 'exclude-dir'; Arg = 'GLOB'; Multi = $true; Help = 'skip directories that match GLOB' }
        @{ Short = 'L'; Long = 'files-without-match'; Key = 'list'; Value = 'without'; Help = 'print only names of FILEs with no selected lines' }
        @{ Short = 'l'; Long = 'files-with-matches'; Key = 'list'; Value = 'with'; Help = 'print only names of FILEs with selected lines' }
        @{ Short = 'c'; Long = 'count'; Help = 'print only a count of selected lines per FILE' }
        @{ Short = 'Z'; Long = 'null'; Help = 'print 0 byte after FILE name' }
        @{ Short = 'B'; Long = 'before-context'; Arg = 'NUM'; Help = 'print NUM lines of leading context' }
        @{ Short = 'A'; Long = 'after-context'; Arg = 'NUM'; Help = 'print NUM lines of trailing context' }
        @{ Short = 'C'; Long = 'context'; Arg = 'NUM'; Help = 'print NUM lines of output context' }
        @{ Long = 'color'; Arg = 'WHEN'; OptionalArg = $true; Help = 'use markers to highlight the matching strings; WHEN is ''always'', ''never'', or ''auto''' }
        @{ Long = 'colour'; Key = 'color'; Arg = 'WHEN'; OptionalArg = $true; Hidden = $true; Help = 'same as --color' }
    )
    Notes         = @(
        'When FILE is ''-'', read standard input.  With no FILE, read ''.'' if',
        'recursive, ''-'' otherwise.  With fewer than two FILEs, assume -h.',
        'Exit status is 0 if any line is selected, 1 otherwise;',
        'if any error occurs and -q is not given, the exit status is 2.',
        '',
        'PowerShell notes: basic and extended expressions are translated to .NET regular expressions',
        '(POSIX classes, \< \>, backreferences); -P uses .NET syntax directly. Pipeline objects are matched',
        'against the text the console would show, so "Get-Process | grep pwsh" works. Pipeline input is',
        'searched as it arrives (Get-Content -Wait | grep ... works).'
    )
}

function Invoke-GnuGrep {
    <#
    .SYNOPSIS
    GNU grep: print lines that match patterns.

    .DESCRIPTION
    Searches FILEs, directories (-r) or pipeline input for PATTERNS: basic (default), extended
    (-E), fixed strings (-F) or .NET/Perl (-P) regular expressions. Supports -i, -v, -w, -x,
    -n, -c, -l, -L, -o, -q, -m, context (-A/-B/-C/-NUM), file name control (-H/-h/-Z/--label),
    --include/--exclude/--exclude-dir, binary file handling and --color.
    Exit code 0 if something matched, 1 if not, 2 on errors.
    Enable the GNU name with: Enable-GnuUtil grep

    .EXAMPLE
    Invoke-GnuGrep -rn 'TODO' src

    .EXAMPLE
    Get-Process | Invoke-GnuGrep -i pwsh
    #>
    begin {
        $ctx = Initialize-GnuUtil -Name 'grep' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput
        if (-not $ctx.Done) {
            $grep = New-GnuGrepState -Context $ctx -ToConsole (Test-GnuConsoleOutput -Invocation $MyInvocation)
            if (-not $ctx.Done) {
                $stream = (Test-GnuStdinOnly -Context $ctx) -and -not $grep.Recursive -and -not $grep.NullData
                if ($stream) { $file = New-GnuGrepFile -Name $grep.Label }
            }
        }
    }
    process {
        if ($ctx.Done) { return }
        if ($stream) {
            foreach ($line in @(ConvertFrom-GnuPipelineItem -Context $ctx -InputObject $_)) { Step-GnuGrepLine -State $grep -File $file -Line $line }
        }
        else {
            Add-GnuPipelineInput -Context $ctx -InputObject $_
        }
    }
    end {
        if (-not $ctx.Done) {
            if ($stream) {
                foreach ($line in @(Complete-GnuPipelineInput -Context $ctx)) { Step-GnuGrepLine -State $grep -File $file -Line $line }
                Complete-GnuGrepFile -State $grep -File $file
            }
            else {
                Invoke-GnuGrepSearch -Context $ctx -State $grep
            }
            $ctx.ExitCode = 1
            if ($grep.Matched) { $ctx.ExitCode = 0 }
            if ($ctx.ErrorCount -gt 0 -and -not ($grep.Quiet -and $grep.Matched)) { $ctx.ExitCode = 2 }
        }
        Complete-GnuUtil -Context $ctx
    }
}

function New-GnuGrepState {
    <#
    .SYNOPSIS
    Validates options, compiles the patterns and returns the search state (or marks the context Done).
    #>
    param([Parameter(Mandatory)][hashtable]$Context, [bool]$ToConsole)

    # Patterns: -e / -f, or the first operand.
    $patterns = New-Object 'System.Collections.Generic.List[string]'
    $explicit = (Test-GnuOption -Context $Context -Key 'regexp') -or (Test-GnuOption -Context $Context -Key 'file')
    foreach ($value in @(Get-GnuOptionValue -Context $Context -Key 'regexp' -Default @())) { foreach ($part in $value.Split("`n")) { $patterns.Add($part) } }
    foreach ($name in @(Get-GnuOptionValue -Context $Context -Key 'file' -Default @())) {
        $text = Get-GnuInputText -Context $Context -Operand $name
        if ($null -eq $text) { $Context.ExitCode = 2; $Context.Done = $true; return }
        foreach ($part in @(Split-GnuRecord -Text $text.Replace("`r`n", "`n"))) { $patterns.Add($part) }
    }
    $operands = New-Object 'System.Collections.Generic.List[string]'
    foreach ($operand in $Context.Operands) { $operands.Add($operand) }
    if (-not $explicit) {
        if ($operands.Count -eq 0) {
            Write-GnuUsageError -Context $Context
            return
        }
        foreach ($part in $operands[0].Split("`n")) { $patterns.Add($part) }
        $operands.RemoveAt(0)
    }

    $syntax = [string](Get-GnuOptionValue -Context $Context -Key 'syntax' -Default 'basic')
    $converted = New-Object 'System.Collections.Generic.List[string]'
    foreach ($pattern in $patterns) {
        switch ($syntax) {
            'fixed' { $converted.Add([regex]::Escape($pattern)) }
            'perl' { $converted.Add($pattern) }
            default {
                $result = ConvertTo-GnuDotNetRegex -Pattern $pattern -Extended:($syntax -eq 'extended')
                if ($result.ContainsKey('Error')) {
                    Write-GnuError -Context $Context -Message $result.Error -ExitCode 2
                    $Context.Done = $true
                    return
                }
                $converted.Add($result.Regex)
            }
        }
    }

    $regex = $null
    if ($converted.Count -gt 0) {
        $joined = (@($converted | ForEach-Object { "(?:$_)" })) -join '|'
        if (Test-GnuOption -Context $Context -Key 'word-regexp') { $joined = "(?<!\w)(?:$joined)(?!\w)" }
        if (Test-GnuOption -Context $Context -Key 'line-regexp') { $joined = "^(?:$joined)$" }
        $options = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
        if ((Get-GnuOptionValue -Context $Context -Key 'case' -Default 'match') -eq 'ignore') { $options = $options -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }
        try { $regex = New-Object System.Text.RegularExpressions.Regex -ArgumentList $joined, $options }
        catch {
            # .NET messages are localized, so classify the error ourselves.
            $message = 'Invalid regular expression'
            switch (Get-GnuParenthesisBalance -Regex $joined) {
                'open' { $message = 'Unmatched ( or \(' }
                'close' { $message = 'Unmatched ) or \)' }
            }
            Write-GnuError -Context $Context -Message $message -ExitCode 2
            $Context.Done = $true
            return
        }
    }

    $numbers = @{}
    foreach ($key in @('max-count', 'after-context', 'before-context', 'context')) {
        $numbers[$key] = -1
        if (-not (Test-GnuOption -Context $Context -Key $key)) { continue }
        $text = [string](Get-GnuOptionValue -Context $Context -Key $key)
        if ($text -notmatch '^\d+$') {
            $what = 'context length argument'
            if ($key -eq 'max-count') { $what = 'max count' }
            Write-GnuError -Context $Context -Message "invalid $($what): '$text'" -ExitCode 2
            $Context.Done = $true
            return
        }
        $numbers[$key] = ConvertTo-GnuInt64 -Value (ConvertFrom-GnuSize -Text $text)
    }
    $after = $numbers['after-context']
    $before = $numbers['before-context']
    if ($after -lt 0) { $after = [Math]::Max([long]0, $numbers['context']) }
    if ($before -lt 0) { $before = [Math]::Max([long]0, $numbers['context']) }

    $binary = [string](Get-GnuOptionValue -Context $Context -Key 'binary-files' -Default 'binary')
    if (@('binary', 'text', 'without-match') -notcontains $binary) {
        Write-GnuUsageError -Context $Context -Message "invalid argument '$binary' for '--binary-files'`nValid arguments are: 'binary', 'text', 'without-match'"
        return
    }
    $color = $false
    if (Test-GnuOption -Context $Context -Key 'color') {
        $when = [string](Get-GnuOptionValue -Context $Context -Key 'color')
        switch -Regex ($when) {
            '^$|^(always|yes|force)$' { $color = $true }
            '^(never|no|none)$' { $color = $false }
            '^(auto|tty|if-tty)$' { $color = $ToConsole }
            default {
                Write-GnuUsageError -Context $Context -Message "invalid argument '$when' for '--color'`nValid arguments are: 'always', 'yes', 'force', 'never', 'no', 'none', 'auto', 'tty', 'if-tty'"
                return
            }
        }
    }

    $recursive = Test-GnuOption -Context $Context -Key 'recursive'
    if ($operands.Count -eq 0) {
        if ($recursive) { $operands.Add('.') } else { $operands.Add('-') }
    }
    $Context.Operands = [string[]]$operands.ToArray()

    $label = '(standard input)'
    if (Test-GnuOption -Context $Context -Key 'label') { $label = [string](Get-GnuOptionValue -Context $Context -Key 'label') }
    $filenameMode = [string](Get-GnuOptionValue -Context $Context -Key 'filename' -Default 'auto')
    $showNames = $filenameMode -eq 'show' -or ($filenameMode -eq 'auto' -and ($operands.Count -gt 1 -or $recursive))

    @{
        Regex         = $regex
        Invert        = Test-GnuOption -Context $Context -Key 'invert-match'
        OnlyMatching  = Test-GnuOption -Context $Context -Key 'only-matching'
        Count         = Test-GnuOption -Context $Context -Key 'count'
        List          = [string](Get-GnuOptionValue -Context $Context -Key 'list' -Default '')
        Quiet         = Test-GnuOption -Context $Context -Key 'quiet'
        LineNumbers   = Test-GnuOption -Context $Context -Key 'line-number'
        ByteOffset    = Test-GnuOption -Context $Context -Key 'byte-offset'
        Null          = Test-GnuOption -Context $Context -Key 'null'
        NullData      = Test-GnuOption -Context $Context -Key 'null-data'
        NoMessages    = Test-GnuOption -Context $Context -Key 'no-messages'
        MaxCount      = $numbers['max-count']
        After         = $after
        Before        = $before
        Binary        = $binary
        Color         = $color
        ShowNames     = $showNames
        Label         = $label
        Recursive     = $recursive
        Include       = @(Get-GnuOptionValue -Context $Context -Key 'include' -Default @())
        Exclude       = @(Get-GnuOptionValue -Context $Context -Key 'exclude' -Default @())
        ExcludeDir    = @(Get-GnuOptionValue -Context $Context -Key 'exclude-dir' -Default @())
        Matched       = $false
        Finished      = $false   # -q found a match: nothing else needs to be read
        PrintedGroups = $false   # for the '--' separator between context groups
        Context       = $Context
    }
}

function New-GnuGrepFile {
    <#
    .SYNOPSIS
    Per-input state of the line engine.
    #>
    param([Parameter(Mandatory)][string]$Name)
    @{
        Name           = $Name
        LineNumber     = [long]0
        Offset         = [long]0
        Selected       = [long]0
        Before         = New-Object 'System.Collections.Generic.Queue[object]'
        AfterRemaining = [long]0
        LastPrinted    = [long]0
        Stopped        = $false
        Binary         = $false
    }
}

function Format-GnuGrepColor {
    param([string]$Text, [string]$Code, [bool]$Color)
    if (-not $Color -or $Text.Length -eq 0) { return $Text }
    [char]27 + "[$($Code)m" + [char]27 + '[K' + $Text + [char]27 + '[m' + [char]27 + '[K'
}

function Format-GnuGrepPrefix {
    <#
    .SYNOPSIS
    'file:12:' style prefix; Separator is ':' for selected lines and '-' for context lines.
    #>
    param([hashtable]$State, [hashtable]$File, [long]$LineNumber, [long]$Offset, [string]$Separator)

    $prefix = ''
    $sep = Format-GnuGrepColor -Text $Separator -Code '36' -Color $State.Color
    if ($State.ShowNames) {
        $prefix += Format-GnuGrepColor -Text $File.Name -Code '35' -Color $State.Color
        if ($State.Null) { $prefix += [string][char]0 } else { $prefix += $sep }
    }
    if ($State.LineNumbers) { $prefix += (Format-GnuGrepColor -Text ([string]$LineNumber) -Code '32' -Color $State.Color) + $sep }
    if ($State.ByteOffset) { $prefix += (Format-GnuGrepColor -Text ([string]$Offset) -Code '32' -Color $State.Color) + $sep }
    $prefix
}

function Step-GnuGrepLine {
    <#
    .SYNOPSIS
    Processes one input line: emits selected lines, context lines and separators as needed.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][hashtable]$File, [Parameter(Mandatory)][AllowEmptyString()][string]$Line)

    if ($State.Finished -or ($File.Stopped -and $File.AfterRemaining -le 0)) { return }
    $File.LineNumber++
    $offset = $File.Offset
    $File.Offset += $script:GnuUtf8.GetByteCount($Line) + 1

    $isMatch = $false
    if ($null -ne $State.Regex) { $isMatch = $State.Regex.IsMatch($Line) }
    $selected = $isMatch -ne $State.Invert

    if ($File.Stopped) {
        # After -m NUM lines GNU still prints the trailing context, but nothing selected.
        if ($selected) { $File.AfterRemaining = 0; return }
    }

    $printLines = -not ($State.Quiet -or $State.Count -or $State.List -or $File.Binary)
    if ($selected) {
        $File.Selected++
        $State.Matched = $true
        if ($State.Quiet) { $State.Finished = $true; return }
        if ($printLines) {
            $start = $File.LineNumber - $File.Before.Count
            if (($State.Before -gt 0 -or $State.After -gt 0) -and $State.PrintedGroups -and $start -gt $File.LastPrinted + 1) {
                Format-GnuGrepColor -Text '--' -Code '36' -Color $State.Color
            }
            while ($File.Before.Count -gt 0) {
                $previous = $File.Before.Dequeue()
                (Format-GnuGrepPrefix -State $State -File $File -LineNumber $previous.Number -Offset $previous.Offset -Separator '-') + $previous.Line
            }
            $prefix = Format-GnuGrepPrefix -State $State -File $File -LineNumber $File.LineNumber -Offset $offset -Separator ':'
            if ($State.OnlyMatching) {
                if (-not $State.Invert) {
                    foreach ($match in $State.Regex.Matches($Line)) {
                        if ($match.Length -eq 0) { continue }
                        $matchPrefix = $prefix
                        if ($State.ByteOffset) { $matchPrefix = Format-GnuGrepPrefix -State $State -File $File -LineNumber $File.LineNumber -Offset ($offset + $script:GnuUtf8.GetByteCount($Line.Substring(0, $match.Index))) -Separator ':' }
                        $matchPrefix + (Format-GnuGrepColor -Text $match.Value -Code '01;31' -Color $State.Color)
                    }
                }
            }
            else {
                $text = $Line
                if ($State.Color -and -not $State.Invert -and $null -ne $State.Regex) {
                    $text = $State.Regex.Replace($Line, [System.Text.RegularExpressions.MatchEvaluator] { param($m) Format-GnuGrepColor -Text $m.Value -Code '01;31' -Color $true })
                }
                $prefix + $text
            }
            $File.LastPrinted = $File.LineNumber
            $State.PrintedGroups = $true
            $File.AfterRemaining = $State.After
        }
        if ($State.MaxCount -ge 0 -and $File.Selected -ge $State.MaxCount) { $File.Stopped = $true }
        return
    }

    if (-not $printLines) { return }
    if ($File.AfterRemaining -gt 0) {
        $File.AfterRemaining--
        (Format-GnuGrepPrefix -State $State -File $File -LineNumber $File.LineNumber -Offset $offset -Separator '-') + $Line
        $File.LastPrinted = $File.LineNumber
        return
    }
    if ($State.Before -gt 0) {
        $File.Before.Enqueue(@{ Line = $Line; Number = $File.LineNumber; Offset = $offset })
        while ($File.Before.Count -gt $State.Before) { [void]$File.Before.Dequeue() }
    }
}

function Complete-GnuGrepFile {
    <#
    .SYNOPSIS
    Emits the per-file results of -c, -l, -L and binary files after all lines were processed.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][hashtable]$File)

    $terminator = "`n"
    if ($State.Null) { $terminator = [string][char]0 }
    $name = Format-GnuGrepColor -Text $File.Name -Code '35' -Color $State.Color
    if ($State.Quiet) { return }
    if ($State.List -eq 'with') {
        if ($File.Selected -gt 0) { if ($State.Null) { $name + $terminator } else { $name } }
        return
    }
    if ($State.List -eq 'without') {
        if ($File.Selected -eq 0) { if ($State.Null) { $name + $terminator } else { $name } }
        return
    }
    if ($State.Count) {
        $text = [string]$File.Selected
        if ($State.ShowNames) {
            $separator = ':'
            if ($State.Null) { $separator = [string][char]0 }
            $text = $name + $separator + $text
        }
        $text
        return
    }
    if ($File.Binary -and $File.Selected -gt 0) { "grep: $($File.Name): binary file matches" }
}

function Test-GnuGrepGlob {
    param([string]$Name, [AllowEmptyCollection()][object[]]$Patterns)
    foreach ($pattern in $Patterns) {
        if ((New-Object System.Management.Automation.WildcardPattern -ArgumentList ([string]$pattern)).IsMatch($Name)) { return $true }
    }
    $false
}

function Search-GnuGrepFile {
    <#
    .SYNOPSIS
    Searches one file (or stdin for '-') with the line engine.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][string]$Operand, [Parameter(Mandatory)][string]$Display)

    $context = $State.Context
    $file = New-GnuGrepFile -Name $Display
    if ($Operand -eq '-') {
        $file.Name = $State.Label
        $lines = @(Read-GnuStdinLine -Context $context)
        if ($State.NullData) { $lines = @(Split-GnuRecord -Text (@($lines) -join "`n") -Separator "`0") }
    }
    else {
        $path = Resolve-GnuPath -Path $Operand
        if ([System.IO.Directory]::Exists($path)) {
            if (-not $State.NoMessages) { Write-GnuError -Context $context -Message "$($Display): Is a directory" -ExitCode 2 } else { $context.ErrorCount++ }
            return
        }
        if (-not [System.IO.File]::Exists($path)) {
            if (-not $State.NoMessages) { Write-GnuError -Context $context -Message "$($Display): No such file or directory" -ExitCode 2 } else { $context.ErrorCount++ }
            return
        }
        try { $bytes = [System.IO.File]::ReadAllBytes($path) }
        catch {
            if (-not $State.NoMessages) { Write-GnuError -Context $context -Message "$($Display): $(Get-GnuErrorReason -Exception $_.Exception)" -ExitCode 2 } else { $context.ErrorCount++ }
            return
        }
        $isBinary = -not $State.NullData -and [Array]::IndexOf($bytes, [byte]0) -ge 0
        if ($isBinary -and $State.Binary -eq 'without-match') { return }
        $file.Binary = $isBinary -and $State.Binary -eq 'binary'
        $reader = New-Object System.IO.StreamReader -ArgumentList (New-Object System.IO.MemoryStream -ArgumentList (, $bytes)), $script:GnuUtf8, $true
        $text = $reader.ReadToEnd()
        $reader.Dispose()
        if ($State.NullData) { $lines = @(Split-GnuRecord -Text $text -Separator "`0") }
        else { $lines = @(ConvertTo-GnuOutputLine -Text $text) }
    }

    $output = foreach ($line in $lines) {
        Step-GnuGrepLine -State $State -File $file -Line $line
        if ($State.Finished -or ($file.Stopped -and $file.AfterRemaining -le 0)) { break }
    }
    if ($State.NullData) { $output = @(foreach ($line in @($output)) { $line + [string][char]0 }) }
    $output
    Complete-GnuGrepFile -State $State -File $file
}

function Invoke-GnuGrepSearch {
    <#
    .SYNOPSIS
    Walks the operands (recursively with -r) and searches every file.
    #>
    param([Parameter(Mandatory)][hashtable]$Context, [Parameter(Mandatory)][hashtable]$State)

    foreach ($operand in $Context.Operands) {
        if ($State.Finished) { return }
        $path = ''
        if ($operand -ne '-') { $path = Resolve-GnuPath -Path $operand }
        if ($State.Recursive -and $operand -ne '-' -and [System.IO.Directory]::Exists($path)) {
            $stack = New-Object 'System.Collections.Generic.Stack[object]'
            $stack.Push(@{ Path = $path; Display = $operand })
            while ($stack.Count -gt 0 -and -not $State.Finished) {
                $directory = $stack.Pop()
                $entries = @([System.IO.Directory]::GetFileSystemEntries($directory.Path))
                [System.Array]::Sort($entries, [System.StringComparer]::Ordinal)
                $subdirectories = New-Object 'System.Collections.Generic.List[object]'
                foreach ($entry in $entries) {
                    $name = [System.IO.Path]::GetFileName($entry)
                    $display = Join-GnuDisplayPath -Directory $directory.Display -Leaf $name
                    if ([System.IO.Directory]::Exists($entry)) {
                        if (Test-GnuGrepGlob -Name $name -Patterns $State.ExcludeDir) { continue }
                        $subdirectories.Add(@{ Path = $entry; Display = $display })
                        continue
                    }
                    if ($State.Include.Count -gt 0 -and -not (Test-GnuGrepGlob -Name $name -Patterns $State.Include)) { continue }
                    if (Test-GnuGrepGlob -Name $name -Patterns $State.Exclude) { continue }
                    Search-GnuGrepFile -State $State -Operand $entry -Display $display
                    if ($State.Finished) { return }
                }
                for ($i = $subdirectories.Count - 1; $i -ge 0; $i--) { $stack.Push($subdirectories[$i]) }
            }
            continue
        }
        if ($operand -ne '-' -and (Test-GnuGrepGlob -Name ([System.IO.Path]::GetFileName($operand)) -Patterns $State.Exclude)) { continue }
        Search-GnuGrepFile -State $State -Operand $operand -Display $operand
    }
}
