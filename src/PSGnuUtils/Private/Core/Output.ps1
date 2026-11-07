# Output helpers.
#
# Output model (see docs/ARCHITECTURE.md): utils write one string per output line to the
# PowerShell pipeline. Whether the last line ended with a newline cannot be represented.
# NUL-terminated output (-z / -0 / --null) is emitted as a single string in which every
# record is followed by a NUL character.

function ConvertTo-GnuOutputLine {
    <#
    .SYNOPSIS
    Splits text into output lines (LF or CRLF). A trailing newline does not produce an extra empty line.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return }
    $lines = $Text -split "`r?`n"
    $count = $lines.Count
    if ($Text.EndsWith("`n")) { $count-- }
    for ($i = 0; $i -lt $count; $i++) { $lines[$i] }
}

function ConvertTo-GnuRecordOutput {
    <#
    .SYNOPSIS
    Emits records as lines, or as one NUL-terminated string when Zero is set.
    #>
    param(
        [AllowNull()][AllowEmptyCollection()][object[]]$Record,
        [switch]$Zero
    )

    $items = @(foreach ($item in $Record) { if ($null -ne $item) { [string]$item } })
    if (-not $Zero) {
        $items
        return
    }
    if ($items.Count -gt 0) { ($items -join "`0") + "`0" }
}

function Split-GnuRecord {
    <#
    .SYNOPSIS
    Splits text into records terminated by Separator (default LF). A final terminator does not create an empty record.
    #>
    param(
        [AllowEmptyString()][string]$Text,
        [string]$Separator = "`n"
    )

    if ($Text -eq '') { return }
    $parts = $Text.Split([string[]]@($Separator), [System.StringSplitOptions]::None)
    $count = $parts.Length
    if ($Text.EndsWith($Separator)) { $count-- }
    for ($i = 0; $i -lt $count; $i++) { $parts[$i] }
}
