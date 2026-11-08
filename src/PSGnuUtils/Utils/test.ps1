Register-GnuUtil @{
    Name         = 'test'
    Category     = 'Shell helpers'
    Synopsis     = 'Check file types and compare values.'
    Usage        = @('test EXPRESSION', 'test', 'test OPTION')
    Description  = @(
        'Exit with the status determined by EXPRESSION.',
        '',
        'An omitted EXPRESSION defaults to false.  Otherwise,',
        'EXPRESSION is true or false and sets exit status.  It is one of:'
    )
    RawArguments  = $true
    UsageExitCode = 2
    Notes        = @(
        '  ( EXPRESSION )               EXPRESSION is true',
        '  ! EXPRESSION                 EXPRESSION is false',
        '  EXPRESSION1 -a EXPRESSION2   both EXPRESSION1 and EXPRESSION2 are true',
        '  EXPRESSION1 -o EXPRESSION2   either EXPRESSION1 or EXPRESSION2 is true',
        '',
        '  -n STRING            the length of STRING is nonzero',
        '  STRING               equivalent to -n STRING',
        '  -z STRING            the length of STRING is zero',
        '  STRING1 = STRING2    the strings are equal',
        '  STRING1 != STRING2   the strings are not equal',
        '  STRING1 > STRING2    STRING1 sorts after STRING2 (ordinal)',
        '  STRING1 < STRING2    STRING1 sorts before STRING2 (ordinal)',
        '',
        '  INTEGER1 -eq INTEGER2   INTEGER1 is equal to INTEGER2',
        '  INTEGER1 -ge INTEGER2   INTEGER1 is greater than or equal to INTEGER2',
        '  INTEGER1 -gt INTEGER2   INTEGER1 is greater than INTEGER2',
        '  INTEGER1 -le INTEGER2   INTEGER1 is less than or equal to INTEGER2',
        '  INTEGER1 -lt INTEGER2   INTEGER1 is less than INTEGER2',
        '  INTEGER1 -ne INTEGER2   INTEGER1 is not equal to INTEGER2',
        '  (-l STRING may replace an INTEGER: the length of STRING)',
        '',
        '  FILE1 -ef FILE2   FILE1 and FILE2 are the same file',
        '  FILE1 -nt FILE2   FILE1 is newer (modification date) than FILE2',
        '  FILE1 -ot FILE2   FILE1 is older than FILE2',
        '',
        '  -b FILE     FILE exists and is block special',
        '  -c FILE     FILE exists and is character special',
        '  -d FILE     FILE exists and is a directory',
        '  -e FILE     FILE exists',
        '  -f FILE     FILE exists and is a regular file',
        '  -g FILE     FILE exists and is set-group-ID',
        '  -G FILE     FILE exists and is owned by the effective group ID',
        '  -h FILE     FILE exists and is a symbolic link (same as -L)',
        '  -k FILE     FILE exists and has its sticky bit set',
        '  -L FILE     FILE exists and is a symbolic link (same as -h)',
        '  -N FILE     FILE exists and has been modified since it was last read',
        '  -O FILE     FILE exists and is owned by the effective user ID',
        '  -p FILE     FILE exists and is a named pipe',
        '  -r FILE     FILE exists and the user has read access',
        '  -s FILE     FILE exists and has a size greater than zero',
        '  -S FILE     FILE exists and is a socket',
        '  -t FD       file descriptor FD is opened on a terminal',
        '  -u FILE     FILE exists and its set-user-ID bit is set',
        '  -w FILE     FILE exists and the user has write access',
        '  -x FILE     FILE exists and the user has execute (or search) access',
        '',
        'Exit status: 0 if EXPRESSION is true, 1 if it is false, 2 if an error occurred.',
        '',
        'PowerShell note: test sets $LASTEXITCODE and outputs nothing; use it as',
        '"Invoke-GnuTest -f x; if ($LASTEXITCODE -eq 0) { ... }". Quote ( ) ! = < > in',
        'PowerShell. "[" cannot be used as a command name. On Windows -x means a directory',
        'or an extension in PATHEXT, -O / -G mean the file exists, and -b -c -p -S -u -g -k',
        'are false.'
    )
}

function Invoke-GnuTest {
    <#
    .SYNOPSIS
    GNU test: check file types and compare values; the result is the exit code.

    .DESCRIPTION
    Evaluates EXPRESSION with the POSIX rules for 0 to 4 arguments and GNU's grammar beyond
    that (! ( ) -a -o). Sets $LASTEXITCODE to 0 (true), 1 (false) or 2 (error).
    Enable the GNU name with: Enable-GnuUtil test

    .EXAMPLE
    Invoke-GnuTest -d build; if ($LASTEXITCODE -eq 0) { 'build exists' }

    .EXAMPLE
    Invoke-GnuTest 10 -gt 9 -a '(' -n "$env:HOME" ')'
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'test' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            $state = @{ Args = [string[]]@($ctx.Operands); Pos = 0; Context = $ctx }
            if ($state.Args.Length -eq 0) { $ctx.ExitCode = 1 }
            else {
                try {
                    $value = Invoke-GnuTestPosix -State $state -Count $state.Args.Length
                    if ($state.Pos -ne $state.Args.Length) { Stop-GnuTestSyntax "extra argument '$($state.Args[$state.Pos])'" }
                    if (-not $value) { $ctx.ExitCode = 1 }
                }
                catch {
                    if (-not $_.Exception.Message.StartsWith('GNUTEST:', [System.StringComparison]::Ordinal)) { throw }
                    Write-GnuError -Context $ctx -Message $_.Exception.Message.Substring(8)
                    $ctx.ExitCode = 2
                }
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}

function Stop-GnuTestSyntax {
    <#
    .SYNOPSIS
    Aborts the evaluation with a syntax error (exit code 2).
    #>
    param([Parameter(Mandatory)][string]$Message)
    throw "GNUTEST:$Message"
}

function Step-GnuTestArgument {
    <#
    .SYNOPSIS
    Moves to the next argument; with -Require, a missing argument is a syntax error.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [switch]$Require)
    $State.Pos++
    if ($Require -and $State.Pos -ge $State.Args.Length) { Stop-GnuTestBeyond -State $State }
}

function Stop-GnuTestBeyond {
    <#
    .SYNOPSIS
    The "missing argument after LAST" error of GNU test.
    #>
    param([Parameter(Mandatory)][hashtable]$State)
    Stop-GnuTestSyntax "missing argument after '$($State.Args[$State.Args.Length - 1])'"
}

function Test-GnuTestBinaryOperator {
    <#
    .SYNOPSIS
    $true for the binary operators of test.
    #>
    param([AllowNull()][string]$Text)
    @('=', '==', '!=', '<', '>', '-eq', '-ne', '-lt', '-le', '-gt', '-ge', '-nt', '-ot', '-ef') -ccontains $Text
}

function Test-GnuTestUnaryOperator {
    <#
    .SYNOPSIS
    $true for the unary operators of test.
    #>
    param([AllowNull()][string]$Text)
    @('-b', '-c', '-d', '-e', '-f', '-g', '-G', '-h', '-k', '-L', '-n', '-N', '-O', '-p', '-r', '-s', '-S', '-t', '-u', '-w', '-x', '-z') -ccontains $Text
}

function Invoke-GnuTestPosix {
    <#
    .SYNOPSIS
    POSIX rules for 1 to 4 arguments; more arguments use the full grammar.
    #>
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][int]$Count)

    $a = $State.Args
    $p = $State.Pos
    switch ($Count) {
        1 { $State.Pos++; return -not [string]::IsNullOrEmpty($a[$p]) }
        2 { return Invoke-GnuTestTwo -State $State }
        3 { return Invoke-GnuTestThree -State $State }
        4 {
            if ($a[$p] -ceq '!') { Step-GnuTestArgument -State $State -Require; return -not (Invoke-GnuTestThree -State $State) }
            if ($a[$p] -ceq '(' -and $a[$p + 3] -ceq ')') {
                $State.Pos++
                $value = Invoke-GnuTestTwo -State $State
                $State.Pos++
                return $value
            }
        }
    }
    Invoke-GnuTestOr -State $State
}

function Invoke-GnuTestTwo {
    <#
    .SYNOPSIS
    Two arguments: "! STRING" or "-op OPERAND".
    #>
    param([Parameter(Mandatory)][hashtable]$State)

    $first = $State.Args[$State.Pos]
    if ($first -ceq '!') {
        $State.Pos++
        $value = -not [string]::IsNullOrEmpty($State.Args[$State.Pos])
        $State.Pos++
        return -not $value
    }
    if ($first.Length -eq 2 -and $first[0] -eq '-') {
        if (Test-GnuTestUnaryOperator $first) { return Invoke-GnuTestUnary -State $State }
        Stop-GnuTestSyntax "'$first': unary operator expected"
    }
    Stop-GnuTestBeyond -State $State
}

function Invoke-GnuTestThree {
    <#
    .SYNOPSIS
    Three arguments: a binary operation, "! A B", "( A )" or "A -a B" / "A -o B".
    #>
    param([Parameter(Mandatory)][hashtable]$State)

    $a = $State.Args
    $p = $State.Pos
    if (Test-GnuTestBinaryOperator $a[$p + 1]) { return Invoke-GnuTestBinary -State $State }
    if ($a[$p] -ceq '!') { Step-GnuTestArgument -State $State -Require; return -not (Invoke-GnuTestTwo -State $State) }
    if ($a[$p] -ceq '(' -and $a[$p + 2] -ceq ')') {
        $State.Pos += 2
        $value = -not [string]::IsNullOrEmpty($a[$p + 1])
        $State.Pos++
        return $value
    }
    if ($a[$p + 1] -ceq '-a' -or $a[$p + 1] -ceq '-o') { return Invoke-GnuTestOr -State $State }
    Stop-GnuTestSyntax "'$($a[$p + 1])': binary operator expected"
}

function Invoke-GnuTestOr {
    <#
    .SYNOPSIS
    EXPR -o EXPR ...
    #>
    param([Parameter(Mandatory)][hashtable]$State)
    $value = Invoke-GnuTestAnd -State $State
    while ($State.Pos -lt $State.Args.Length -and $State.Args[$State.Pos] -ceq '-o') {
        $State.Pos++
        $right = Invoke-GnuTestAnd -State $State
        $value = $value -or $right
    }
    $value
}

function Invoke-GnuTestAnd {
    <#
    .SYNOPSIS
    TERM -a TERM ...
    #>
    param([Parameter(Mandatory)][hashtable]$State)
    $value = Invoke-GnuTestTerm -State $State
    while ($State.Pos -lt $State.Args.Length -and $State.Args[$State.Pos] -ceq '-a') {
        $State.Pos++
        $right = Invoke-GnuTestTerm -State $State
        $value = $value -and $right
    }
    $value
}

function Invoke-GnuTestTerm {
    <#
    .SYNOPSIS
    ! TERM, ( EXPR ), a binary or unary operation, or a string.
    #>
    param([Parameter(Mandatory)][hashtable]$State)

    $a = $State.Args
    if ($State.Pos -ge $a.Length) { Stop-GnuTestBeyond -State $State }
    $invert = $false
    while ($State.Pos -lt $a.Length -and $a[$State.Pos] -ceq '!') {
        Step-GnuTestArgument -State $State -Require
        $invert = -not $invert
    }
    $p = $State.Pos
    if ($a[$p] -ceq '(') {
        Step-GnuTestArgument -State $State -Require
        $count = 1
        while ($State.Pos + $count -lt $a.Length -and $a[$State.Pos + $count] -cne ')') {
            if ($count -eq 4) { $count = $a.Length - $State.Pos; break }
            $count++
        }
        $value = Invoke-GnuTestPosix -State $State -Count $count
        if ($State.Pos -ge $a.Length) { Stop-GnuTestSyntax "')' expected" }
        if ($a[$State.Pos] -cne ')') { Stop-GnuTestSyntax "')' expected, found '$($a[$State.Pos])'" }
        $State.Pos++
    }
    elseif ($a.Length - $p -ge 4 -and $a[$p] -ceq '-l' -and (Test-GnuTestBinaryOperator $a[$p + 2])) { $value = Invoke-GnuTestBinary -State $State }
    elseif ($a.Length - $p -ge 3 -and (Test-GnuTestBinaryOperator $a[$p + 1])) { $value = Invoke-GnuTestBinary -State $State }
    elseif ($a[$p].Length -eq 2 -and $a[$p][0] -eq '-') {
        if (-not (Test-GnuTestUnaryOperator $a[$p])) { Stop-GnuTestSyntax "'$($a[$p])': unary operator expected" }
        $value = Invoke-GnuTestUnary -State $State
    }
    else {
        $value = -not [string]::IsNullOrEmpty($a[$p])
        $State.Pos++
    }
    $value -xor $invert
}

function ConvertFrom-GnuTestInteger {
    <#
    .SYNOPSIS
    An integer operand of test (blanks around it allowed), or a syntax error.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $match = [regex]::Match($Text, '^\s*([+-]?\d+)\s*$')
    if (-not $match.Success) { Stop-GnuTestSyntax "invalid integer '$Text'" }
    [System.Numerics.BigInteger]::Parse($match.Groups[1].Value.TrimStart('+'), [System.Globalization.CultureInfo]::InvariantCulture)
}

function Invoke-GnuTestBinary {
    <#
    .SYNOPSIS
    A binary operation at the current position ("-l STRING" may replace integer operands).
    #>
    param([Parameter(Mandatory)][hashtable]$State)

    $a = $State.Args
    $leftIsLength = $false
    if ($a[$State.Pos] -ceq '-l') { $leftIsLength = $true; $State.Pos++ }
    $left = $a[$State.Pos]
    $operator = $a[$State.Pos + 1]
    $State.Pos += 2
    $rightIsLength = $false
    if ($a[$State.Pos] -ceq '-l' -and $State.Pos + 1 -lt $a.Length) { $rightIsLength = $true; $State.Pos++ }
    $right = $a[$State.Pos]
    $State.Pos++

    if ($operator -match '^-(eq|ne|lt|le|gt|ge)$') {
        if ($leftIsLength) { $leftValue = [System.Numerics.BigInteger]$left.Length } else { $leftValue = ConvertFrom-GnuTestInteger -Text $left }
        if ($rightIsLength) { $rightValue = [System.Numerics.BigInteger]$right.Length } else { $rightValue = ConvertFrom-GnuTestInteger -Text $right }
        $order = [System.Numerics.BigInteger]::Compare($leftValue, $rightValue)
        switch -CaseSensitive ($operator) {
            '-eq' { return $order -eq 0 }
            '-ne' { return $order -ne 0 }
            '-lt' { return $order -lt 0 }
            '-le' { return $order -le 0 }
            '-gt' { return $order -gt 0 }
            default { return $order -ge 0 }
        }
    }
    # GNU quirk with string operators: a left -l is ignored, and a right -l shifts the comparison,
    # so the operator itself is compared with STRING ("test 3 = -l abc" compares '=' with 'abc').
    if ($rightIsLength) { $left = $operator }
    switch -CaseSensitive ($operator) {
        { $_ -eq '=' -or $_ -eq '==' } { return [string]::Equals($left, $right, [System.StringComparison]::Ordinal) }
        '!=' { return -not [string]::Equals($left, $right, [System.StringComparison]::Ordinal) }
        '<' { return [string]::CompareOrdinal($left, $right) -lt 0 }
        '>' { return [string]::CompareOrdinal($left, $right) -gt 0 }
        '-ef' {
            $leftPath = Get-GnuCanonicalPath -Path $left -Require all
            $rightPath = Get-GnuCanonicalPath -Path $right -Require all
            return $leftPath.ContainsKey('Path') -and $rightPath.ContainsKey('Path') -and (Test-GnuSamePath -Left $leftPath.Path -Right $rightPath.Path)
        }
        default {
            # -nt / -ot: a missing file is older than any existing one.
            $leftTime = Get-GnuTestModificationTime -Path $left
            $rightTime = Get-GnuTestModificationTime -Path $right
            if ($operator -ceq '-ot') { $leftTime, $rightTime = $rightTime, $leftTime }
            if ($null -eq $leftTime) { return $false }
            if ($null -eq $rightTime) { return $true }
            return $leftTime -gt $rightTime
        }
    }
}

function Get-GnuTestModificationTime {
    <#
    .SYNOPSIS
    The modification time (UTC) of an existing file or directory, or $null.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Path)
    if ([string]::IsNullOrEmpty($Path)) { return $null }
    $full = Resolve-GnuPath -Path $Path
    if ([System.IO.File]::Exists($full)) { return [System.IO.File]::GetLastWriteTimeUtc($full) }
    if ([System.IO.Directory]::Exists($full)) { return [System.IO.Directory]::GetLastWriteTimeUtc($full) }
    $null
}

function Invoke-GnuTestUnary {
    <#
    .SYNOPSIS
    A unary operation at the current position.
    #>
    param([Parameter(Mandatory)][hashtable]$State)

    $operator = $State.Args[$State.Pos]
    Step-GnuTestArgument -State $State -Require
    $operand = $State.Args[$State.Pos]
    $State.Pos++
    switch -CaseSensitive ($operator) {
        '-n' { return -not [string]::IsNullOrEmpty($operand) }
        '-z' { return [string]::IsNullOrEmpty($operand) }
        '-t' { return Test-GnuTerminal -Descriptor ([int](ConvertFrom-GnuTestInteger -Text $operand)) }
        default { return Test-GnuFileCondition -Operator $operator.Substring(1) -Path $operand }
    }
}

function Test-GnuTerminal {
    <#
    .SYNOPSIS
    $true if file descriptor 0, 1 or 2 is a terminal (console), as far as .NET can tell.
    #>
    param([Parameter(Mandatory)][int]$Descriptor)
    switch ($Descriptor) {
        0 { return -not [System.Console]::IsInputRedirected }
        1 { return -not [System.Console]::IsOutputRedirected }
        2 { return -not [System.Console]::IsErrorRedirected }
    }
    $false
}

function Get-GnuUnixModeString {
    <#
    .SYNOPSIS
    The 'ls -l' mode string of a path on Unix (PowerShell 7.1+ UnixMode, like 'crw-rw-rw-'), or nothing.
    #>
    param([Parameter(Mandatory)][string]$Path)
    if (Test-GnuWindows) { return }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -ne $item -and $null -ne $item.PSObject.Properties['UnixMode']) { [string]$item.UnixMode }
}

function Test-GnuFileCondition {
    <#
    .SYNOPSIS
    The file tests of test (-b -c -d -e -f -g -G -h -k -L -N -O -p -r -s -S -u -w -x).
    #>
    param([Parameter(Mandatory)][string]$Operator, [Parameter(Mandatory)][AllowEmptyString()][string]$Path)

    if ([string]::IsNullOrEmpty($Path)) { return $false }
    $full = Resolve-GnuPath -Path $Path
    if ($Operator -ceq 'h' -or $Operator -ceq 'L') { return $null -ne (Get-GnuLinkTarget -Path $full) }

    # Like stat(): links are followed, so a dangling link does not exist.
    $isFile = [System.IO.File]::Exists($full)
    $isDirectory = [System.IO.Directory]::Exists($full)
    if (-not ($isFile -or $isDirectory)) { return $false }
    $mode = Get-GnuUnixModeString -Path $full
    $bits = Get-GnuUnixFileMode -Path $full
    switch -CaseSensitive ($Operator) {
        'e' { return $true }
        'd' { return $isDirectory }
        'f' { return $isFile -and ($null -eq $mode -or $mode.StartsWith('-', [System.StringComparison]::Ordinal)) }
        's' { return $isDirectory -or (New-Object System.IO.FileInfo -ArgumentList $full).Length -gt 0 }
        'b' { return $null -ne $mode -and $mode.StartsWith('b', [System.StringComparison]::Ordinal) }
        'c' { return $null -ne $mode -and $mode.StartsWith('c', [System.StringComparison]::Ordinal) }
        'p' { return $null -ne $mode -and $mode.StartsWith('p', [System.StringComparison]::Ordinal) }
        'S' { return $null -ne $mode -and $mode.StartsWith('s', [System.StringComparison]::Ordinal) }
        'u' { return $null -ne $bits -and ($bits -band 2048) -ne 0 }
        'g' { return $null -ne $bits -and ($bits -band 1024) -ne 0 }
        'k' { return $null -ne $bits -and ($bits -band 512) -ne 0 }
        'N' {
            $info = Get-Item -LiteralPath $full -Force
            return $info.LastWriteTimeUtc -gt $info.LastAccessTimeUtc
        }
        'r' {
            if ($isDirectory) { return $true }
            try { (New-Object System.IO.FileStream -ArgumentList $full, 'Open', 'Read', 'ReadWrite').Dispose(); return $true } catch { return $false }
        }
        'w' {
            if ($null -ne $bits) { return ($bits -band 146) -ne 0 }   # any w bit (0o222)
            if ($isDirectory) { return $true }
            return -not ((Get-Item -LiteralPath $full -Force).Attributes -band [System.IO.FileAttributes]::ReadOnly)
        }
        'x' {
            if ($null -ne $bits) { return ($bits -band 73) -ne 0 }    # any x bit (0o111)
            if ($isDirectory) { return $true }
            $extension = [System.IO.Path]::GetExtension($full)
            $pathExt = '.COM;.EXE;.BAT;.CMD'
            if ($env:PATHEXT) { $pathExt = $env:PATHEXT }
            return -not [string]::IsNullOrEmpty($extension) -and @($pathExt -split ';') -contains $extension
        }
        default { return $true }   # -O / -G: owned by the current user or group (approximation: exists)
    }
}
