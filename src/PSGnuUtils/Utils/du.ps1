Register-GnuUtil @{
    Name         = 'du'
    Category     = 'File info and disk usage'
    Synopsis     = 'Estimate file space usage.'
    Usage        = @('du [OPTION]... [FILE]...')
    Description  = @('Summarize disk usage of the set of FILEs, recursively for directories.')
    FileOperands = $true
    Options      = @(
        @{ Short = '0'; Long = 'null'; Help = 'end each output line with NUL, not newline' }
        @{ Short = 'a'; Long = 'all'; Help = 'write counts for all files, not just directories' }
        @{ Long = 'apparent-size'; Help = 'print apparent sizes, rather than disk usage; although the apparent size is usually smaller, it may be larger due to holes in (''sparse'') files, internal fragmentation, indirect blocks, and the like' }
        @{ Short = 'B'; Long = 'block-size'; Key = 'scale'; Arg = 'SIZE'; Help = 'scale sizes by SIZE before printing them; e.g., ''-BM'' prints sizes in units of 1,048,576 bytes; see SIZE format below' }
        @{ Short = 'b'; Long = 'bytes'; Key = 'scale'; Value = '1'; Sets = @{ 'apparent-size' = 1 }; Help = 'equivalent to ''--apparent-size --block-size=1''' }
        @{ Short = 'c'; Long = 'total'; Help = 'produce a grand total' }
        @{ Short = 'd'; Long = 'max-depth'; Arg = 'N'; Help = 'print the total for a directory (or file, with --all) only if it is N or fewer levels below the command line argument;  --max-depth=0 is the same as --summarize' }
        @{ Long = 'exclude'; Arg = 'PATTERN'; Multi = $true; Help = 'exclude files that match PATTERN' }
        @{ Short = 'X'; Long = 'exclude-from'; Arg = 'FILE'; Multi = $true; Help = 'exclude files that match any pattern in FILE' }
        @{ Short = 'h'; Long = 'human-readable'; Key = 'scale'; Value = 'human:1024'; Help = 'print sizes in human readable format (e.g., 1K 234M 2G)' }
        @{ Long = 'si'; Key = 'scale'; Value = 'human:1000'; Help = 'like -h, but use powers of 1000 not 1024' }
        @{ Short = 'k'; Key = 'scale'; Value = '1K'; Help = 'like --block-size=1K' }
        @{ Short = 'L'; Long = 'dereference'; Key = 'links'; Value = 'follow'; Help = 'dereference all symbolic links' }
        @{ Short = 'm'; Key = 'scale'; Value = '1M'; Help = 'like --block-size=1M' }
        @{ Short = 'P'; Long = 'no-dereference'; Key = 'links'; Value = 'none'; Help = 'don''t follow any symbolic links (this is the default)' }
        @{ Short = 'S'; Long = 'separate-dirs'; Help = 'for directories do not include size of subdirectories' }
        @{ Short = 's'; Long = 'summarize'; Help = 'display only a total for each argument' }
        @{ Short = 't'; Long = 'threshold'; Arg = 'SIZE'; Help = 'exclude entries smaller than SIZE if positive, or entries greater than SIZE if negative' }
        @{ Short = 'x'; Long = 'one-file-system'; Help = 'skip directories on different file systems' }
    )
    Notes        = @(
        'Display values are in units of the first available SIZE from --block-size,',
        'and the DU_BLOCK_SIZE, BLOCK_SIZE and BLOCKSIZE environment variables.',
        'Otherwise, units default to 1024 bytes (or 512 if POSIXLY_CORRECT is set).',
        '',
        'PowerShell note: -x stops only at links and junctions, not at mount points. Disk usage is the size rounded up to 4 KiB clusters (.NET does not',
        'expose allocation sizes); directories count 0 on Windows and 4 KiB elsewhere. Entries',
        'are listed in name order, hard links are counted every time, and the environment',
        'variables are ignored; SIZE does not take the '' grouping prefix.'
    )
}

function Invoke-GnuDu {
    <#
    .SYNOPSIS
    GNU du: estimate file space usage.

    .DESCRIPTION
    Prints the space used by every directory below each FILE (default .), in 1K blocks,
    -B units or human readable (-h, --si). -a includes files, -s and -d limit the depth,
    -c adds a total, --apparent-size / -b count bytes, --exclude skips names.
    Enable the GNU name with: Enable-GnuUtil du

    .EXAMPLE
    Invoke-GnuDu -sh *
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'du' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) { Invoke-GnuDuReport -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function Get-GnuDuSize {
    <#
    .SYNOPSIS
    The size an entry adds: apparent bytes, or the disk usage estimate (4 KiB clusters; directories 0 on Windows).
    .PARAMETER Resolved
    With -L, the path the entry resolves to: that file is measured instead of the link.
    #>
    param([Parameter(Mandatory)][System.IO.FileSystemInfo]$Item, [Parameter(Mandatory)][bool]$Apparent, [string]$Resolved)
    if ($Resolved) { $Item = Get-Item -LiteralPath $Resolved -Force }
    # A link's own size: its target text when apparent, no blocks otherwise (checked first: a link to a directory is a DirectoryInfo).
    $target = Get-GnuLinkTarget -Path $Item.FullName
    if ($null -ne $target) {
        if ($Apparent) { return [double]$target.Length }
        return [double]0
    }
    if ($Item -is [System.IO.DirectoryInfo]) {
        # GNU counts only files and links as apparent size.
        if ($Apparent -or (Test-GnuWindows)) { return [double]0 }
        return [double]4096
    }
    $length = [double]$Item.Length
    if ($Apparent) { return $length }
    [Math]::Ceiling($length / 4096) * 4096
}

function Measure-GnuDuEntry {
    <#
    .SYNOPSIS
    Measures one entry (recursively), adding output records for the entries that are printed. Returns the size.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][System.IO.FileSystemInfo]$Item, [Parameter(Mandatory)][string]$Display, [Parameter(Mandatory)][int]$Depth)

    $canonical = ''
    if ($State.Follow) {
        $resolved = Get-GnuCanonicalPath -Path $Item.FullName -Require 'all'
        if ($resolved.ContainsKey('Error')) { Write-GnuError -Context $State.Context -Message "cannot access '$Display': $($resolved.Error)"; return [double]0 }
        $canonical = $resolved.Path
        # A link back to a directory being measured: GNU skips it silently, and without this du -L would never end.
        if ($State.Active.Contains($canonical)) { return [double]0 }
    }
    $size = Get-GnuDuSize -Item $Item -Apparent $State.Apparent -Resolved $canonical
    $isLink = $null -ne (Get-GnuLinkTarget -Path $Item.FullName)
    $descend = $Item -is [System.IO.DirectoryInfo] -and (-not $isLink -or $State.Follow)
    $children = [double]0
    if ($descend) {
        if ($State.Follow) { $null = $State.Active.Add($canonical) }
        try { $entries = @(Get-ChildItem -LiteralPath $Item.FullName -Force -ErrorAction Stop | Sort-Object -Property Name) }
        catch {
            Write-GnuError -Context $State.Context -Message "cannot read directory '$Display': $(Get-GnuErrorReason -Exception $_.Exception)"
            $entries = @()
        }
        foreach ($entry in $entries) {
            if (Test-GnuDuExcluded -State $State -Name $entry.Name) { continue }
            if ($State.OneFileSystem -and $entry -is [System.IO.DirectoryInfo] -and $null -ne (Get-GnuLinkTarget -Path $entry.FullName)) { continue }
            $childSize = Measure-GnuDuEntry -State $State -Item $entry -Display (Join-GnuDisplayPath -Directory $Display -Leaf $entry.Name) -Depth ($Depth + 1)
            if ($State.Separate -and $entry -is [System.IO.DirectoryInfo]) { continue }
            $children += $childSize
        }
        if ($State.Follow) { $null = $State.Active.Remove($canonical) }
    }
    $total = $size + $children
    $print = $Depth -eq 0 -or ($Depth -le $State.MaxDepth -and ($descend -or $State.All))
    if ($print -and (Test-GnuDuThreshold -State $State -Bytes $total)) {
        $State.Records.Add("$(Format-GnuScaledSize -Bytes $total -Scale $State.Scale)`t$Display")
    }
    $total
}

function Test-GnuDuExcluded {
    <#
    .SYNOPSIS
    $true if a name matches an --exclude / -X pattern.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][string]$Name)
    foreach ($pattern in $State.Exclude) { if ($pattern.IsMatch($Name)) { return $true } }
    $false
}

function Test-GnuDuThreshold {
    <#
    .SYNOPSIS
    The --threshold rule: positive SIZE hides smaller entries, negative SIZE hides larger ones.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][double]$Bytes)
    if ($State.Threshold -gt 0) { return $Bytes -ge $State.Threshold }
    if ($State.Threshold -lt 0) { return $Bytes -le -$State.Threshold }
    $true
}

function Invoke-GnuDuReport {
    <#
    .SYNOPSIS
    Implementation of du.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $scale = Get-GnuSizeScale -Context $Context
    if ($null -eq $scale) { return }
    $maxDepth = [long]::MaxValue
    $depthGiven = Test-GnuOption -Context $Context -Key 'max-depth'
    if ($depthGiven) {
        $text = [string](Get-GnuOptionValue -Context $Context -Key 'max-depth')
        if (-not [long]::TryParse($text, [System.Globalization.NumberStyles]::None, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$maxDepth)) {
            Write-GnuUsageError -Context $Context -Message "invalid maximum depth '$text'"
            return
        }
    }
    $summarize = Test-GnuOption -Context $Context -Key 'summarize'
    if ($summarize -and (Test-GnuOption -Context $Context -Key 'all')) {
        Write-GnuUsageError -Context $Context -Message 'cannot both summarize and show all entries'
        return
    }
    if ($summarize -and $depthGiven) {
        if ($maxDepth -ne 0) { Write-GnuUsageError -Context $Context -Message "warning: summarizing conflicts with --max-depth=$maxDepth"; return }
        Write-GnuWarning -Context $Context -Message 'warning: summarizing is the same as using --max-depth=0'
    }
    if ($summarize) { $maxDepth = 0 }
    $threshold = [double]0
    if (Test-GnuOption -Context $Context -Key 'threshold') {
        $text = [string](Get-GnuOptionValue -Context $Context -Key 'threshold')
        $negative = $text.StartsWith('-', [System.StringComparison]::Ordinal)
        $magnitude = $text
        if ($negative) { $magnitude = $text.Substring(1) }
        $parsed = ConvertFrom-GnuBlockSize -Text $magnitude -AllowZero
        if ($parsed.ContainsKey('Error')) { Write-GnuSizeArgumentError -Context $Context -Key 'threshold' -Text $text -Kind $parsed.Error; return }
        if ($negative -and $parsed.Bytes -eq 0) { Write-GnuError -Context $Context -Message "invalid --threshold argument '-0'"; return }
        $threshold = $parsed.Bytes
        if ($negative) { $threshold = -$threshold }
    }
    $patterns = New-Object 'System.Collections.Generic.List[System.Management.Automation.WildcardPattern]'
    foreach ($pattern in @(Get-GnuOptionValue -Context $Context -Key 'exclude' -Default @())) { $patterns.Add((New-Object System.Management.Automation.WildcardPattern -ArgumentList $pattern)) }
    foreach ($file in @(Get-GnuOptionValue -Context $Context -Key 'exclude-from' -Default @())) {
        $lines = Get-GnuInputLine -Context $Context -Operand $file
        foreach ($line in @($lines)) { if ($line.Length -gt 0) { $patterns.Add((New-Object System.Management.Automation.WildcardPattern -ArgumentList $line)) } }
    }

    $state = @{
        Context = $Context; Apparent = Test-GnuOption -Context $Context -Key 'apparent-size'; Scale = $scale
        MaxDepth = $maxDepth; All = Test-GnuOption -Context $Context -Key 'all'; Separate = Test-GnuOption -Context $Context -Key 'separate-dirs'
        Follow = (Get-GnuOptionValue -Context $Context -Key 'links' -Default 'none') -eq 'follow'; OneFileSystem = Test-GnuOption -Context $Context -Key 'one-file-system'
        Threshold = $threshold; Exclude = $patterns; Records = New-Object 'System.Collections.Generic.List[string]'
        Active = New-Object 'System.Collections.Generic.HashSet[string]'
    }
    $operands = @($Context.Operands)
    if ($operands.Count -eq 0) { $operands = @('.') }
    $grand = [double]0
    $zero = Test-GnuOption -Context $Context -Key 'null'
    foreach ($operand in $operands) {
        $item = Get-Item -LiteralPath (Resolve-GnuPath -Path $operand) -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) { Write-GnuError -Context $Context -Message "cannot access '$operand': No such file or directory"; continue }
        $grand += Measure-GnuDuEntry -State $state -Item $item -Display $operand -Depth 0
        # Written per operand so results and errors keep GNU's order; -0 output is one string.
        if (-not $zero) { ConvertTo-GnuRecordOutput -Record $state.Records.ToArray(); $state.Records.Clear() }
    }
    if (Test-GnuOption -Context $Context -Key 'total') { $state.Records.Add("$(Format-GnuScaledSize -Bytes $grand -Scale $scale)`ttotal") }
    ConvertTo-GnuRecordOutput -Record $state.Records.ToArray() -Zero:$zero
}
