Register-GnuUtil @{
    Name         = 'paste'
    Category     = 'Text processing'
    Synopsis     = 'Merge lines of files.'
    Usage        = @('paste [OPTION]... [FILE]...')
    Description  = @(
        'Write lines consisting of the sequentially corresponding lines from',
        'each FILE, separated by TABs, to standard output.',
        '',
        'With no FILE, or when FILE is -, read standard input.'
    )
    FileOperands = $true
    Options      = @(
        @{ Short = 'd'; Long = 'delimiters'; Arg = 'LIST'; Help = 'reuse characters from LIST instead of TABs' }
        @{ Short = 's'; Long = 'serial'; Help = 'paste one file at a time instead of in parallel' }
        @{ Short = 'z'; Long = 'zero-terminated'; Help = 'line delimiter is NUL, not newline' }
    )
    Notes        = @('LIST may contain the escapes \n (newline), \t (tab), \\ (backslash) and \0 (no delimiter).')
}

function Invoke-GnuPaste {
    <#
    .SYNOPSIS
    GNU paste: merge lines of files.

    .DESCRIPTION
    Joins line N of every FILE into one output line, separated by TAB or by the characters of
    -d LIST (used in turn). With -s, the lines of each file are joined into one line. Each '-'
    operand reads the next line of the pipeline input.
    Enable the GNU name with: Enable-GnuAlias paste

    .EXAMPLE
    Invoke-GnuPaste -d ',' names.txt ages.txt

    .EXAMPLE
    1..6 | Invoke-GnuPaste - - -

    1	2	3
    4	5	6
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'paste' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuPasteMerge -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function ConvertFrom-GnuPasteDelimiter {
    <#
    .SYNOPSIS
    Expands the escapes of a paste -d LIST into a list of delimiters ('' for \0).
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$List)

    $delimiters = New-Object 'System.Collections.Generic.List[string]'
    for ($i = 0; $i -lt $List.Length; $i++) {
        $char = $List[$i]
        if ($char -eq '\' -and $i + 1 -lt $List.Length) {
            $i++
            switch -CaseSensitive ([string]$List[$i]) {
                'n' { $delimiters.Add("`n") }
                't' { $delimiters.Add("`t") }
                '0' { $delimiters.Add('') }
                default { $delimiters.Add([string]$List[$i]) }
            }
        }
        else {
            $delimiters.Add([string]$char)
        }
    }
    , $delimiters.ToArray()
}

function Invoke-GnuPasteMerge {
    <#
    .SYNOPSIS
    Implementation of paste.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $delimiters = [string[]]@("`t")
    if (Test-GnuOption -Context $Context -Key 'delimiters') {
        $delimiters = ConvertFrom-GnuPasteDelimiter -List ([string](Get-GnuOptionValue -Context $Context -Key 'delimiters'))
        if ($delimiters.Length -eq 0) { $delimiters = [string[]]@('') }
    }
    $zero = Test-GnuOption -Context $Context -Key 'zero-terminated'
    $operands = @($Context.Operands)
    if ($operands.Count -eq 0) { $operands = @('-') }

    # Every operand becomes a queue of records; all '-' operands share the same queue (GNU reads stdin in turn).
    $stdin = $null
    $sources = New-Object 'System.Collections.Generic.List[object]'
    foreach ($operand in $operands) {
        if ($operand -eq '-' -and $null -ne $stdin) { $sources.Add($stdin); continue }
        $records = @()
        if ($zero) {
            $text = Get-GnuInputText -Context $Context -Operand $operand
            if ($null -eq $text) { return }
            $records = @(Split-GnuRecord -Text $text -Separator "`0")
        }
        else {
            # GNU: paste stops without output when an input cannot be opened.
            $errorsBefore = $Context.ErrorCount
            $records = @(Get-GnuInputLine -Context $Context -Operand $operand)
            if ($Context.ErrorCount -gt $errorsBefore) { return }
        }
        $queue = New-Object 'System.Collections.Generic.Queue[string]'
        foreach ($record in $records) { $queue.Enqueue($record) }
        if ($operand -eq '-') { $stdin = $queue }
        $sources.Add($queue)
    }

    $output = New-Object 'System.Collections.Generic.List[string]'
    if (Test-GnuOption -Context $Context -Key 'serial') {
        # GNU: one output line per operand, even for empty input (a later '-' finds stdin already consumed).
        foreach ($queue in $sources) {
            $builder = New-Object System.Text.StringBuilder
            $index = 0
            while ($queue.Count -gt 0) {
                if ($index -gt 0) { [void]$builder.Append($delimiters[($index - 1) % $delimiters.Length]) }
                [void]$builder.Append($queue.Dequeue())
                $index++
            }
            $output.Add($builder.ToString())
        }
    }
    else {
        while ($true) {
            $any = $false
            foreach ($queue in $sources) { if ($queue.Count -gt 0) { $any = $true; break } }
            if (-not $any) { break }
            $builder = New-Object System.Text.StringBuilder
            for ($i = 0; $i -lt $sources.Count; $i++) {
                if ($i -gt 0) { [void]$builder.Append($delimiters[($i - 1) % $delimiters.Length]) }
                if ($sources[$i].Count -gt 0) { [void]$builder.Append($sources[$i].Dequeue()) }
            }
            $output.Add($builder.ToString())
        }
    }

    if ($zero) {
        ConvertTo-GnuRecordOutput -Record $output.ToArray() -Zero
        return
    }
    # Delimiters may contain newlines (-d '\n'), so split the result into lines.
    foreach ($line in $output) { ConvertTo-GnuOutputLine -Text ($line + "`n") }
}
