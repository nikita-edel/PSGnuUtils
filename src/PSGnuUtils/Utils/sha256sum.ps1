Register-GnuUtil (New-GnuChecksumSpec -Name 'sha256sum')

function Invoke-GnuSha256sum {
    <#
    .SYNOPSIS
    GNU sha256sum: compute and check SHA256 message digests.

    .DESCRIPTION
    Prints "<digest>  <file>" for every FILE ('-' or no FILE = pipeline input), or the BSD
    format with --tag. With -c, reads such lines from the FILEs and verifies them
    (--quiet, --status, --warn, --strict and --ignore-missing control the report).
    Pipeline input is hashed as UTF-8 text with a LF after every line.
    Enable the GNU name with: Enable-GnuUtil sha256sum

    .EXAMPLE
    Invoke-GnuSha256sum setup.exe

    .EXAMPLE
    Invoke-GnuSha256sum *.zip > SUMS; Invoke-GnuSha256sum -c SUMS
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'sha256sum' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuChecksumUtil -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}
