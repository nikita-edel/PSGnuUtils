Register-GnuUtil @{
    Name          = 'diff'
    Category      = 'Searching and comparing'
    Synopsis      = 'Compare files line by line.'
    Usage         = @('diff [OPTION]... FILES')
    Description   = @('Compare FILES line by line.')
    UsageExitCode = 2
    UsageHintHasName = $true
    FileOperands  = $true
    Options       = @(
        @{ Long = 'normal'; Help = 'output a normal diff (the default)' }
        @{ Short = 'q'; Long = 'brief'; Help = 'report only when files differ' }
        @{ Short = 's'; Long = 'report-identical-files'; Help = 'report when two files are the same' }
        @{ Short = 'c'; Help = 'output 3 lines of copied context' }
        @{ Short = 'C'; Key = 'context'; Arg = 'NUM'; Help = 'output NUM lines of copied context' }
        @{ Long = 'context'; Key = 'context'; Arg = 'NUM'; OptionalArg = $true; Help = 'output NUM (default 3) lines of copied context' }
        @{ Short = 'u'; Help = 'output 3 lines of unified context' }
        @{ Short = 'U'; Key = 'unified'; Arg = 'NUM'; Help = 'output NUM lines of unified context' }
        @{ Long = 'unified'; Key = 'unified'; Arg = 'NUM'; OptionalArg = $true; Help = 'output NUM (default 3) lines of unified context' }
        @{ Short = 'e'; Long = 'ed'; Help = 'output an ed script' }
        @{ Short = 'p'; Long = 'show-c-function'; Help = 'show which C function each change is in' }
        @{ Short = 'F'; Long = 'show-function-line'; Arg = 'RE'; Help = 'show the most recent line matching RE' }
        @{ Long = 'label'; Short = 'L'; Arg = 'LABEL'; Multi = $true; Help = 'use LABEL instead of file name and timestamp (can be repeated)' }
        @{ Short = 't'; Long = 'expand-tabs'; Help = 'expand tabs to spaces in output' }
        @{ Short = 'T'; Long = 'initial-tab'; Help = 'make tabs line up by prepending a tab' }
        @{ Long = 'tabsize'; Arg = 'NUM'; Help = 'tab stops every NUM (default 8) print columns' }
        @{ Short = 'r'; Long = 'recursive'; Help = 'recursively compare any subdirectories found' }
        @{ Short = 'N'; Long = 'new-file'; Help = 'treat absent files as empty' }
        @{ Long = 'unidirectional-new-file'; Help = 'treat absent first files as empty' }
        @{ Short = 'x'; Long = 'exclude'; Arg = 'PAT'; Multi = $true; Help = 'exclude files that match PAT' }
        @{ Short = 'X'; Long = 'exclude-from'; Arg = 'FILE'; Multi = $true; Help = 'exclude files that match any pattern in FILE' }
        @{ Short = 'i'; Long = 'ignore-case'; Help = 'ignore case differences in file contents' }
        @{ Short = 'E'; Long = 'ignore-tab-expansion'; Help = 'ignore changes due to tab expansion' }
        @{ Short = 'Z'; Long = 'ignore-trailing-space'; Help = 'ignore white space at line end' }
        @{ Short = 'b'; Long = 'ignore-space-change'; Help = 'ignore changes in the amount of white space' }
        @{ Short = 'w'; Long = 'ignore-all-space'; Help = 'ignore all white space' }
        @{ Short = 'B'; Long = 'ignore-blank-lines'; Help = 'ignore changes where lines are all blank' }
        @{ Long = 'strip-trailing-cr'; Help = 'strip trailing carriage return on input' }
        @{ Short = 'a'; Long = 'text'; Help = 'treat all files as text' }
        @{ Short = 'd'; Long = 'minimal'; Help = 'try hard to find a smaller set of changes' }
        @{ Long = 'speed-large-files'; Help = 'accepted; has no effect' }
        @{ Long = 'horizon-lines'; Arg = 'NUM'; Help = 'keep NUM lines of the common prefix and suffix' }
    )
    Notes         = @(
        'FILES are ''FILE1 FILE2'' or ''DIR1 DIR2'' or ''DIR FILE'' or ''FILE DIR''.',
        'If a FILE is ''-'', read standard input.',
        'Exit status is 0 if inputs are the same, 1 if different, 2 if trouble.',
        '',
        'PowerShell notes: -y (side by side), -I, -S, --from-file and format options are not supported.',
        'File names in directories are compared in ordinal order. Timestamps have 100 ns resolution.'
    )
}

function Invoke-GnuDiff {
    <#
    .SYNOPSIS
    GNU diff: compare files line by line.

    .DESCRIPTION
    Compares two files, a file and a directory, or two directories (-r for subdirectories), and
    prints normal, unified (-u, -U), context (-c, -C) or ed (-e) output. A port of GNU's algorithm,
    so hunks come out the same. Exit code 0: same, 1: different, 2: trouble.
    Enable the GNU name with: Enable-GnuAlias diff

    .EXAMPLE
    Invoke-GnuDiff -u old.txt new.txt

    .EXAMPLE
    Invoke-GnuDiff -r -q src backup
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'diff' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuDiffReport -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}

function Remove-GnuDiffConfusingLine {
    <#
    .SYNOPSIS
    Port of GNU's discard_confusing_lines: marks lines that cannot match, and which only confuse the search, as changed.
    #>
    param([Parameter(Mandatory)][hashtable[]]$Files, [Parameter(Mandatory)][int]$ClassCount)

    $counts = @((New-Object int[] ($ClassCount + 1)), (New-Object int[] ($ClassCount + 1)))
    foreach ($f in 0, 1) { foreach ($class in $Files[$f].Equivs) { $counts[$f][$class]++ } }

    $discards = @((New-Object byte[] ($Files[0].Equivs.Length + 1)), (New-Object byte[] ($Files[1].Equivs.Length + 1)))
    foreach ($f in 0, 1) {
        $equivs = $Files[$f].Equivs
        $other = $counts[1 - $f]
        $flags = $discards[$f]
        $many = 5
        $tem = [int][Math]::Floor($equivs.Length / 64)
        while (($tem = $tem -shr 2) -gt 0) { $many *= 2 }
        for ($i = 0; $i -lt $equivs.Length; $i++) {
            $matches2 = $other[$equivs[$i]]
            if ($matches2 -eq 0) { $flags[$i] = 1 } elseif ($matches2 -gt $many) { $flags[$i] = 2 }
        }
    }

    foreach ($f in 0, 1) {
        $flags = $discards[$f]
        $end = $Files[$f].Equivs.Length
        for ($i = 0; $i -lt $end; $i++) {
            if ($flags[$i] -eq 2) { $flags[$i] = 0; continue }
            if ($flags[$i] -eq 0) { continue }
            # A nonprovisional discard starts a run of discardable lines.
            $provisional = 0
            $j = $i
            while ($j -lt $end -and $flags[$j] -ne 0) {
                if ($flags[$j] -eq 2) { $provisional++ }
                $j++
            }
            while ($j -gt $i -and $flags[$j - 1] -eq 2) {
                $j--
                $flags[$j] = 0
                $provisional--
            }
            $length = $j - $i
            if ($provisional * 4 -gt $length) {
                while ($j -gt $i) {
                    $j--
                    if ($flags[$j] -eq 2) { $flags[$j] = 0 }
                }
                continue
            }
            $minimum = 1
            $tem = $length -shr 2
            while (($tem = $tem -shr 2) -gt 0) { $minimum = $minimum -shl 1 }
            $minimum++

            $consec = 0
            for ($j = 0; $j -lt $length; $j++) {
                if ($flags[$i + $j] -ne 2) { $consec = 0; continue }
                $consec++
                if ($minimum -eq $consec) { $j -= $consec }
                elseif ($minimum -lt $consec) { $flags[$i + $j] = 0 }
            }
            $consec = 0
            for ($j = 0; $j -lt $length; $j++) {
                if ($j -ge 8 -and $flags[$i + $j] -eq 1) { break }
                if ($flags[$i + $j] -eq 2) { $consec = 0; $flags[$i + $j] = 0 }
                elseif ($flags[$i + $j] -eq 0) { $consec = 0 }
                else { $consec++ }
                if ($consec -eq 3) { break }
            }
            $i += $length - 1
            $consec = 0
            for ($j = 0; $j -lt $length; $j++) {
                if ($j -ge 8 -and $flags[$i - $j] -eq 1) { break }
                if ($flags[$i - $j] -eq 2) { $consec = 0; $flags[$i - $j] = 0 }
                elseif ($flags[$i - $j] -eq 0) { $consec = 0 }
                else { $consec++ }
                if ($consec -eq 3) { break }
            }
        }
    }

    foreach ($f in 0, 1) {
        $kept = New-Object 'System.Collections.Generic.List[int]'
        $real = New-Object 'System.Collections.Generic.List[int]'
        for ($i = 0; $i -lt $Files[$f].Equivs.Length; $i++) {
            if ($discards[$f][$i] -eq 0) {
                $kept.Add($Files[$f].Equivs[$i])
                $real.Add($i)
            }
            else { $Files[$f].Changed[$i + 1] = 1 }
        }
        $Files[$f].Kept = $kept.ToArray()
        $Files[$f].Real = $real.ToArray()
    }
}

function Find-GnuDiffMiddle {
    <#
    .SYNOPSIS
    Port of GNU's diag: finds the midpoint of a shortest edit script by searching from both ends. Returns @(x, y).
    #>
    param([Parameter(Mandatory)][hashtable]$Search, [int]$XOff, [int]$XLim, [int]$YOff, [int]$YLim)

    $xv = $Search.X
    $yv = $Search.Y
    $fd = $Search.Fd
    $bd = $Search.Bd
    $o = $Search.Offset
    $dmin = $XOff - $YLim
    $dmax = $XLim - $YOff
    $fmid = $XOff - $YOff
    $bmid = $XLim - $YLim
    $fmin = $fmid
    $fmax = $fmid
    $bmin = $bmid
    $bmax = $bmid
    $odd = (($fmid - $bmid) -band 1) -ne 0
    $fd[$o + $fmid] = $XOff
    $bd[$o + $bmid] = $XLim

    while ($true) {
        if ($fmin -gt $dmin) { $fmin--; $fd[$o + $fmin - 1] = -1 } else { $fmin++ }
        if ($fmax -lt $dmax) { $fmax++; $fd[$o + $fmax + 1] = -1 } else { $fmax-- }
        for ($d = $fmax; $d -ge $fmin; $d -= 2) {
            $tlo = $fd[$o + $d - 1]
            $thi = $fd[$o + $d + 1]
            if ($tlo -lt $thi) { $x = $thi } else { $x = $tlo + 1 }
            $y = $x - $d
            while ($x -lt $XLim -and $y -lt $YLim -and $xv[$x] -eq $yv[$y]) { $x++; $y++ }
            $fd[$o + $d] = $x
            if ($odd -and $bmin -le $d -and $d -le $bmax -and $bd[$o + $d] -le $x) { return @($x, $y) }
        }
        if ($bmin -gt $dmin) { $bmin--; $bd[$o + $bmin - 1] = [int]::MaxValue } else { $bmin++ }
        if ($bmax -lt $dmax) { $bmax++; $bd[$o + $bmax + 1] = [int]::MaxValue } else { $bmax-- }
        for ($d = $bmax; $d -ge $bmin; $d -= 2) {
            $tlo = $bd[$o + $d - 1]
            $thi = $bd[$o + $d + 1]
            if ($tlo -lt $thi) { $x = $tlo } else { $x = $thi - 1 }
            $y = $x - $d
            while ($XOff -lt $x -and $YOff -lt $y -and $xv[$x - 1] -eq $yv[$y - 1]) { $x--; $y-- }
            $bd[$o + $d] = $x
            if (-not $odd -and $fmin -le $d -and $d -le $fmax -and $x -le $fd[$o + $d]) { return @($x, $y) }
        }
    }
}

function Compare-GnuDiffSequence {
    <#
    .SYNOPSIS
    Port of GNU's compareseq: marks the changed lines of both files.
    #>
    param([Parameter(Mandatory)][hashtable]$Search, [int]$XOff, [int]$XLim, [int]$YOff, [int]$YLim)

    $xv = $Search.X
    $yv = $Search.Y
    while ($XOff -lt $XLim -and $YOff -lt $YLim -and $xv[$XOff] -eq $yv[$YOff]) { $XOff++; $YOff++ }
    while ($XOff -lt $XLim -and $YOff -lt $YLim -and $xv[$XLim - 1] -eq $yv[$YLim - 1]) { $XLim--; $YLim-- }
    if ($XOff -eq $XLim) {
        while ($YOff -lt $YLim) { $Search.Changed1[$Search.Real1[$YOff] + 1] = 1; $YOff++ }
        return
    }
    if ($YOff -eq $YLim) {
        while ($XOff -lt $XLim) { $Search.Changed0[$Search.Real0[$XOff] + 1] = 1; $XOff++ }
        return
    }
    $middle = Find-GnuDiffMiddle -Search $Search -XOff $XOff -XLim $XLim -YOff $YOff -YLim $YLim
    Compare-GnuDiffSequence -Search $Search -XOff $XOff -XLim $middle[0] -YOff $YOff -YLim $middle[1]
    Compare-GnuDiffSequence -Search $Search -XOff $middle[0] -XLim $XLim -YOff $middle[1] -YLim $YLim
}

function Move-GnuDiffBoundary {
    <#
    .SYNOPSIS
    Port of GNU's shift_boundaries: moves runs of changes to merge them and to end them at natural places.
    #>
    param([Parameter(Mandatory)][hashtable[]]$Files)

    foreach ($f in 0, 1) {
        $changed = $Files[$f].Changed
        $other = $Files[1 - $f].Changed
        $equivs = $Files[$f].Equivs
        $i = 0
        $j = 0
        $end = $equivs.Length
        while ($true) {
            while ($i -lt $end -and $changed[$i + 1] -eq 0) {
                while ($other[$j + 1] -ne 0) { $j++ }
                $j++
                $i++
            }
            if ($i -eq $end) { break }
            $start = $i
            $i++
            while ($changed[$i + 1] -ne 0) { $i++ }
            while ($other[$j + 1] -ne 0) { $j++ }
            do {
                $run = $i - $start
                while ($start -gt 0 -and $equivs[$start - 1] -eq $equivs[$i - 1]) {
                    $start--
                    $changed[$start + 1] = 1
                    $i--
                    $changed[$i + 1] = 0
                    while ($changed[$start] -ne 0) { $start-- }
                    $j--
                    while ($other[$j + 1] -ne 0) { $j-- }
                }
                if ($other[$j] -ne 0) { $corresponding = $i } else { $corresponding = $end }
                while ($i -ne $end -and $equivs[$start] -eq $equivs[$i]) {
                    $changed[$start + 1] = 0
                    $start++
                    $changed[$i + 1] = 1
                    $i++
                    while ($changed[$i + 1] -ne 0) { $i++ }
                    $j++
                    while ($other[$j + 1] -ne 0) { $corresponding = $i; $j++ }
                }
            } while ($run -ne $i - $start)
            while ($corresponding -lt $i) {
                $start--
                $changed[$start + 1] = 1
                $i--
                $changed[$i + 1] = 0
                do { $j-- } while ($other[$j + 1] -ne 0)
            }
        }
    }
}

function Get-GnuDiffLineKey {
    <#
    .SYNOPSIS
    The text two lines are compared by, after the ignore options.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [AllowEmptyString()][string]$Line)

    $key = $Line
    if ($State.IgnoreAllSpace) { $key = [regex]::Replace($key, '\s+', '') }
    elseif ($State.IgnoreSpaceChange) { $key = [regex]::Replace([regex]::Replace($key, '\s+$', ''), '\s+', ' ') }
    else {
        if ($State.IgnoreTrailing) { $key = [regex]::Replace($key, '\s+$', '') }
        if ($State.IgnoreTabs) { $key = Expand-GnuDiffTab -Text $key -Size $State.TabSize }
    }
    if ($State.IgnoreCase) { $key = $key.ToLowerInvariant() }
    $key
}

function Expand-GnuDiffTab {
    <#
    .SYNOPSIS
    Replaces tabs by spaces up to the next tab stop.
    #>
    param([AllowEmptyString()][string]$Text, [int]$Size)
    if (-not $Text.Contains("`t")) { return $Text }
    $builder = New-Object System.Text.StringBuilder
    foreach ($char in $Text.ToCharArray()) {
        if ($char -eq "`t") { [void]$builder.Append(' ', $Size - ($builder.Length % $Size)) }
        else { [void]$builder.Append($char) }
    }
    $builder.ToString()
}

function Get-GnuDiffScript {
    <#
    .SYNOPSIS
    The changes between two files: a list of @{ Line0; Line1; Deleted; Inserted; Ignore } with 0-based line numbers.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][hashtable]$First, [Parameter(Mandatory)][hashtable]$Second)

    $lines0 = $First.Lines
    $lines1 = $Second.Lines
    $robust = -not $State.Ed -and -not $State.IgnoreSpaceChange -and -not $State.IgnoreAllSpace
    $classes = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([System.StringComparer]::Ordinal)
    $keysOf = {
        param($File)
        $keys = New-Object string[] $File.Lines.Length
        for ($i = 0; $i -lt $File.Lines.Length; $i++) { $keys[$i] = Get-GnuDiffLineKey -State $State -Line $File.Lines[$i] }
        # An incomplete last line only equals another incomplete one, unless space changes are ignored.
        if ($robust -and $File.Missing -and $keys.Length -gt 0) { $keys[$keys.Length - 1] += [string][char]0 + 'missing' }
        , $keys
    }
    $keys0 = & $keysOf $First
    $keys1 = & $keysOf $Second

    # Identical ends are left out of the search, except for the lines kept as a horizon (GNU's find_identical_ends).
    $common = 0
    $limit = [Math]::Min($keys0.Length, $keys1.Length)
    while ($common -lt $limit -and [string]::Equals($lines0[$common], $lines1[$common], [System.StringComparison]::Ordinal) -and [string]::Equals($keys0[$common], $keys1[$common], [System.StringComparison]::Ordinal)) { $common++ }
    $prefix = [Math]::Max(0, $common - $State.Horizon)
    $tail = 0
    while ($tail -lt $limit - $common -and [string]::Equals($lines0[$keys0.Length - 1 - $tail], $lines1[$keys1.Length - 1 - $tail], [System.StringComparison]::Ordinal) -and [string]::Equals($keys0[$keys0.Length - 1 - $tail], $keys1[$keys1.Length - 1 - $tail], [System.StringComparison]::Ordinal)) { $tail++ }
    $suffix = [Math]::Max(0, $tail - $State.Horizon)

    $count0 = $keys0.Length - $prefix - $suffix
    $count1 = $keys1.Length - $prefix - $suffix
    $equivs0 = New-Object int[] $count0
    $equivs1 = New-Object int[] $count1
    foreach ($pair in @(, @($keys0, $equivs0)) + @(, @($keys1, $equivs1))) {
        for ($i = 0; $i -lt $pair[1].Length; $i++) {
            $key = $pair[0][$prefix + $i]
            $class = 0
            if (-not $classes.TryGetValue($key, [ref]$class)) {
                $class = $classes.Count + 1
                $classes[$key] = $class
            }
            $pair[1][$i] = $class
        }
    }

    # Changed arrays have a sentinel on both sides: index i of the file is element i + 1.
    $files = @(
        @{ Equivs = $equivs0; Changed = (New-Object byte[] ($count0 + 2)); Kept = $null; Real = $null }
        @{ Equivs = $equivs1; Changed = (New-Object byte[] ($count1 + 2)); Kept = $null; Real = $null }
    )
    if ($State.Minimal) {
        foreach ($file in $files) {
            $file.Kept = $file.Equivs
            $file.Real = [int[]](0..[Math]::Max(0, $file.Equivs.Length))
        }
    }
    else { Remove-GnuDiffConfusingLine -Files $files -ClassCount $classes.Count }
    $size = $files[0].Kept.Length + $files[1].Kept.Length + 3
    $search = @{
        X = $files[0].Kept; Y = $files[1].Kept; Real0 = $files[0].Real; Real1 = $files[1].Real; Changed0 = $files[0].Changed; Changed1 = $files[1].Changed
        Fd = New-Object int[] $size; Bd = New-Object int[] $size; Offset = $files[1].Kept.Length + 1
    }
    Compare-GnuDiffSequence -Search $search -XOff 0 -XLim $search.X.Length -YOff 0 -YLim $search.Y.Length
    Move-GnuDiffBoundary -Files $files

    $changes = New-Object 'System.Collections.Generic.List[hashtable]'
    $i0 = 0
    $i1 = 0
    $changed0 = $files[0].Changed
    $changed1 = $files[1].Changed
    while ($i0 -lt $count0 -or $i1 -lt $count1) {
        if ($changed0[$i0 + 1] -ne 0 -or $changed1[$i1 + 1] -ne 0) {
            $start0 = $i0
            $start1 = $i1
            while ($changed0[$i0 + 1] -ne 0) { $i0++ }
            while ($changed1[$i1 + 1] -ne 0) { $i1++ }
            $changes.Add(@{ Line0 = $prefix + $start0; Line1 = $prefix + $start1; Deleted = $i0 - $start0; Inserted = $i1 - $start1; Ignore = $false })
        }
        $i0++
        $i1++
    }
    foreach ($change in $changes) {
        $trivial = $State.IgnoreBlank
        if ($trivial) {
            foreach ($row in @(@($First.Lines, $change.Line0, $change.Deleted), @($Second.Lines, $change.Line1, $change.Inserted))) {
                for ($k = 0; $k -lt $row[2]; $k++) {
                    if (-not [string]::IsNullOrEmpty((Get-GnuDiffLineKey -State $State -Line $row[0][$row[1] + $k]))) { $trivial = $false }
                }
            }
        }
        $change.Ignore = $trivial
    }
    , $changes.ToArray()
}

function Get-GnuDiffHunk {
    <#
    .SYNOPSIS
    Groups changes into hunks (GNU's find_hunk): changes closer than the context distance stay together.
    #>
    param([AllowEmptyCollection()][hashtable[]]$Changes, [int]$Context)

    $start = 0
    while ($start -lt $Changes.Count) {
        $last = $start
        while ($last + 1 -lt $Changes.Count) {
            $next = $Changes[$last + 1]
            $threshold = 2 * $Context + 1
            if ($next.Ignore) { $threshold = $Context }
            if ($threshold -le $next.Line0 - ($Changes[$last].Line0 + $Changes[$last].Deleted)) { break }
            $last++
        }
        , @($Changes[$start..$last])
        $start = $last + 1
    }
}

function Get-GnuDiffHunkRange {
    <#
    .SYNOPSIS
    What a hunk touches (GNU's analyze_hunk): @{ First0; Last0; First1; Last1; Old; New }, or $null if it is all ignorable.
    #>
    param([Parameter(Mandatory)][hashtable[]]$Hunk)

    if (@($Hunk | Where-Object { -not $_.Ignore }).Count -eq 0) { return $null }
    $last = $Hunk[$Hunk.Count - 1]
    $old = $false
    $new = $false
    foreach ($change in $Hunk) {
        if ($change.Deleted -gt 0) { $old = $true }
        if ($change.Inserted -gt 0) { $new = $true }
    }
    @{ First0 = $Hunk[0].Line0; Last0 = $last.Line0 + $last.Deleted - 1; First1 = $Hunk[0].Line1; Last1 = $last.Line1 + $last.Inserted - 1; Old = $old; New = $new }
}

function Format-GnuDiffRange {
    <#
    .SYNOPSIS
    A line range for normal, context and ed output: 'a,b', or one number when it covers at most one line.
    #>
    param([int]$A, [int]$B)
    if ($B -gt $A) { return "$($A + 1),$($B + 1)" }
    [string]($B + 1)
}

function Format-GnuDiffUnifiedRange {
    <#
    .SYNOPSIS
    A line range for unified output.
    #>
    param([int]$A, [int]$B)
    $from = $A + 1
    $to = $B + 1
    if ($to -lt $from) { return "$to,0" }
    if ($to -eq $from) { return [string]$to }
    "$from,$($to - $from + 1)"
}

function Add-GnuDiffLine {
    <#
    .SYNOPSIS
    Writes one line of a file with its prefix, and GNU's note when the file does not end in a newline.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][hashtable]$File, [int]$Index, [AllowEmptyString()][string]$Prefix)

    $text = $File.Lines[$Index]
    if ($State.ExpandTabs) { $text = Expand-GnuDiffTab -Text $text -Size $State.TabSize }
    $State.Output.Add($Prefix + $text)
    if ($File.Missing -and $Index -eq $File.Lines.Length - 1 -and -not $State.Ed) { $State.Output.Add('\ No newline at end of file') }
}

function Find-GnuDiffFunctionLine {
    <#
    .SYNOPSIS
    The last line before the hunk that matches the -p / -F pattern, cut to 40 characters; '' if there is none.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][hashtable]$File, [int]$Before)

    if ($null -eq $State.FunctionRegex) { return '' }
    for ($i = $Before - 1; $i -ge 0; $i--) {
        if ($State.FunctionRegex.IsMatch($File.Lines[$i])) {
            $text = $File.Lines[$i]
            if ($text.Length -gt 40) { $text = $text.Substring(0, 40) }
            return ' ' + $text.TrimEnd()
        }
    }
    ''
}

function Add-GnuDiffNormalHunk {
    <#
    .SYNOPSIS
    One hunk of the normal format.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][hashtable]$First, [Parameter(Mandatory)][hashtable]$Second, [Parameter(Mandatory)][hashtable]$Change)

    $letter = 'c'
    if ($Change.Deleted -eq 0) { $letter = 'a' } elseif ($Change.Inserted -eq 0) { $letter = 'd' }
    $last0 = $Change.Line0 + $Change.Deleted - 1
    $last1 = $Change.Line1 + $Change.Inserted - 1
    $State.Output.Add((Format-GnuDiffRange -A $Change.Line0 -B $last0) + $letter + (Format-GnuDiffRange -A $Change.Line1 -B $last1))
    $mark = ' '
    if ($State.InitialTab) { $mark = "`t" }
    for ($i = $Change.Line0; $i -le $last0; $i++) { Add-GnuDiffLine -State $State -File $First -Index $i -Prefix "<$mark" }
    if ($Change.Deleted -gt 0 -and $Change.Inserted -gt 0) { $State.Output.Add('---') }
    for ($i = $Change.Line1; $i -le $last1; $i++) { Add-GnuDiffLine -State $State -File $Second -Index $i -Prefix ">$mark" }
}

function Add-GnuDiffEdHunk {
    <#
    .SYNOPSIS
    One hunk of an ed script.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][hashtable]$Second, [Parameter(Mandatory)][hashtable]$Change)

    $letter = 'c'
    if ($Change.Deleted -eq 0) { $letter = 'a' } elseif ($Change.Inserted -eq 0) { $letter = 'd' }
    $State.Output.Add((Format-GnuDiffRange -A $Change.Line0 -B ($Change.Line0 + $Change.Deleted - 1)) + $letter)
    if ($letter -ceq 'd') { return }
    $inserting = $true
    for ($i = $Change.Line1; $i -lt $Change.Line1 + $Change.Inserted; $i++) {
        if (-not $inserting) { $State.Output.Add('a'); $inserting = $true }
        if ($Second.Lines[$i] -ceq '.') {
            # A lone dot would end the insertion: write two dots, end it, and remove the extra dot.
            foreach ($row in '..', '.', 's/.//') { $State.Output.Add($row) }
            $inserting = $false
        }
        else { Add-GnuDiffLine -State $State -File $Second -Index $i -Prefix '' }
    }
    if ($inserting) { $State.Output.Add('.') }
}

function Add-GnuDiffContextHunk {
    <#
    .SYNOPSIS
    One hunk of the context format.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][hashtable]$First, [Parameter(Mandatory)][hashtable]$Second, [Parameter(Mandatory)][hashtable[]]$Hunk, [Parameter(Mandatory)][hashtable]$Range)

    $from0 = [Math]::Max(0, $Range.First0 - $State.ContextLines)
    $from1 = [Math]::Max(0, $Range.First1 - $State.ContextLines)
    $to0 = [Math]::Min($First.Lines.Length - 1, $Range.Last0 + $State.ContextLines)
    $to1 = [Math]::Min($Second.Lines.Length - 1, $Range.Last1 + $State.ContextLines)
    $State.Output.Add('***************' + (Find-GnuDiffFunctionLine -State $State -File $First -Before $Range.First0))
    $State.Output.Add('*** ' + (Format-GnuDiffRange -A $from0 -B $to0) + ' ****')
    $mark = ' '
    if ($State.InitialTab) { $mark = "`t" }
    if ($Range.Old) {
        $k = 0
        for ($i = $from0; $i -le $to0; $i++) {
            while ($k -lt $Hunk.Count -and $Hunk[$k].Line0 + $Hunk[$k].Deleted -le $i) { $k++ }
            $flag = ' '
            if ($k -lt $Hunk.Count -and $Hunk[$k].Line0 -le $i) { if ($Hunk[$k].Inserted -gt 0) { $flag = '!' } else { $flag = '-' } }
            Add-GnuDiffLine -State $State -File $First -Index $i -Prefix ($flag + $mark)
        }
    }
    $State.Output.Add('--- ' + (Format-GnuDiffRange -A $from1 -B $to1) + ' ----')
    if ($Range.New) {
        $k = 0
        for ($i = $from1; $i -le $to1; $i++) {
            while ($k -lt $Hunk.Count -and $Hunk[$k].Line1 + $Hunk[$k].Inserted -le $i) { $k++ }
            $flag = ' '
            if ($k -lt $Hunk.Count -and $Hunk[$k].Line1 -le $i) { if ($Hunk[$k].Deleted -gt 0) { $flag = '!' } else { $flag = '+' } }
            Add-GnuDiffLine -State $State -File $Second -Index $i -Prefix ($flag + $mark)
        }
    }
}

function Add-GnuDiffUnifiedHunk {
    <#
    .SYNOPSIS
    One hunk of the unified format.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][hashtable]$First, [Parameter(Mandatory)][hashtable]$Second, [Parameter(Mandatory)][hashtable[]]$Hunk, [Parameter(Mandatory)][hashtable]$Range)

    $from0 = [Math]::Max(0, $Range.First0 - $State.ContextLines)
    $from1 = [Math]::Max(0, $Range.First1 - $State.ContextLines)
    $to0 = [Math]::Min($First.Lines.Length - 1, $Range.Last0 + $State.ContextLines)
    $to1 = [Math]::Min($Second.Lines.Length - 1, $Range.Last1 + $State.ContextLines)
    $State.Output.Add('@@ -' + (Format-GnuDiffUnifiedRange -A $from0 -B $to0) + ' +' + (Format-GnuDiffUnifiedRange -A $from1 -B $to1) + ' @@' + (Find-GnuDiffFunctionLine -State $State -File $First -Before $Range.First0))
    $tab = ''
    if ($State.InitialTab) { $tab = "`t" }
    $i = $from0
    $j = $from1
    $k = 0
    while ($i -le $to0 -or $j -le $to1) {
        if ($k -ge $Hunk.Count -or $i -lt $Hunk[$k].Line0) {
            Add-GnuDiffLine -State $State -File $First -Index $i -Prefix (' ' + $tab)
            $i++
            $j++
            continue
        }
        for ($n = 0; $n -lt $Hunk[$k].Deleted; $n++) { Add-GnuDiffLine -State $State -File $First -Index $i -Prefix ('-' + $tab); $i++ }
        for ($n = 0; $n -lt $Hunk[$k].Inserted; $n++) { Add-GnuDiffLine -State $State -File $Second -Index $j -Prefix ('+' + $tab); $j++ }
        $k++
    }
}

function Format-GnuDiffFileHeader {
    <#
    .SYNOPSIS
    The name and time on a header line, or the label given with -L.
    #>
    param([Parameter(Mandatory)][hashtable]$File, [AllowNull()][string]$Label)

    if (-not [string]::IsNullOrEmpty($Label)) { return $Label }
    $time = $File.Time
    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $offset = $time.ToString('zzz', $invariant).Replace(':', '')
    $File.Name + "`t" + $time.ToString('yyyy-MM-dd HH:mm:ss.fffffff', $invariant) + '00 ' + $offset
}

function Read-GnuDiffFile {
    <#
    .SYNOPSIS
    Loads one side of a comparison: @{ Name; Lines; Missing; Time; Binary; Bytes }. An empty side stands for an absent file with -N.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][string]$Name, [switch]$Absent)

    $file = @{ Name = $Name; Lines = @(); Missing = $false; Time = [System.DateTimeOffset]::new([datetime]'1970-01-01Z'); Binary = $false; Bytes = (New-Object byte[] 0) }
    if ($Absent) { return $file }
    if ($Name -ceq '-') {
        $text = [string](Get-GnuInputText -Context $State.Context -Operand '-')
        $file.Bytes = $script:GnuUtf8.GetBytes($text)
        $file.Time = [System.DateTimeOffset]::Now
    }
    else {
        $path = Resolve-GnuPath -Path $Name
        $file.Bytes = [System.IO.File]::ReadAllBytes($path)
        $file.Time = [System.DateTimeOffset]::new([System.IO.File]::GetLastWriteTime($path))
        $text = (Read-GnuTextFile -Path $path).Text
    }
    if (-not $State.Text) { $file.Binary = [array]::IndexOf($file.Bytes, [byte]0, 0, [Math]::Min($file.Bytes.Length, 32768)) -ge 0 }
    $file.Missing = $text.Length -gt 0 -and -not $text.EndsWith("`n", [System.StringComparison]::Ordinal)
    if ($text.Length -gt 0) {
        $body = $text
        if (-not $file.Missing) { $body = $text.Substring(0, $text.Length - 1) }
        $file.Lines = $body.Split("`n")
        if ($State.StripCr) {
            for ($i = 0; $i -lt $file.Lines.Length; $i++) {
                if ($file.Lines[$i].EndsWith("`r", [System.StringComparison]::Ordinal)) { $file.Lines[$i] = $file.Lines[$i].Substring(0, $file.Lines[$i].Length - 1) }
            }
        }
    }
    $file
}

function Compare-GnuDiffContent {
    <#
    .SYNOPSIS
    Compares two regular files and writes the result.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][hashtable]$First, [Parameter(Mandatory)][hashtable]$Second, [switch]$InDirectory)

    $sameBytes = $First.Bytes.Length -eq $Second.Bytes.Length -and ([System.Linq.Enumerable]::SequenceEqual([byte[]]$First.Bytes, [byte[]]$Second.Bytes))
    $differs = -not $sameBytes
    $changes = @()
    if ($differs -and $State.Ed) {
        # An ed script cannot express an incomplete last line.
        foreach ($file in $First, $Second) {
            if ($file.Missing) {
                Write-GnuError -Context $State.Context -Message "$($file.Name): No newline at end of file`n" -ExitCode 2
                return
            }
        }
    }
    if ($differs -and -not $First.Binary -and -not $Second.Binary) {
        $changes = Get-GnuDiffScript -State $State -First $First -Second $Second
        $differs = @($changes | Where-Object { -not $_.Ignore }).Count -gt 0
    }
    if (-not $differs) {
        if ($State.ReportSame) { $State.Output.Add("Files $($First.Name) and $($Second.Name) are identical") }
        return
    }
    $State.Context.ExitCode = [Math]::Max($State.Context.ExitCode, 1)
    if ($State.Brief) { $State.Output.Add("Files $($First.Name) and $($Second.Name) differ"); return }
    if ($First.Binary -or $Second.Binary) { $State.Output.Add("Binary files $($First.Name) and $($Second.Name) differ"); return }
    if ($InDirectory) { $State.Output.Add("diff$($State.Switches) $($First.Name) $($Second.Name)") }
    if ($State.Style -ceq 'unified' -or $State.Style -ceq 'context') {
        $first0 = '***'
        $first1 = '---'
        if ($State.Style -ceq 'unified') { $first0 = '---'; $first1 = '+++' }
        $State.Output.Add("$first0 " + (Format-GnuDiffFileHeader -File $First -Label $State.Label0))
        $State.Output.Add("$first1 " + (Format-GnuDiffFileHeader -File $Second -Label $State.Label1))
    }
    if ($State.Style -ceq 'ed') {
        for ($i = $changes.Count - 1; $i -ge 0; $i--) { if (-not $changes[$i].Ignore) { Add-GnuDiffEdHunk -State $State -Second $Second -Change $changes[$i] } }
        return
    }
    if ($State.Style -ceq 'normal') {
        foreach ($change in $changes) { if (-not $change.Ignore) { Add-GnuDiffNormalHunk -State $State -First $First -Second $Second -Change $change } }
        return
    }
    foreach ($hunk in @(Get-GnuDiffHunk -Changes $changes -Context $State.ContextLines)) {
        $range = Get-GnuDiffHunkRange -Hunk $hunk
        if ($null -eq $range) { continue }
        if ($State.Style -ceq 'unified') { Add-GnuDiffUnifiedHunk -State $State -First $First -Second $Second -Hunk $hunk -Range $range }
        else { Add-GnuDiffContextHunk -State $State -First $First -Second $Second -Hunk $hunk -Range $range }
    }
}

function Test-GnuDiffExcluded {
    <#
    .SYNOPSIS
    $true if a name matches an --exclude pattern.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][string]$Name)
    foreach ($pattern in $State.Exclude) { if ($pattern.IsMatch($Name)) { return $true } }
    $false
}

function Compare-GnuDiffDirectory {
    <#
    .SYNOPSIS
    Compares two directories entry by entry in name order.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][string]$Left, [Parameter(Mandatory)][string]$Right)

    $names = New-Object 'System.Collections.Generic.SortedSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($directory in $Left, $Right) {
        # With -N a directory can exist on one side only.
        $path = Resolve-GnuPath -Path $directory
        if (-not [System.IO.Directory]::Exists($path)) { continue }
        foreach ($entry in [System.IO.Directory]::GetFileSystemEntries($path)) { $null = $names.Add([System.IO.Path]::GetFileName($entry)) }
    }
    foreach ($name in $names) {
        if (Test-GnuDiffExcluded -State $State -Name $name) { continue }
        Compare-GnuDiffEntry -State $State -Left (Join-GnuDisplayPath -Directory $Left -Leaf $name) -Right (Join-GnuDisplayPath -Directory $Right -Leaf $name) -LeftParent $Left -RightParent $Right -Leaf $name
    }
}

function Compare-GnuDiffEntry {
    <#
    .SYNOPSIS
    Compares one name found in a directory on either side.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][string]$Left, [Parameter(Mandatory)][string]$Right, [Parameter(Mandatory)][string]$LeftParent, [Parameter(Mandatory)][string]$RightParent, [Parameter(Mandatory)][string]$Leaf)

    $leftPath = Resolve-GnuPath -Path $Left
    $rightPath = Resolve-GnuPath -Path $Right
    $leftDir = [System.IO.Directory]::Exists($leftPath)
    $rightDir = [System.IO.Directory]::Exists($rightPath)
    $leftFile = [System.IO.File]::Exists($leftPath)
    $rightFile = [System.IO.File]::Exists($rightPath)
    $leftMissing = -not $leftDir -and -not $leftFile
    $rightMissing = -not $rightDir -and -not $rightFile

    $treatLeftEmpty = $leftMissing -and ($State.NewFile -or $State.UniNewFile) -and ($rightFile -or ($rightDir -and $State.Recursive))
    $treatRightEmpty = $rightMissing -and $State.NewFile -and ($leftFile -or ($leftDir -and $State.Recursive))
    if (($leftMissing -and -not $treatLeftEmpty) -or ($rightMissing -and -not $treatRightEmpty)) {
        $parent = $LeftParent
        if ($leftMissing) { $parent = $RightParent }
        $State.Output.Add("Only in $($parent.TrimEnd('/')): $Leaf")
        $State.Context.ExitCode = [Math]::Max($State.Context.ExitCode, 1)
        return
    }
    if (($leftDir -and $rightDir) -or ($leftDir -and $treatRightEmpty) -or ($rightDir -and $treatLeftEmpty)) {
        if ($State.Recursive) { Compare-GnuDiffDirectory -State $State -Left $Left -Right $Right }
        else { $State.Output.Add("Common subdirectories: $Left and $Right") }
        return
    }
    if ($leftDir -ne $rightDir -and -not $leftMissing -and -not $rightMissing) {
        $kinds = @('regular file', 'directory')
        $State.Output.Add("File $Left is a $($kinds[[int]$leftDir]) while file $Right is a $($kinds[[int]$rightDir])")
        $State.Context.ExitCode = [Math]::Max($State.Context.ExitCode, 1)
        return
    }
    $first = Read-GnuDiffFile -State $State -Name $Left -Absent:$treatLeftEmpty
    $second = Read-GnuDiffFile -State $State -Name $Right -Absent:$treatRightEmpty
    Compare-GnuDiffContent -State $State -First $first -Second $second -InDirectory
}

function Invoke-GnuDiffReport {
    <#
    .SYNOPSIS
    Implementation of diff.
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $operands = @($Context.Operands)
    if ($operands.Count -eq 0) { Write-GnuUsageError -Context $Context -Message 'missing operand after ''diff'''; return }
    if ($operands.Count -eq 1) { Write-GnuUsageError -Context $Context -Message "missing operand after '$($operands[0])'"; return }
    if ($operands.Count -gt 2) { Write-GnuUsageError -Context $Context -Message "extra operand '$($operands[2])'"; return }

    $styles = @()
    if (Test-GnuOption -Context $Context -Key 'normal') { $styles += 'normal' }
    if (Test-GnuOption -Context $Context -Key 'ed') { $styles += 'ed' }
    if ((Test-GnuOption -Context $Context -Key 'c') -or (Test-GnuOption -Context $Context -Key 'context')) { $styles += 'context' }
    if ((Test-GnuOption -Context $Context -Key 'u') -or (Test-GnuOption -Context $Context -Key 'unified')) { $styles += 'unified' }
    if ($styles.Count -gt 1) { Write-GnuUsageError -Context $Context -Message 'conflicting output style options'; return }

    $contextLines = 3
    foreach ($key in 'context', 'unified') {
        if (-not (Test-GnuOption -Context $Context -Key $key)) { continue }
        $text = [string](Get-GnuOptionValue -Context $Context -Key $key)
        if ($text.Length -eq 0) { continue }
        if ($text -notmatch '^\d+$') { Write-GnuUsageError -Context $Context -Message "invalid context length '$text'"; return }
        $contextLines = [int]$text
    }
    $tabSize = 8
    if (Test-GnuOption -Context $Context -Key 'tabsize') {
        $text = [string](Get-GnuOptionValue -Context $Context -Key 'tabsize')
        if ($text -notmatch '^[1-9]\d*$') { Write-GnuUsageError -Context $Context -Message "invalid tabsize '$text'"; return }
        $tabSize = [int]$text
    }
    $horizon = 0
    if (Test-GnuOption -Context $Context -Key 'horizon-lines') {
        $text = [string](Get-GnuOptionValue -Context $Context -Key 'horizon-lines')
        if ($text -notmatch '^\d+$') { Write-GnuUsageError -Context $Context -Message "invalid horizon length '$text'"; return }
        $horizon = [int]$text
    }
    $style = 'normal'
    if ($styles.Count -eq 1) { $style = $styles[0] }
    # -p and -F only make sense with context, so on their own they select it.
    elseif ((Test-GnuOption -Context $Context -Key 'show-c-function') -or (Test-GnuOption -Context $Context -Key 'show-function-line')) { $style = 'context' }

    $functionPattern = $null
    if (Test-GnuOption -Context $Context -Key 'show-c-function') { $functionPattern = '^[A-Za-z$_]' }
    if (Test-GnuOption -Context $Context -Key 'show-function-line') { $functionPattern = (ConvertTo-GnuDotNetRegex -Pattern ([string](Get-GnuOptionValue -Context $Context -Key 'show-function-line'))).Regex }
    $functionRegex = $null
    if ($null -ne $functionPattern) { $functionRegex = New-Object System.Text.RegularExpressions.Regex -ArgumentList $functionPattern }

    $labels = @(Get-GnuOptionValue -Context $Context -Key 'label' -Default @())
    if ($labels.Count -gt 2) { Write-GnuError -Context $Context -Message 'too many file label options' -ExitCode 2; return }
    $label0 = $null
    $label1 = $null
    if ($labels.Count -gt 0) { $label0 = $labels[0] }
    if ($labels.Count -gt 1) { $label1 = $labels[1] }

    $exclude = New-Object 'System.Collections.Generic.List[System.Management.Automation.WildcardPattern]'
    foreach ($pattern in @(Get-GnuOptionValue -Context $Context -Key 'exclude' -Default @())) { $exclude.Add((New-Object System.Management.Automation.WildcardPattern -ArgumentList $pattern)) }
    foreach ($file in @(Get-GnuOptionValue -Context $Context -Key 'exclude-from' -Default @())) {
        foreach ($line in @(Get-GnuInputLine -Context $Context -Operand $file)) { if ($line.Length -gt 0) { $exclude.Add((New-Object System.Management.Automation.WildcardPattern -ArgumentList $line)) } }
    }

    # GNU repeats the options on its 'diff -r a/x b/x' lines, in the order given.
    $switches = New-Object System.Text.StringBuilder
    $remaining = New-Object 'System.Collections.Generic.List[string]'
    foreach ($operand in @($Context.RawOperands)) { $remaining.Add($operand) }
    foreach ($argument in @($Context.Argv)) {
        if ($argument -ceq '--') { continue }
        if ($remaining.Remove($argument)) { continue }
        $shown = $argument
        if ($shown -notmatch '^[-A-Za-z0-9_+,./:@%^]+$') { $shown = "'" + $shown.Replace("'", "'\''") + "'" }
        [void]$switches.Append(' ').Append($shown)
    }

    $state = @{
        Context = $Context; Output = New-Object 'System.Collections.Generic.List[string]'; Style = $style; ContextLines = $contextLines; TabSize = $tabSize; Horizon = [Math]::Max($horizon, $(if ($style -ceq 'normal' -or $style -ceq 'ed') { 0 } else { $contextLines }))
        Brief = Test-GnuOption -Context $Context -Key 'brief'; ReportSame = Test-GnuOption -Context $Context -Key 'report-identical-files'; Ed = $style -ceq 'ed'
        IgnoreCase = Test-GnuOption -Context $Context -Key 'ignore-case'; IgnoreTabs = Test-GnuOption -Context $Context -Key 'ignore-tab-expansion'; IgnoreTrailing = Test-GnuOption -Context $Context -Key 'ignore-trailing-space'
        IgnoreSpaceChange = Test-GnuOption -Context $Context -Key 'ignore-space-change'; IgnoreAllSpace = Test-GnuOption -Context $Context -Key 'ignore-all-space'; IgnoreBlank = Test-GnuOption -Context $Context -Key 'ignore-blank-lines'
        StripCr = Test-GnuOption -Context $Context -Key 'strip-trailing-cr'; Text = Test-GnuOption -Context $Context -Key 'text'; Minimal = Test-GnuOption -Context $Context -Key 'minimal'
        ExpandTabs = Test-GnuOption -Context $Context -Key 'expand-tabs'; InitialTab = Test-GnuOption -Context $Context -Key 'initial-tab'; FunctionRegex = $functionRegex
        Label0 = $label0; Label1 = $label1; Recursive = Test-GnuOption -Context $Context -Key 'recursive'; NewFile = Test-GnuOption -Context $Context -Key 'new-file'; UniNewFile = Test-GnuOption -Context $Context -Key 'unidirectional-new-file'
        Exclude = $exclude; Switches = $switches.ToString()
    }

    $left = $operands[0]
    $right = $operands[1]
    $leftPath = ''
    $rightPath = ''
    if ($left -cne '-') { $leftPath = Resolve-GnuPath -Path $left }
    if ($right -cne '-') { $rightPath = Resolve-GnuPath -Path $right }
    $leftDir = $leftPath.Length -gt 0 -and [System.IO.Directory]::Exists($leftPath)
    $rightDir = $rightPath.Length -gt 0 -and [System.IO.Directory]::Exists($rightPath)
    if (($leftDir -and $right -ceq '-') -or ($rightDir -and $left -ceq '-')) {
        Write-GnuError -Context $Context -Message 'cannot compare ''-'' to a directory' -ExitCode 2
        return
    }
    # A directory against a file means the file of that name in the directory.
    if ($leftDir -and -not $rightDir) { $left = Join-GnuDisplayPath -Directory $left -Leaf ([System.IO.Path]::GetFileName($rightPath)); $leftPath = Resolve-GnuPath -Path $left; $leftDir = $false }
    elseif ($rightDir -and -not $leftDir) { $right = Join-GnuDisplayPath -Directory $right -Leaf ([System.IO.Path]::GetFileName($leftPath)); $rightPath = Resolve-GnuPath -Path $right; $rightDir = $false }

    $absentLeft = $false
    $absentRight = $false
    foreach ($side in @(@($left, $leftPath, 0), @($right, $rightPath, 1))) {
        if ($side[0] -ceq '-' -or [System.IO.File]::Exists($side[1]) -or [System.IO.Directory]::Exists($side[1])) { continue }
        $other = $rightPath
        if ($side[2] -eq 1) { $other = $leftPath }
        $otherExists = $other.Length -eq 0 -or [System.IO.File]::Exists($other) -or [System.IO.Directory]::Exists($other)
        $allowed = $state.NewFile -or ($state.UniNewFile -and $side[2] -eq 0)
        if ($allowed -and $otherExists) {
            if ($side[2] -eq 0) { $absentLeft = $true } else { $absentRight = $true }
            continue
        }
        Write-GnuError -Context $Context -Message "$($side[0]): No such file or directory" -ExitCode 2
    }
    if ($Context.ExitCode -ge 2) { return }

    try {
        if ($leftDir -and $rightDir) { Compare-GnuDiffDirectory -State $state -Left $left -Right $right }
        else {
            $first = Read-GnuDiffFile -State $state -Name $left -Absent:$absentLeft
            $second = Read-GnuDiffFile -State $state -Name $right -Absent:$absentRight
            Compare-GnuDiffContent -State $state -First $first -Second $second
        }
    }
    finally { $state.Output.ToArray() }
}
