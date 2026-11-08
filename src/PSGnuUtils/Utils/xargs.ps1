Register-GnuUtil @{
    Name               = 'xargs'
    Category           = 'Searching and comparing'
    Synopsis           = 'Run COMMAND with arguments INITIAL-ARGS and more arguments read from input.'
    Usage              = @('xargs [OPTION]... COMMAND [INITIAL-ARGS]...')
    Description        = @('Run COMMAND with arguments INITIAL-ARGS and more arguments read from input.')
    StopAtFirstOperand = $true
    Options            = @(
        @{ Short = '0'; Long = 'null'; Key = 'delimiter'; Multi = $true; Value = '0:'; Help = 'items are separated by a null, not whitespace; disables quote and backslash processing and logical EOF processing' }
        @{ Short = 'a'; Long = 'arg-file'; Arg = 'FILE'; Help = 'read arguments from FILE, not standard input' }
        @{ Short = 'd'; Long = 'delimiter'; Key = 'delimiter'; Multi = $true; Prefix = 'd:'; Arg = 'CHARACTER'; Help = 'items in input stream are separated by CHARACTER, not by whitespace; disables quote and backslash processing and logical EOF processing' }
        @{ Short = 'E'; Key = 'eof'; Arg = 'END'; Help = 'set logical EOF string; if END occurs as a line of input, the rest of the input is ignored (ignored if -0 or -d was specified)' }
        @{ Short = 'e'; Long = 'eof'; Key = 'eof'; Arg = 'END'; OptionalArg = $true; Help = 'equivalent to -E END if END is specified; otherwise, there is no end-of-file string' }
        @{ Short = 'I'; Key = 'group'; Arg = 'R'; Multi = $true; Prefix = 'I:'; Help = 'same as --replace=R' }
        @{ Short = 'i'; Long = 'replace'; Key = 'group'; Arg = 'R'; OptionalArg = $true; Multi = $true; Prefix = 'i:'; Help = 'replace R in INITIAL-ARGS with names read from standard input; if R is unspecified, assume {}' }
        @{ Short = 'L'; Key = 'group'; Arg = 'MAX-LINES'; Multi = $true; Prefix = 'L:'; Help = 'use at most MAX-LINES non-blank input lines per command line' }
        @{ Short = 'l'; Long = 'max-lines'; Key = 'group'; Arg = 'MAX-LINES'; OptionalArg = $true; Multi = $true; Prefix = 'l:'; Help = 'similar to -L but defaults to at most one non-blank input line if MAX-LINES is not specified' }
        @{ Short = 'n'; Long = 'max-args'; Key = 'group'; Arg = 'MAX-ARGS'; Multi = $true; Prefix = 'n:'; Help = 'use at most MAX-ARGS arguments per command line' }
        @{ Short = 'P'; Long = 'max-procs'; Arg = 'MAX-PROCS'; Help = 'run at most MAX-PROCS processes at a time' }
        @{ Short = 'p'; Long = 'interactive'; Help = 'prompt before running commands' }
        @{ Long = 'process-slot-var'; Arg = 'VAR'; Help = 'set environment variable VAR in child processes' }
        @{ Short = 'r'; Long = 'no-run-if-empty'; Help = 'if there are no arguments, then do not run COMMAND; if this option is not given, COMMAND will be run at least once' }
        @{ Short = 's'; Long = 'max-chars'; Arg = 'MAX-CHARS'; Help = 'limit length of command line to MAX-CHARS' }
        @{ Short = 't'; Long = 'verbose'; Help = 'print commands before executing them' }
        @{ Short = 'x'; Long = 'exit'; Help = 'exit if the size (see -s) is exceeded' }
    )
    Notes              = @(
        'PowerShell notes: COMMAND can be a program, a PowerShell command or a util of this module; the GNU',
        'name of a util (echo, cat) runs the util even where PowerShell has an alias of that name. An unquoted',
        '{} works. Pipeline objects become lines, so names with spaces need -d ''\n''. -t prints to the',
        'information stream (6). -P runs programs in parallel and writes each one''s output when it ends;',
        'PowerShell commands run one at a time. -p reads the answer from standard input, not /dev/tty. On Unix an',
        'exit code from 129 to 192 counts as killed by a signal (exit code 125), because PowerShell cannot tell',
        'the two apart. -o and --show-limits are not supported.'
    )
}

function Invoke-GnuXargs {
    <#
    .SYNOPSIS
    GNU xargs: build and run command lines from input.

    .DESCRIPTION
    Reads items from the pipeline (or -a FILE) and runs COMMAND with them as arguments: as many as
    fit (-s), N at a time (-n), per line (-L), or once per input line with -I. Quoting works as in
    GNU; -0 and -d split on a single character instead. The default COMMAND is echo.
    Enable the GNU name with: Enable-GnuAlias xargs

    .EXAMPLE
    'a.txt', 'b.txt' | Invoke-GnuXargs -n 1 Invoke-GnuWc -l

    .EXAMPLE
    Get-Content urls.txt | Invoke-GnuXargs -P 4 -I '{}' curl -sO '{}'
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'xargs' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuXargsBatch -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function ConvertFrom-GnuXargsDelimiter {
    <#
    .SYNOPSIS
    The character of a -d value (one character or an escape like \n, \x41, \0): @{ Char; Error }.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    if ($Text.Length -eq 1) { return @{ Char = $Text[0]; Error = $null } }
    if ($Text.Length -lt 2 -or $Text[0] -ne '\') {
        return @{ Char = $null; Error = "Invalid input delimiter specification $($Text): the delimiter must be either a single character or an escape sequence starting with \." }
    }
    # As in GNU only the character after the backslash counts here: \nX is a newline.
    $named = 'abfnrtv\'.IndexOf($Text[1])
    if ($named -ge 0) { return @{ Char = [char]@(7, 8, 12, 10, 13, 9, 11, 92)[$named]; Error = $null } }
    $base = 8
    $digits = '01234567'
    $end = 1
    $top = '377'
    if ($Text[1] -ceq 'x') { $base = 16; $digits = '0123456789abcdefABCDEF'; $end = 2; $top = 'ff' }
    elseif ('0123456789'.IndexOf($Text[1]) -lt 0) { return @{ Char = $null; Error = "Invalid escape sequence $Text in input delimiter specification." } }
    $value = 0
    while ($end -lt $Text.Length -and $digits.IndexOf($Text[$end]) -ge 0) {
        $value = [Math]::Min($value * $base + [Convert]::ToInt32([string]$Text[$end], 16), 65536)
        $end++
    }
    if ($value -gt 255) { return @{ Char = $null; Error = "Invalid escape sequence $Text in input delimiter specification; character values must not exceed $top." } }
    if ($end -lt $Text.Length) { return @{ Char = $null; Error = "Invalid escape sequence $Text in input delimiter specification; trailing characters $($Text.Substring($end)) not recognised." } }
    @{ Char = [char]$value; Error = $null }
}

function Read-GnuXargsItem {
    <#
    .SYNOPSIS
    Splits input the way GNU's read_line does. Returns @{ Items = @{ Text; Lines }[]; Error; Nul }.
    .PARAMETER Whole
    -I mode: blanks inside a line do not end an item.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [AllowNull()][string]$Eof, [switch]$Whole)

    $items = New-Object 'System.Collections.Generic.List[hashtable]'
    $result = @{ Items = $items; Error = $null; Nul = $false }
    $word = New-Object System.Text.StringBuilder
    $state = 'space'
    $quote = [char]0
    $seen = $false
    $lines = 0
    $previous = [char]0
    # A [string] parameter turns $null into '', so an empty END also means: no end-of-file string.
    $hasEof = -not [string]::IsNullOrEmpty($Eof)
    $finish = {
        # An argument cannot hold a NUL: it ends there.
        $value = $word.ToString()
        $cut = $value.IndexOf([char]0)
        if ($cut -ge 0) { $value = $value.Substring(0, $cut); $result.Nul = $true }
        if ($hasEof -and $value -ceq $Eof) { return $false }
        $items.Add(@{ Text = $value; Lines = $lines })
        $true
    }
    foreach ($char in $Text.ToCharArray()) {
        $blank = $char -eq ' ' -or $char -eq "`t"
        $space = $blank -or $char -eq "`n" -or $char -eq "`r" -or $char -eq [char]12 -or $char -eq [char]11
        if ($state -ceq 'space') {
            if ($space) { continue }
            $state = 'normal'
        }
        if ($state -ceq 'quote') {
            if ($char -eq "`n") { $result.Error = $quote; return $result }
            if ($char -eq $quote) { $state = 'normal'; $seen = $true } else { [void]$word.Append($char) }
            continue
        }
        if ($state -ceq 'backslash') {
            [void]$word.Append($char)
            $seen = $true
            $state = 'normal'
            continue
        }
        if ($char -eq "`n") {
            # A line that ends in a blank continues on the next line.
            if ($previous -ne ' ' -and $previous -ne "`t") { $lines++ }
            if (-not (& $finish)) { return $result }
            [void]$word.Clear()
            $seen = $false
            $lines = 0
            $state = 'space'
            $previous = $char
            continue
        }
        if ($space -and -not $Whole) {
            if (-not (& $finish)) { return $result }
            [void]$word.Clear()
            $seen = $false
            $lines = 0
            $state = 'space'
            $previous = $char
            continue
        }
        if ($char -eq '\') { $state = 'backslash'; $previous = $char; continue }
        if ($char -eq "'" -or $char -eq '"') { $state = 'quote'; $quote = $char; $previous = $char; continue }
        [void]$word.Append($char)
        $seen = $true
        $previous = $char
    }
    if ($state -ceq 'quote') { $result.Error = $quote; return $result }
    if ($word.Length -gt 0 -or $seen) { $null = & $finish }
    $result
}

function Test-GnuXargsNumber {
    <#
    .SYNOPSIS
    Checks a numeric option: writes GNU's usage error and returns $null, or returns the number.
    .PARAMETER Clamp
    A number below the minimum is only reported and replaced by it (-s).
    #>
    param([Parameter(Mandatory)][hashtable]$Context, [Parameter(Mandatory)][string]$Option, [AllowEmptyString()][string]$Text, [long]$Minimum, [long]$Maximum = [long]::MaxValue, [switch]$Clamp)
    if ($Text -notmatch '^[-+]?[0-9]+$') { Write-GnuUsageError -Context $Context -Message "invalid number `"$Text`" for $Option option"; return $null }
    $value = [long]0
    # strtol saturates, so a huge -n just means no limit.
    if (-not [long]::TryParse($Text, [System.Globalization.NumberStyles]::AllowLeadingSign, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$value)) {
        $value = [long]::MaxValue
        if ($Text[0] -eq '-') { $value = [long]::MinValue }
    }
    if ($value -lt $Minimum -and $Clamp) { Write-GnuWarning -Context $Context -Message "value $Text for $Option option should be >= $Minimum"; return $Minimum }
    if ($value -lt $Minimum) { Write-GnuUsageError -Context $Context -Message "value $Text for $Option option should be >= $Minimum"; return $null }
    if ($value -gt $Maximum) { Write-GnuUsageError -Context $Context -Message "value $Text for $Option option should be <= $Maximum"; return $null }
    $value
}

function Invoke-GnuXargsCommand {
    <#
    .SYNOPSIS
    Runs COMMAND once with the given arguments, in order or (with -P) as a background process.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [AllowEmptyCollection()][string[]]$Arguments)

    if ($State.Stop) { return }
    $name = $Arguments[0]
    $rest = @()
    if ($Arguments.Count -gt 1) { $rest = @($Arguments[1..($Arguments.Count - 1)]) }
    $line = $Arguments -join ' '
    if ($State.Prompt) { if (-not (Read-GnuConfirmation -Context $State.Context -Question "$line ?..." -Bare)) { return } }
    elseif ($State.Verbose) { Write-Information -MessageData $line -InformationAction Continue }
    $State.Runs++

    $command = Resolve-GnuExecCommand -Name $name
    if ($null -eq $command) {
        $message = "$($name): No such file or directory"
        if (Test-GnuWindows) { $message = "failed to run command '$name': No such file or directory" }
        Write-GnuError -Context $State.Context -Message $message -ExitCode 127
        $State.Stop = $true
        return
    }
    if ($State.MaxProcs -ne 1 -and $command.CommandType -eq 'Application') {
        Start-GnuXargsProcess -State $State -Path $command.Source -Arguments $rest
        return
    }
    $child = $State.Context.Clone()
    $child.ExitCode = 0
    $slotSet = $State.SlotVar.Length -gt 0
    if ($slotSet) { [System.Environment]::SetEnvironmentVariable($State.SlotVar, '0') }
    try { Invoke-GnuChildCommand -Context $child -Command $command -Arguments $rest -InputObject $null -LaunchPrefix $name }
    finally { if ($slotSet) { [System.Environment]::SetEnvironmentVariable($State.SlotVar, [NullString]::Value) } }
    if ($child.ContainsKey('LaunchFailed')) {
        $State.Context.ExitCode = [Math]::Max($State.Context.ExitCode, 126)
        $State.Stop = $true
        return
    }
    Set-GnuXargsResult -State $State -Name $name -Code $child.ExitCode
}

function Set-GnuXargsResult {
    <#
    .SYNOPSIS
    Applies a command's exit code to xargs' own (123, 124, 125), and stops when GNU stops.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][string]$Name, [int]$Code)

    $context = $State.Context
    if ($Code -eq 0) { return }
    if ($Code -eq 255) {
        Write-GnuError -Context $context -Message "$($Name): exited with status 255; aborting" -ExitCode 124
        $State.Stop = $true
        return
    }
    # PowerShell reports a program killed by signal N as exit code 128+N.
    if ($Code -gt 128 -and $Code -le 192 -and -not (Test-GnuWindows)) {
        Write-GnuError -Context $context -Message "$($Name): terminated by signal $($Code - 128)" -ExitCode 125
        $State.Stop = $true
        return
    }
    $context.ExitCode = [Math]::Max($context.ExitCode, 123)
}

function Start-GnuXargsProcess {
    <#
    .SYNOPSIS
    Starts one program for -P, after waiting for a free slot.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][string]$Path, [AllowEmptyCollection()][string[]]$Arguments)

    Wait-GnuXargsProcess -State $State -Below $State.MaxProcs
    if ($State.Stop) { return }
    $info = New-GnuProcessStartInfo -Path $Path -Arguments $Arguments
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.RedirectStandardInput = $true
    $slot = 0
    while (@($State.Running | Where-Object { $_.Slot -eq $slot }).Count -gt 0) { $slot++ }
    if ($State.SlotVar.Length -gt 0) { $info.Environment[$State.SlotVar] = [string]$slot }
    try { $process = [System.Diagnostics.Process]::Start($info) }
    catch {
        Write-GnuError -Context $State.Context -Message "$([System.IO.Path]::GetFileName($Path)): $(Get-GnuErrorReason -Exception $_.Exception)" -ExitCode 126
        $State.Stop = $true
        return
    }
    $process.StandardInput.Close()
    # Read while the process runs: a full pipe would block it forever.
    $State.Running.Add(@{ Process = $process; Name = [System.IO.Path]::GetFileName($Path); Slot = $slot; Out = $process.StandardOutput.ReadToEndAsync(); Err = $process.StandardError.ReadToEndAsync() })
}

function Wait-GnuXargsProcess {
    <#
    .SYNOPSIS
    Collects finished processes until fewer than Below are running; a limit of 0 means no limit.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [long]$Below)

    if ($Below -eq 0) { return }
    while ($State.Running.Count -ge $Below) {
        for ($i = $State.Running.Count - 1; $i -ge 0; $i--) {
            $job = $State.Running[$i]
            if (-not $job.Process.HasExited) { continue }
            $job.Process.WaitForExit()
            ConvertTo-GnuOutputLine -Text $job.Out.Result
            if ($job.Err.Result.Length -gt 0) { [System.Console]::Error.Write($job.Err.Result) }
            Set-GnuXargsResult -State $State -Name $job.Name -Code $job.Process.ExitCode
            $job.Process.Dispose()
            $State.Running.RemoveAt($i)
        }
        if ($State.Running.Count -ge $Below) { Start-Sleep -Milliseconds 10 }
    }
}

function Invoke-GnuXargsBatch {
    <#
    .SYNOPSIS
    Implementation of xargs.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $maxArgs = [long]0
    $maxLines = [long]0
    $replace = $null
    $warn = {
        param($Option, $Previous)
        Write-GnuWarning -Context $Context -Message "warning: options $Previous and $Option are mutually exclusive, ignoring previous $Previous value"
    }
    # -n, -L, -l and -I exclude each other and the last one wins, so they are read in command line order.
    foreach ($entry in @(Get-GnuOptionValue -Context $Context -Key 'group' -Default @())) {
        $kind = $entry.Substring(0, 1)
        $text = $entry.Substring(2)
        if ($kind -ceq 'I' -or $kind -ceq 'i') {
            $replace = $text
            if ($replace.Length -eq 0 -and $kind -ceq 'i') { $replace = '{}' }
            if ($maxArgs -ne 0) { & $warn '--replace/-I/-i' '--max-args'; $maxArgs = 0 }
            if ($maxLines -ne 0) { & $warn '--replace/-I/-i' '--max-lines'; $maxLines = 0 }
            continue
        }
        if ($kind -ceq 'l' -and $text.Length -eq 0) { $text = '1' }
        $value = Test-GnuXargsNumber -Context $Context -Option "-$kind" -Text $text -Minimum 1
        if ($null -eq $value) { return }
        if ($kind -ceq 'n') {
            $maxArgs = $value
            if ($maxLines -ne 0) { & $warn '--max-args/-n' '--max-lines'; $maxLines = 0 }
            # -I already means one argument per command, so -n 1 changes nothing.
            if ($null -ne $replace -and $value -eq 1) { $maxArgs = 0 }
            elseif ($null -ne $replace) { & $warn '--max-args/-n' '--replace'; $replace = $null }
            continue
        }
        $label = '-L'
        if ($kind -ceq 'l') { $label = '--max-lines/-l' }
        $maxLines = $value
        if ($maxArgs -ne 0) { & $warn $label '--max-args'; $maxArgs = 0 }
        if ($null -ne $replace) { & $warn $label '--replace'; $replace = $null }
    }
    $maxProcs = [long]1
    if (Test-GnuOption -Context $Context -Key 'max-procs') {
        $maxProcs = Test-GnuXargsNumber -Context $Context -Option '-P' -Text ([string](Get-GnuOptionValue -Context $Context -Key 'max-procs')) -Minimum 0 -Maximum ([int]::MaxValue)
        if ($null -eq $maxProcs) { return }
    }
    # Windows limits a command line to 32767 characters.
    $limit = [long]131072
    $largest = [long]::MaxValue
    if (Test-GnuWindows) { $limit = [long]32000; $largest = $limit }
    if (Test-GnuOption -Context $Context -Key 'max-chars') {
        $limit = Test-GnuXargsNumber -Context $Context -Option '-s' -Text ([string](Get-GnuOptionValue -Context $Context -Key 'max-chars')) -Minimum 1 -Clamp
        if ($null -eq $limit) { return }
        if ($limit -gt $largest) {
            Write-GnuWarning -Context $Context -Message "warning: value $limit for -s option is too large, using $largest instead"
            $limit = $largest
        }
    }

    $delimiter = $null
    foreach ($entry in @(Get-GnuOptionValue -Context $Context -Key 'delimiter' -Default @())) {
        if ($entry[0] -ceq '0') { $delimiter = [char]0; continue }
        $found = ConvertFrom-GnuXargsDelimiter -Text $entry.Substring(2)
        if ($null -ne $found.Error) { Write-GnuError -Context $Context -Message $found.Error; return }
        $delimiter = $found.Char
    }
    $eof = $null
    if (Test-GnuOption -Context $Context -Key 'eof') {
        $eof = [string](Get-GnuOptionValue -Context $Context -Key 'eof')
        if ($eof.Length -eq 0) { $eof = $null }
        if ($null -ne $delimiter -and $null -ne $eof) { Write-GnuWarning -Context $Context -Message "warning: the -E option has no effect if -0 or -d is used.`n" }
    }
    $initial = [string[]]@($Context.Operands)
    if ($initial.Count -eq 0) { $initial = [string[]]@('echo') }
    $baseSize = [long]0
    foreach ($argument in $initial) { $baseSize += $argument.Length + 1 }
    if ($limit -lt $baseSize -and $null -eq $replace) {
        Write-GnuError -Context $Context -Message 'cannot fit single argument within argument list size limit'
        return
    }

    $source = '-'
    if (Test-GnuOption -Context $Context -Key 'arg-file') { $source = [string](Get-GnuOptionValue -Context $Context -Key 'arg-file') }
    if ($source -cne '-' -and -not [System.IO.File]::Exists((Resolve-GnuPath -Path $source))) {
        Write-GnuError -Context $Context -Message "Cannot open input file '$source': No such file or directory"
        return
    }
    $text = [string](Get-GnuInputText -Context $Context -Operand $source)

    $items = @()
    if ($null -ne $delimiter) {
        # Pipeline text gets a newline after its last line that was never part of the data.
        if ($source -ceq '-' -and $text.EndsWith("`n", [System.StringComparison]::Ordinal) -and $delimiter -ne "`n") { $text = $text.Substring(0, $text.Length - 1) }
        $items = @(foreach ($part in @(Split-GnuRecord -Text $text -Separator ([string]$delimiter))) { @{ Text = ($part -split "`0", 2)[0]; Lines = 1 } })
    }
    else {
        $parsed = Read-GnuXargsItem -Text $text -Eof $eof -Whole:($null -ne $replace)
        if ($null -ne $parsed.Error) {
            $word = 'single'
            if ($parsed.Error -eq '"') { $word = 'double' }
            Write-GnuError -Context $Context -Message "unmatched $word quote; by default quotes are special to xargs unless you use the -0 option"
            return
        }
        if ($parsed.Nul) { Write-GnuWarning -Context $Context -Message 'WARNING: a NUL character occurred in the input.  It cannot be passed through in the argument list.  Did you mean to use the --null option?' }
        $items = @($parsed.Items)
    }

    $state = @{
        Context = $Context; Verbose = Test-GnuOption -Context $Context -Key 'verbose'; Prompt = Test-GnuOption -Context $Context -Key 'interactive'; MaxProcs = $maxProcs
        SlotVar = [string](Get-GnuOptionValue -Context $Context -Key 'process-slot-var' -Default ''); Stop = $false; Runs = 0; Running = New-Object 'System.Collections.Generic.List[hashtable]'
    }
    $exitOnSize = Test-GnuOption -Context $Context -Key 'exit'
    $current = New-Object 'System.Collections.Generic.List[string]'
    $size = $baseSize
    $lines = [long]0
    foreach ($item in $items) {
        if ($state.Stop) { break }
        if ($null -ne $replace) {
            if ($replace.Length -eq 0) { Write-GnuError -Context $Context -Message 'command too long'; $state.Stop = $true; break }
            Invoke-GnuXargsCommand -State $state -Arguments ([string[]]@($initial | ForEach-Object { $_.Replace($replace, $item.Text) }))
            continue
        }
        $lines += $item.Lines
        $itemSize = [long]$item.Text.Length + 1
        if ($baseSize + $itemSize -gt $limit) { Write-GnuError -Context $Context -Message 'argument line too long'; $state.Stop = $true; break }
        if ($size + $itemSize -gt $limit) {
            if ($exitOnSize -and ($maxArgs -gt 0 -or $maxLines -gt 0)) { Write-GnuError -Context $Context -Message 'argument list too long'; $state.Stop = $true; break }
            Invoke-GnuXargsCommand -State $state -Arguments ([string[]]($initial + $current.ToArray()))
            $current.Clear()
            $size = $baseSize
        }
        $current.Add($item.Text)
        $size += $itemSize
        if (($maxArgs -gt 0 -and $current.Count -ge $maxArgs) -or ($maxLines -gt 0 -and $lines -ge $maxLines)) {
            Invoke-GnuXargsCommand -State $state -Arguments ([string[]]($initial + $current.ToArray()))
            $current.Clear()
            $size = $baseSize
            $lines = 0
        }
    }
    if ($current.Count -gt 0 -or ($null -eq $replace -and $state.Runs -eq 0 -and -not $state.Stop -and -not (Test-GnuOption -Context $Context -Key 'no-run-if-empty'))) {
        Invoke-GnuXargsCommand -State $state -Arguments ([string[]]($initial + $current.ToArray()))
    }
    Wait-GnuXargsProcess -State $state -Below 1
}
