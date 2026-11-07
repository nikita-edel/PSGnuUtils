Register-GnuUtil @{
    Name        = 'link'
    Category    = 'File and directory operations'
    Synopsis    = 'Call the link function to create a link to a file.'
    Usage       = @('link FILE1 FILE2', 'link OPTION')
    Description = @('Call the link function to create a link named FILE2 to an existing FILE1.')
    Notes       = @('PowerShell note: creates an NTFS / POSIX hard link via New-Item -ItemType HardLink.')
}

function Invoke-GnuLink {
    <#
    .SYNOPSIS
    GNU link: create a hard link FILE2 to an existing FILE1.

    .DESCRIPTION
    Exactly two operands. FILE1 must be an existing file and FILE2 must not exist.
    Enable the GNU name with: Enable-GnuUtil link

    .EXAMPLE
    Invoke-GnuLink original.txt copy.txt
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'link' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            $operands = @($ctx.Operands)
            if ($operands.Count -eq 0) { Write-GnuUsageError -Context $ctx -Message 'missing operand' }
            elseif ($operands.Count -eq 1) { Write-GnuUsageError -Context $ctx -Message "missing operand after '$($operands[0])'" }
            elseif ($operands.Count -gt 2) { Write-GnuUsageError -Context $ctx -Message "extra operand '$($operands[2])'" }
            else {
                $source = Resolve-GnuPath -Path $operands[0]
                $target = Resolve-GnuPath -Path $operands[1]
                $prefix = "cannot create link '$($operands[1])' to '$($operands[0])'"
                if ([System.IO.Directory]::Exists($source)) {
                    Write-GnuError -Context $ctx -Message "$($prefix): Operation not permitted"
                }
                elseif (-not [System.IO.File]::Exists($source)) {
                    Write-GnuError -Context $ctx -Message "$($prefix): No such file or directory"
                }
                elseif ([System.IO.File]::Exists($target) -or [System.IO.Directory]::Exists($target)) {
                    Write-GnuError -Context $ctx -Message "$($prefix): File exists"
                }
                else {
                    try {
                        $escaped = [System.Management.Automation.WildcardPattern]::Escape($target)
                        $null = New-Item -ItemType HardLink -Path $escaped -Value $source -ErrorAction Stop
                    }
                    catch {
                        Write-GnuError -Context $ctx -Message "$($prefix): $(Get-GnuErrorReason -Exception $_.Exception)"
                    }
                }
            }
        }
        Complete-GnuUtil -Context $ctx
    }
}
