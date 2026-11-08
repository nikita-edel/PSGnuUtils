Register-GnuUtil (New-GnuChecksumSpec -Name 'sha224sum')

function Invoke-GnuSha224sum {
    <#
    .SYNOPSIS
    GNU sha224sum: compute and check SHA224 message digests.

    .DESCRIPTION
    Prints "<digest>  <file>" for every FILE ('-' or no FILE = pipeline input), or the BSD
    format with --tag. With -c, reads such lines from the FILEs and verifies them
    (--quiet, --status, --warn, --strict and --ignore-missing control the report).
    The digest is computed in PowerShell, as there is no SHA-224 in .NET (slower for large files).
    Enable the GNU name with: Enable-GnuAlias sha224sum

    .EXAMPLE
    Invoke-GnuSha224sum setup.exe

    .EXAMPLE
    Invoke-GnuSha224sum *.zip > SUMS; Invoke-GnuSha224sum -c SUMS
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'sha224sum' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuChecksumUtil -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}
