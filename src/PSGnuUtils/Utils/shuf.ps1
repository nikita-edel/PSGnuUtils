Register-GnuUtil @{
    Name         = 'shuf'
    Category     = 'Text processing'
    Synopsis     = 'Generate random permutations.'
    Usage        = @('shuf [OPTION]... [FILE]', 'shuf -e [OPTION]... [ARG]...', 'shuf -i LO-HI [OPTION]...')
    Description  = @(
        'Write a random permutation of the input lines to standard output.',
        '',
        'With no FILE, or when FILE is -, read standard input.'
    )
    Options      = @(
        @{ Short = 'e'; Long = 'echo'; Help = 'treat each ARG as an input line' }
        @{ Short = 'i'; Long = 'input-range'; Arg = 'LO-HI'; Help = 'treat each number LO through HI as an input line' }
        @{ Short = 'n'; Long = 'head-count'; Arg = 'COUNT'; Help = 'output at most COUNT lines' }
        @{ Short = 'o'; Long = 'output'; Arg = 'FILE'; Help = 'write result to FILE instead of standard output' }
        @{ Long = 'random-source'; Arg = 'FILE'; Help = 'get random bytes from FILE' }
        @{ Short = 'r'; Long = 'repeat'; Help = 'output lines can be repeated' }
        @{ Short = 'z'; Long = 'zero-terminated'; Help = 'line delimiter is NUL, not newline' }
    )
    Notes        = @(
        'PowerShell note: --random-source seeds the generator from the file content, so the same file gives the same order (not the same order as GNU).',
        'PowerShell note: -r with -o needs -n (GNU would write to the file forever).'
    )
}

function Invoke-GnuShuf {
    <#
    .SYNOPSIS
    GNU shuf: generate random permutations.

    .DESCRIPTION
    Prints the input lines (FILE, pipeline input, -e arguments or the numbers of -i LO-HI) in
    random order. -n limits the count, -r draws with repetition (endless without -n), -o writes
    to a file, --random-source makes the order reproducible.
    Enable the GNU name with: Enable-GnuUtil shuf

    .EXAMPLE
    Invoke-GnuShuf -i 1-6 -n 1

    Rolls a die.
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'shuf' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuShuffle -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function Invoke-GnuShuffle {
    <#
    .SYNOPSIS
    Implementation of shuf.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $operands = @($Context.Operands)
    $zero = Test-GnuOption -Context $Context -Key 'zero-terminated'
    $items = New-Object 'System.Collections.Generic.List[string]'
    if (Test-GnuOption -Context $Context -Key 'input-range') {
        $range = [string](Get-GnuOptionValue -Context $Context -Key 'input-range')
        if ($range -notmatch '^(\d+)-(\d+)$' -or [long]$Matches[2] -lt [long]$Matches[1] - 1) {
            Write-GnuError -Context $Context -Message "invalid input range: '$range'"
            return
        }
        if ($operands.Count -gt 0) { Write-GnuUsageError -Context $Context -Message "extra operand '$($operands[0])'"; return }
        for ($n = [long]$Matches[1]; $n -le [long]$Matches[2]; $n++) { $items.Add([string]$n) }
    }
    elseif (Test-GnuOption -Context $Context -Key 'echo') {
        foreach ($operand in $operands) { $items.Add($operand) }
    }
    else {
        if ($operands.Count -gt 1) { Write-GnuUsageError -Context $Context -Message "extra operand '$($operands[1])'"; return }
        $operand = '-'
        if ($operands.Count -eq 1) { $operand = $operands[0] }
        $text = Get-GnuInputText -Context $Context -Operand $operand
        if ($null -eq $text) { return }
        $separator = "`n"
        if ($zero) { $separator = "`0" }
        foreach ($record in @(Split-GnuRecord -Text $text.Replace("`r`n", "`n") -Separator $separator)) { $items.Add($record) }
    }

    $count = [long]::MaxValue
    if (Test-GnuOption -Context $Context -Key 'head-count') {
        $countText = [string](Get-GnuOptionValue -Context $Context -Key 'head-count')
        if ($countText -notmatch '^\d+$') { Write-GnuError -Context $Context -Message "invalid line count: '$countText'"; return }
        $count = ConvertTo-GnuInt64 -Value (ConvertFrom-GnuSize -Text $countText)
    }

    $random = New-Object System.Random
    if (Test-GnuOption -Context $Context -Key 'random-source') {
        $sourceName = [string](Get-GnuOptionValue -Context $Context -Key 'random-source')
        $bytes = Get-GnuInputBytes -Context $Context -Operand $sourceName
        if ($null -eq $bytes) { return }
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        $seed = [System.BitConverter]::ToInt32($hasher.ComputeHash([byte[]]$bytes), 0)
        $hasher.Dispose()
        $random = New-Object System.Random -ArgumentList $seed
    }

    $output = New-Object 'System.Collections.Generic.List[string]'
    if (Test-GnuOption -Context $Context -Key 'repeat') {
        if ($items.Count -eq 0) {
            if ($count -gt 0) { Write-GnuError -Context $Context -Message 'no lines to repeat' }
            return
        }
        if ($count -eq [long]::MaxValue) {
            if (Test-GnuOption -Context $Context -Key 'output') {
                Write-GnuUsageError -Context $Context -Message '--repeat with --output needs --head-count (the file would grow forever)'
                return
            }
            # GNU repeats forever; stop it with Ctrl+C or Select-Object -First.
            while ($true) { $items[$random.Next($items.Count)] }
        }
        for ($i = 0; $i -lt $count; $i++) { $output.Add($items[$random.Next($items.Count)]) }
    }
    else {
        # Fisher-Yates shuffle.
        $array = $items.ToArray()
        for ($i = $array.Length - 1; $i -gt 0; $i--) {
            $j = $random.Next($i + 1)
            $swap = $array[$i]; $array[$i] = $array[$j]; $array[$j] = $swap
        }
        $take = [long][Math]::Min([long]$array.Length, $count)
        for ($i = 0; $i -lt $take; $i++) { $output.Add($array[$i]) }
    }

    if (Test-GnuOption -Context $Context -Key 'output') {
        $target = [string](Get-GnuOptionValue -Context $Context -Key 'output')
        $terminator = "`n"
        if ($zero) { $terminator = "`0" }
        $content = ''
        if ($output.Count -gt 0) { $content = ($output -join $terminator) + $terminator }
        try { [System.IO.File]::WriteAllText((Resolve-GnuPath -Path $target), $content, $script:GnuUtf8) }
        catch { Write-GnuError -Context $Context -Message "$($target): $(Get-GnuErrorReason -Exception $_.Exception)" }
        return
    }
    ConvertTo-GnuRecordOutput -Record $output.ToArray() -Zero:$zero
}
