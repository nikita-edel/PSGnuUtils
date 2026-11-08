Register-GnuUtil @{
    Name         = 'nl'
    Category     = 'Viewing file contents'
    Synopsis     = 'Number lines of files.'
    Usage        = @('nl [OPTION]... [FILE]...')
    Description  = @('Write each FILE to standard output, with line numbers added.', '', 'With no FILE, or when FILE is -, read standard input.')
    FileOperands = $true
    Options      = @(
        @{ Short = 'b'; Long = 'body-numbering'; Arg = 'STYLE'; Help = 'use STYLE for numbering body lines' }
        @{ Short = 'd'; Long = 'section-delimiter'; Arg = 'CC'; Help = 'use CC for logical page delimiters' }
        @{ Short = 'f'; Long = 'footer-numbering'; Arg = 'STYLE'; Help = 'use STYLE for numbering footer lines' }
        @{ Short = 'h'; Long = 'header-numbering'; Arg = 'STYLE'; Help = 'use STYLE for numbering header lines' }
        @{ Short = 'i'; Long = 'line-increment'; Arg = 'NUMBER'; Help = 'line number increment at each line' }
        @{ Short = 'l'; Long = 'join-blank-lines'; Arg = 'NUMBER'; Help = 'group of NUMBER empty lines counted as one' }
        @{ Short = 'n'; Long = 'number-format'; Arg = 'FORMAT'; Help = 'insert line numbers according to FORMAT' }
        @{ Short = 'p'; Long = 'no-renumber'; Help = 'do not reset line numbers for each section' }
        @{ Short = 's'; Long = 'number-separator'; Arg = 'STRING'; Help = 'add STRING after (possible) line number' }
        @{ Short = 'v'; Long = 'starting-line-number'; Arg = 'NUMBER'; Help = 'first line number for each section' }
        @{ Short = 'w'; Long = 'number-width'; Arg = 'NUMBER'; Help = 'use NUMBER columns for line numbers' }
    )
    Notes        = @(
        'Default options are: -bt -d''\:'' -fn -hn -i1 -l1 -n''rn'' -s<TAB> -v1 -w6',
        '',
        'CC are two delimiter characters used to construct logical page delimiters;',
        'a missing second character implies '':''.',
        '',
        'STYLE is one of:',
        '',
        '  a      number all lines',
        '  t      number only nonempty lines',
        '  n      number no lines',
        '  pBRE   number only lines that contain a match for the basic regular',
        '         expression, BRE',
        '',
        'FORMAT is one of:',
        '',
        '  ln     left justified, no leading zeros',
        '  rn     right justified, no leading zeros',
        '  rz     right justified, leading zeros',
        '',
        'PowerShell note: pBRE uses .NET regular expression syntax.'
    )
}

function Invoke-GnuNl {
    <#
    .SYNOPSIS
    GNU nl: number lines of files.

    .DESCRIPTION
    Numbers the non-empty body lines (-b t, default) of every FILE. Supports numbering styles
    (a, t, n, pREGEX) for header, body and footer sections, number formats (ln, rn, rz), width,
    separator, start value and increment.
    Enable the GNU name with: Enable-GnuAlias nl

    .EXAMPLE
    Get-Content script.ps1 | Invoke-GnuNl -ba -w3
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'nl' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) {
            $settings = Get-GnuNlSetting -Context $ctx
            if ($null -ne $settings) {
                $operands = @($ctx.Operands)
                if ($operands.Count -eq 0) { $operands = @('-') }
                $state = @{ Number = $settings.Start; Section = 'body'; BlankRun = 0 }
                foreach ($operand in $operands) {
                    foreach ($line in @(Get-GnuInputLine -Context $ctx -Operand $operand)) {
                        Format-GnuNlLine -Line $line -Settings $settings -State $state
                    }
                }
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}

function Get-GnuNlSetting {
    <#
    .SYNOPSIS
    Validates the nl options. Returns the settings hashtable, or nothing after reporting an error.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $settings = @{}
    foreach ($section in @(@{ Key = 'body-numbering'; Name = 'body'; Default = 't' }, @{ Key = 'header-numbering'; Name = 'header'; Default = 'n' }, @{ Key = 'footer-numbering'; Name = 'footer'; Default = 'n' })) {
        $style = [string](Get-GnuOptionValue -Context $Context -Key $section.Key -Default $section.Default)
        if ($style -cnotmatch '^([atn]|p.*)$') {
            Write-GnuUsageError -Context $Context -Message "invalid $($section.Name) numbering style: '$style'"
            return
        }
        $settings[$section.Name] = $style
    }

    $numbers = @{ 'line-increment' = 1; 'join-blank-lines' = 1; 'starting-line-number' = 1; 'number-width' = 6 }
    $labels = @{ 'line-increment' = 'line number increment'; 'join-blank-lines' = 'line number of blank lines'; 'starting-line-number' = 'starting line number'; 'number-width' = 'line number field width' }
    foreach ($key in @($numbers.Keys)) {
        if (-not (Test-GnuOption -Context $Context -Key $key)) { continue }
        $text = [string](Get-GnuOptionValue -Context $Context -Key $key)
        $value = [long]0
        $valid = [long]::TryParse($text, [System.Globalization.NumberStyles]::AllowLeadingSign, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$value)
        if ($valid -and ($key -eq 'join-blank-lines' -or $key -eq 'number-width') -and $value -lt 1) { $valid = $false }
        if (-not $valid) {
            Write-GnuUsageError -Context $Context -Message "invalid $($labels[$key]): '$text'"
            return
        }
        $numbers[$key] = $value
    }

    $format = [string](Get-GnuOptionValue -Context $Context -Key 'number-format' -Default 'rn')
    if (@('ln', 'rn', 'rz') -cnotcontains $format) {
        Write-GnuUsageError -Context $Context -Message "invalid line numbering format: '$format'"
        return
    }

    $delimiter = [string](Get-GnuOptionValue -Context $Context -Key 'section-delimiter' -Default '\:')
    if ($delimiter.Length -eq 1) { $delimiter += ':' }

    $settings['Increment'] = $numbers['line-increment']
    $settings['JoinBlank'] = $numbers['join-blank-lines']
    $settings['Start'] = $numbers['starting-line-number']
    $settings['Width'] = [int]$numbers['number-width']
    $settings['Format'] = $format
    $settings['Separator'] = [string](Get-GnuOptionValue -Context $Context -Key 'number-separator' -Default "`t")
    $settings['Delimiter'] = $delimiter
    $settings['Renumber'] = -not (Test-GnuOption -Context $Context -Key 'no-renumber')
    $settings
}

function Format-GnuNlLine {
    <#
    .SYNOPSIS
    Numbers (or not) one input line and handles section delimiter lines.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Line,
        [Parameter(Mandatory)][hashtable]$Settings,
        [Parameter(Mandatory)][hashtable]$State
    )

    $delimiter = $Settings.Delimiter
    $section = $null
    if ($delimiter.Length -gt 0) {
        if ([string]::Equals($Line, $delimiter * 3, [System.StringComparison]::Ordinal)) { $section = 'header' }
        elseif ([string]::Equals($Line, $delimiter * 2, [System.StringComparison]::Ordinal)) { $section = 'body' }
        elseif ([string]::Equals($Line, $delimiter, [System.StringComparison]::Ordinal)) { $section = 'footer' }
    }
    if ($null -ne $section) {
        # GNU: a delimiter line starts a section, prints as an empty line, and a header resets the numbers.
        $State.Section = $section
        $State.BlankRun = 0
        if ($section -eq 'header' -and $Settings.Renumber) { $State.Number = $Settings.Start }
        return ''
    }

    $style = $Settings[$State.Section]
    $number = $false
    switch -Regex ($style) {
        '^a$' {
            if ($Line.Length -eq 0) {
                $State.BlankRun++
                if ($State.BlankRun -ge $Settings.JoinBlank) { $number = $true; $State.BlankRun = 0 }
            }
            else {
                $number = $true
                $State.BlankRun = 0
            }
        }
        '^t$' { $number = $Line.Length -gt 0 }
        '^p' { $number = [regex]::IsMatch($Line, $style.Substring(1)) }
    }

    if (-not $number) {
        return (' ' * ($Settings.Width + $Settings.Separator.Length)) + $Line
    }

    $text = $State.Number.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    switch ($Settings.Format) {
        'ln' { $text = $text.PadRight($Settings.Width) }
        'rn' { $text = $text.PadLeft($Settings.Width) }
        'rz' {
            if ($State.Number -lt 0) { $text = '-' + $text.Substring(1).PadLeft($Settings.Width - 1, '0') }
            else { $text = $text.PadLeft($Settings.Width, '0') }
        }
    }
    $State.Number += $Settings.Increment
    $text + $Settings.Separator + $Line
}
