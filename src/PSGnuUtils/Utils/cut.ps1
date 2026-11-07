Register-GnuUtil @{
    Name         = 'cut'
    Category     = 'Text processing'
    Synopsis     = 'Remove sections from each line of files.'
    Usage        = @('cut OPTION... [FILE]...')
    Description  = @('Print selected parts of lines from each FILE to standard output.', '', 'With no FILE, or when FILE is -, read standard input.')
    FileOperands = $true
    Options      = @(
        @{ Short = 'b'; Long = 'bytes'; Key = 'list'; Arg = 'LIST'; Sets = @{ mode = 'bytes' }; Help = 'select only these bytes' }
        @{ Short = 'c'; Long = 'characters'; Key = 'list'; Arg = 'LIST'; Sets = @{ mode = 'characters' }; Help = 'select only these characters' }
        @{ Short = 'd'; Long = 'delimiter'; Arg = 'DELIM'; Help = 'use DELIM instead of TAB for field delimiter' }
        @{ Short = 'f'; Long = 'fields'; Key = 'list'; Arg = 'LIST'; Sets = @{ mode = 'fields' }; Help = 'select only these fields;  also print any line that contains no delimiter character, unless the -s option is specified' }
        @{ Short = 'n'; Help = '(ignored)' }
        @{ Long = 'complement'; Help = 'complement the set of selected bytes, characters or fields' }
        @{ Short = 's'; Long = 'only-delimited'; Help = 'do not print lines not containing delimiters' }
        @{ Long = 'output-delimiter'; Arg = 'STRING'; Help = 'use STRING as the output delimiter the default is to use the input delimiter' }
        @{ Short = 'z'; Long = 'zero-terminated'; Help = 'line delimiter is NUL, not newline' }
    )
    Notes        = @(
        'Use one, and only one of -b, -c or -f.  Each LIST is made up of one',
        'range, or many ranges separated by commas.  Selected input is written',
        'in the same order that it is read, and is written exactly once.',
        'Each range is one of:',
        '',
        '  N     N''th byte, character or field, counted from 1',
        '  N-    from N''th byte, character or field, to end of line',
        '  N-M   from N''th to M''th (included) byte, character or field',
        '  -M    from first to M''th (included) byte, character or field',
        '',
        'PowerShell note: -c counts characters (GNU cut treats -c like -b); -b counts UTF-8 bytes.'
    )
}

function Invoke-GnuCut {
    <#
    .SYNOPSIS
    GNU cut: remove sections from each line.

    .DESCRIPTION
    Prints the selected bytes (-b), characters (-c) or delimiter separated fields (-f, delimiter
    -d, default TAB) of every line. --complement inverts the selection, -s skips lines without
    a delimiter, --output-delimiter changes the joiner.
    Enable the GNU name with: Enable-GnuUtil cut

    .EXAMPLE
    Get-Content data.csv | Invoke-GnuCut -d ',' -f 1,3
    #>
    begin {
        $ctx = Initialize-GnuUtil -Name 'cut' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput
        if (-not $ctx.Done) {
            $cut = New-GnuCutSetting -Context $ctx
            $stream = Test-GnuStdinOnly -Context $ctx
        }
    }
    process {
        if ($ctx.Done) { return }
        if ($stream) {
            foreach ($line in @(ConvertFrom-GnuPipelineItem -Context $ctx -InputObject $_)) { Select-GnuCutPart -Line $line -Setting $cut }
        }
        else {
            Add-GnuPipelineInput -Context $ctx -InputObject $_
        }
    }
    end {
        if (-not $ctx.Done) {
            if ($stream) {
                foreach ($line in @(Complete-GnuPipelineInput -Context $ctx)) { Select-GnuCutPart -Line $line -Setting $cut }
            }
            else {
                $operands = @($ctx.Operands)
                if ($operands.Count -eq 0) { $operands = @('-') }
                $records = foreach ($operand in $operands) {
                    if ($cut.Zero) {
                        $text = Get-GnuInputText -Context $ctx -Operand $operand
                        if ($null -ne $text) { Split-GnuRecord -Text $text -Separator "`0" }
                    }
                    else {
                        Get-GnuInputLine -Context $ctx -Operand $operand
                    }
                }
                $selected = foreach ($record in @($records)) { if ($null -ne $record) { Select-GnuCutPart -Line $record -Setting $cut } }
                ConvertTo-GnuRecordOutput -Record @($selected) -Zero:$cut.Zero
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}

function ConvertFrom-GnuCutList {
    <#
    .SYNOPSIS
    Parses a cut LIST into sorted, merged ranges @(@{ From; To }), To = [long]::MaxValue for open ranges.
    Returns @{ Ranges; Error }.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$List, [Parameter(Mandatory)][string]$Unit)

    $ranges = New-Object 'System.Collections.Generic.List[object]'
    foreach ($item in ($List -split '[, ]')) {
        if ($item -match '^(\d+)$') { $from = [long]$Matches[1]; $to = $from }
        elseif ($item -match '^(\d+)-$') { $from = [long]$Matches[1]; $to = [long]::MaxValue }
        elseif ($item -match '^-(\d+)$') { $from = [long]1; $to = [long]$Matches[1] }
        elseif ($item -match '^(\d+)-(\d+)$') { $from = [long]$Matches[1]; $to = [long]$Matches[2] }
        elseif ($item -eq '-') { return @{ Error = "invalid range with no endpoint: -" } }
        else { return @{ Error = "invalid $Unit value '$item'" } }

        if ($from -eq 0 -or $to -eq 0) {
            $what = 'bytes'
            if ($Unit -eq 'field') { $what = 'fields' }
            if ($Unit -eq 'character position') { $what = 'characters' }
            return @{ Error = "$what are numbered from 1" }
        }
        if ($to -lt $from) { return @{ Error = 'invalid decreasing range' } }
        $ranges.Add(@{ From = $from; To = $to })
    }

    $sorted = @($ranges | Sort-Object -Property { $_.From })
    $merged = New-Object 'System.Collections.Generic.List[object]'
    foreach ($range in $sorted) {
        if ($merged.Count -gt 0 -and $range.From -le $merged[$merged.Count - 1].To + 1) {
            $last = $merged[$merged.Count - 1]
            if ($range.To -gt $last.To) { $last.To = $range.To }
        }
        else {
            $merged.Add(@{ From = $range.From; To = $range.To })
        }
    }
    @{ Ranges = $merged.ToArray(); Error = $null }
}

function New-GnuCutSetting {
    <#
    .SYNOPSIS
    Validates the cut options and returns the settings (or marks the context Done after an error).
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $mode = [string](Get-GnuOptionValue -Context $Context -Key 'mode' -Default '')
    $setting = @{
        Mode            = $mode
        Ranges          = @()
        Delimiter       = "`t"
        OutputDelimiter = $null
        OnlyDelimited   = Test-GnuOption -Context $Context -Key 'only-delimited'
        Complement      = Test-GnuOption -Context $Context -Key 'complement'
        Zero            = Test-GnuOption -Context $Context -Key 'zero-terminated'
    }

    if ([string]::IsNullOrEmpty($mode)) {
        Write-GnuUsageError -Context $Context -Message 'you must specify a list of bytes, characters, or fields'
        return $setting
    }
    if ((Test-GnuOption -Context $Context -Key 'delimiter') -and $mode -ne 'fields') {
        Write-GnuUsageError -Context $Context -Message 'an input delimiter may be specified only when operating on fields'
        return $setting
    }
    if ($setting.OnlyDelimited -and $mode -ne 'fields') {
        Write-GnuUsageError -Context $Context -Message 'suppressing non-delimited lines makes sense only when operating on fields'
        return $setting
    }
    if (Test-GnuOption -Context $Context -Key 'delimiter') {
        $delimiter = [string](Get-GnuOptionValue -Context $Context -Key 'delimiter')
        if ($delimiter.Length -gt 1) {
            Write-GnuUsageError -Context $Context -Message 'the delimiter must be a single character'
            return $setting
        }
        # GNU: -d '' means the NUL character.
        if ($delimiter.Length -eq 0) { $delimiter = [string][char]0 }
        $setting.Delimiter = $delimiter
    }
    if (Test-GnuOption -Context $Context -Key 'output-delimiter') {
        $setting.OutputDelimiter = [string](Get-GnuOptionValue -Context $Context -Key 'output-delimiter')
    }

    $unit = 'byte/character position'
    if ($mode -eq 'fields') { $unit = 'field' }
    $parsed = ConvertFrom-GnuCutList -List ([string](Get-GnuOptionValue -Context $Context -Key 'list')) -Unit $unit
    if ($parsed.Error) {
        Write-GnuUsageError -Context $Context -Message $parsed.Error
        return $setting
    }
    $setting.Ranges = $parsed.Ranges
    $setting
}

function Test-GnuCutSelected {
    <#
    .SYNOPSIS
    $true if 1-based Position is selected (honors --complement).
    #>
    param([long]$Position, [object[]]$Ranges, [bool]$Complement)
    $inside = $false
    foreach ($range in $Ranges) {
        if ($Position -ge $range.From -and $Position -le $range.To) { $inside = $true; break }
    }
    $inside -ne $Complement
}

function Select-GnuCutPart {
    <#
    .SYNOPSIS
    Applies cut to one line; returns nothing for lines suppressed by -s.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Line,
        [Parameter(Mandatory)][hashtable]$Setting
    )

    if ($Setting.Mode -eq 'fields') {
        if ($Line.IndexOf($Setting.Delimiter, [System.StringComparison]::Ordinal) -lt 0) {
            if ($Setting.OnlyDelimited) { return }
            return $Line
        }
        $fields = $Line.Split([string[]]@($Setting.Delimiter), [System.StringSplitOptions]::None)
        $joiner = $Setting.Delimiter
        if ($null -ne $Setting.OutputDelimiter) { $joiner = $Setting.OutputDelimiter }
        $picked = for ($i = 0; $i -lt $fields.Length; $i++) {
            if (Test-GnuCutSelected -Position ($i + 1) -Ranges $Setting.Ranges -Complement $Setting.Complement) { $fields[$i] }
        }
        return (@($picked) -join $joiner)
    }

    # Bytes and characters: contiguous selected runs are joined with the output delimiter (default: nothing).
    $units = @()
    if ($Setting.Mode -eq 'bytes') { $units = $script:GnuUtf8.GetBytes($Line) }
    else {
        $units = New-Object 'System.Collections.Generic.List[string]'
        for ($i = 0; $i -lt $Line.Length; $i++) {
            if ([char]::IsHighSurrogate($Line[$i]) -and $i + 1 -lt $Line.Length) { $units.Add($Line.Substring($i, 2)); $i++ }
            else { $units.Add([string]$Line[$i]) }
        }
        $units = $units.ToArray()
    }

    $joiner = ''
    if ($null -ne $Setting.OutputDelimiter) { $joiner = $Setting.OutputDelimiter }
    $runs = New-Object 'System.Collections.Generic.List[object]'
    $current = $null
    for ($i = 0; $i -lt $units.Length; $i++) {
        if (Test-GnuCutSelected -Position ($i + 1) -Ranges $Setting.Ranges -Complement $Setting.Complement) {
            if ($null -eq $current) {
                $current = New-Object 'System.Collections.Generic.List[object]'
                $runs.Add($current)
            }
            $current.Add($units[$i])
        }
        else {
            $current = $null
        }
    }

    $parts = foreach ($run in $runs) {
        if ($Setting.Mode -eq 'bytes') { $script:GnuUtf8.GetString([byte[]]$run.ToArray()) }
        else { -join $run }
    }
    @($parts) -join $joiner
}
