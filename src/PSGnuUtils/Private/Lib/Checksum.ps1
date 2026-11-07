# Shared implementation of md5sum, sha1sum, sha256sum, sha384sum and sha512sum.

$script:GnuChecksumAlgorithms = @{
    md5sum    = @{ Tag = 'MD5'; Bits = 128; Factory = { [System.Security.Cryptography.MD5]::Create() } }
    sha1sum   = @{ Tag = 'SHA1'; Bits = 160; Factory = { [System.Security.Cryptography.SHA1]::Create() } }
    sha256sum = @{ Tag = 'SHA256'; Bits = 256; Factory = { [System.Security.Cryptography.SHA256]::Create() } }
    sha384sum = @{ Tag = 'SHA384'; Bits = 384; Factory = { [System.Security.Cryptography.SHA384]::Create() } }
    sha512sum = @{ Tag = 'SHA512'; Bits = 512; Factory = { [System.Security.Cryptography.SHA512]::Create() } }
    sha224sum = @{ Tag = 'SHA224'; Bits = 224; Compute = { param([byte[]]$Bytes) Get-GnuSha224 -Bytes $Bytes } }
}

function New-GnuChecksumSpec {
    <#
    .SYNOPSIS
    The registry spec shared by all *sum utils.
    #>
    param([Parameter(Mandatory)][string]$Name)

    $tag = $script:GnuChecksumAlgorithms[$Name].Tag
    @{
        Name         = $Name
        Category     = 'Checksums'
        Synopsis     = "Compute and check $tag message digests."
        Usage        = @("$Name [OPTION]... [FILE]...")
        Description  = @("Print or check $tag checksums.", '', 'With no FILE, or when FILE is -, read standard input.')
        FileOperands = $true
        Options      = @(
            @{ Short = 'b'; Long = 'binary'; Key = 'mode'; Value = 'binary'; Help = 'read in binary mode' }
            @{ Short = 'c'; Long = 'check'; Help = "read checksums from the FILEs and check them" }
            @{ Long = 'tag'; Help = 'create a BSD-style checksum' }
            @{ Short = 't'; Long = 'text'; Key = 'mode'; Value = 'text'; Help = 'read in text mode (default)' }
            @{ Short = 'z'; Long = 'zero'; Help = 'end each output line with NUL, not newline, and disable file name escaping' }
            @{ Long = 'ignore-missing'; Help = "don't fail or report status for missing files" }
            @{ Long = 'quiet'; Help = "don't print OK for each successfully verified file" }
            @{ Long = 'status'; Help = "don't output anything, status code shows success" }
            @{ Long = 'strict'; Help = 'exit non-zero for improperly formatted checksum lines' }
            @{ Short = 'w'; Long = 'warn'; Help = 'warn about improperly formatted checksum lines' }
        )
        Notes        = @(
            'The last five options are useful only when verifying checksums.',
            'When checking, the input should be a former output of this program.',
            'The default mode is to print a line with: checksum, a space,',
            "a character indicating input mode ('*' for binary, ' ' for text",
            'or where binary is insignificant), and name for each FILE.',
            '',
            'PowerShell note: binary and text mode read the same bytes (as on GNU/Linux).'
        )
    }
}

function Get-GnuChecksumHex {
    <#
    .SYNOPSIS
    Computes the lowercase hex digest of one input, or returns nothing if it cannot be read.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Operand,
        [Parameter(Mandatory)][hashtable]$Algorithm,
        [switch]$Quiet
    )

    $stream = Open-GnuInputStream -Context $Context -Operand $Operand -Quiet:$Quiet
    if ($null -eq $stream) { return }
    if ($Algorithm.ContainsKey('Compute')) {
        # Algorithms .NET does not have are implemented in PowerShell and hash a byte array.
        $buffer = New-Object System.IO.MemoryStream
        try { $stream.CopyTo($buffer) } finally { $stream.Dispose() }
        $digest = & $Algorithm.Compute $buffer.ToArray()
    }
    else {
        $hasher = & $Algorithm.Factory
        try {
            $digest = $hasher.ComputeHash($stream)
        }
        finally {
            $hasher.Dispose()
            $stream.Dispose()
        }
    }
    [System.BitConverter]::ToString($digest).Replace('-', '').ToLowerInvariant()
}

function ConvertTo-GnuChecksumName {
    <#
    .SYNOPSIS
    Escapes a file name like GNU does (backslash, LF, CR). Returns @{ Name; Escaped }.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Name)

    if ($Name.IndexOf('\', [System.StringComparison]::Ordinal) -lt 0 -and $Name.IndexOf("`n", [System.StringComparison]::Ordinal) -lt 0 -and $Name.IndexOf("`r", [System.StringComparison]::Ordinal) -lt 0) {
        return @{ Name = $Name; Escaped = $false }
    }
    @{ Name = $Name.Replace('\', '\\').Replace("`n", '\n').Replace("`r", '\r'); Escaped = $true }
}

function ConvertFrom-GnuChecksumLine {
    <#
    .SYNOPSIS
    Parses one line of a checksum file (GNU or BSD --tag format). Returns @{ Hash; Name } or nothing.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Line,
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][int]$HexLength
    )

    $escaped = $false
    if ($Line.StartsWith('\', [System.StringComparison]::Ordinal)) {
        $escaped = $true
        $Line = $Line.Substring(1)
    }

    $hex = "[0-9A-Fa-f]{$HexLength}"
    $hash = $null
    $name = $null
    if ($Line -match ('^' + [regex]::Escape($Tag) + ' \((.*)\) = (' + $hex + ')$')) {
        $name = $Matches[1]
        $hash = $Matches[2]
    }
    elseif ($Line -match ('^(' + $hex + ') [ *](.+)$')) {
        $hash = $Matches[1]
        $name = $Matches[2]
    }
    else {
        return
    }

    if ($escaped) {
        $name = [regex]::Replace($name, '\\(.)', {
                param($match)
                switch -CaseSensitive ($match.Groups[1].Value) {
                    'n' { "`n" }
                    'r' { "`r" }
                    '\' { '\' }
                    default { $match.Value }
                }
            })
    }
    @{ Hash = $hash.ToLowerInvariant(); Name = $name }
}

function Invoke-GnuChecksumUtil {
    <#
    .SYNOPSIS
    Entry point shared by the *sum utils: prints digests or verifies checksum files (--check).
    #>
    param([Parameter(Mandatory)][hashtable]$Context)

    $algorithm = $script:GnuChecksumAlgorithms[$Context.Name]
    $operands = @($Context.Operands)
    if ($operands.Count -eq 0) { $operands = @('-') }

    $check = Test-GnuOption -Context $Context -Key 'check'
    if ($check -and (Test-GnuOption -Context $Context -Key 'tag')) {
        Write-GnuUsageError -Context $Context -Message 'the --tag option is meaningless when verifying checksums'
        return
    }
    if (-not $check) {
        foreach ($key in @('ignore-missing', 'quiet', 'status', 'strict', 'warn')) {
            if (Test-GnuOption -Context $Context -Key $key) {
                Write-GnuUsageError -Context $Context -Message "the --$key option is meaningful only when verifying checksums"
                return
            }
        }
    }

    if ($check) {
        Test-GnuChecksumList -Context $Context -Algorithm $algorithm -Operands $operands
        return
    }

    $zero = Test-GnuOption -Context $Context -Key 'zero'
    $marker = ' '
    if ((Get-GnuOptionValue -Context $Context -Key 'mode' -Default 'text') -eq 'binary') { $marker = '*' }

    $records = foreach ($operand in $operands) {
        $hash = Get-GnuChecksumHex -Context $Context -Operand $operand -Algorithm $algorithm
        if ($null -eq $hash) { continue }
        $name = @{ Name = $operand; Escaped = $false }
        if (-not $zero) { $name = ConvertTo-GnuChecksumName -Name $operand }
        $prefix = ''
        if ($name.Escaped) { $prefix = '\' }
        if (Test-GnuOption -Context $Context -Key 'tag') { "$prefix$($algorithm.Tag) ($($name.Name)) = $hash" }
        else { "$prefix$hash $marker$($name.Name)" }
    }
    ConvertTo-GnuRecordOutput -Record $records -Zero:$zero
}

function Test-GnuChecksumList {
    <#
    .SYNOPSIS
    Implements --check: verifies every entry of the given checksum files.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][hashtable]$Algorithm,
        [Parameter(Mandatory)][string[]]$Operands
    )

    $quiet = Test-GnuOption -Context $Context -Key 'quiet'
    $status = Test-GnuOption -Context $Context -Key 'status'
    $warn = Test-GnuOption -Context $Context -Key 'warn'
    $strict = Test-GnuOption -Context $Context -Key 'strict'
    $ignoreMissing = Test-GnuOption -Context $Context -Key 'ignore-missing'
    $hexLength = [int]($Algorithm.Bits / 4)

    foreach ($listOperand in $Operands) {
        $errorsBefore = $Context.ErrorCount
        $lines = @(Get-GnuInputLine -Context $Context -Operand $listOperand)
        if ($Context.ErrorCount -gt $errorsBefore) { continue }
        $displayName = Get-GnuDisplayName -Operand $listOperand

        $formatted = 0
        $improper = 0
        $unreadable = 0
        $mismatched = 0
        $verified = 0
        for ($lineNumber = 1; $lineNumber -le $lines.Count; $lineNumber++) {
            $entry = ConvertFrom-GnuChecksumLine -Line $lines[$lineNumber - 1] -Tag $Algorithm.Tag -HexLength $hexLength
            if ($null -eq $entry) {
                $improper++
                if ($warn) { Write-GnuWarning -Context $Context -Message "$($displayName): $($lineNumber): improperly formatted $($Algorithm.Tag) checksum line" }
                continue
            }
            $formatted++

            $missing = $entry.Name -ne '-' -and -not [System.IO.File]::Exists((Resolve-GnuPath -Path $entry.Name))
            if ($missing -and $ignoreMissing) { continue }

            $actual = Get-GnuChecksumHex -Context $Context -Operand $entry.Name -Algorithm $Algorithm -Quiet:$status
            if ($null -eq $actual) {
                $unreadable++
                if (-not $status) { "$($entry.Name): FAILED open or read" }
                continue
            }
            $verified++
            if ($actual -eq $entry.Hash) {
                if (-not $quiet -and -not $status) { "$($entry.Name): OK" }
            }
            else {
                $mismatched++
                if (-not $status) { "$($entry.Name): FAILED" }
            }
        }

        if ($formatted -eq 0) {
            Write-GnuError -Context $Context -Message "$($displayName): no properly formatted checksum lines found"
            continue
        }

        if (-not $status) {
            if ($improper -gt 0) {
                $text = "$improper lines are improperly formatted"
                if ($improper -eq 1) { $text = '1 line is improperly formatted' }
                Write-GnuWarning -Context $Context -Message $text
            }
            if ($unreadable -gt 0) {
                $text = "$unreadable listed files could not be read"
                if ($unreadable -eq 1) { $text = '1 listed file could not be read' }
                Write-GnuWarning -Context $Context -Message $text
            }
            if ($mismatched -gt 0) {
                $text = "$mismatched computed checksums did NOT match"
                if ($mismatched -eq 1) { $text = '1 computed checksum did NOT match' }
                Write-GnuWarning -Context $Context -Message $text
            }
        }

        if ($ignoreMissing -and $verified -eq 0) {
            Write-GnuError -Context $Context -Message "$($displayName): no file was verified"
        }
        if ($mismatched -gt 0 -or $unreadable -gt 0 -or ($strict -and $improper -gt 0)) {
            if ($Context.ExitCode -lt 1) { $Context.ExitCode = 1 }
        }
    }
}
