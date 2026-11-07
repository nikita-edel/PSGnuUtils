Register-GnuUtil (New-GnuBaseEncodingSpec -Name 'base32')

function Invoke-GnuBase32 {
    <#
    .SYNOPSIS
    GNU base32: base32 encode or decode data.

    .DESCRIPTION
    Encodes FILE (or pipeline input) as base32, wrapped at 76 columns (-w COLS, 0 = no wrapping).
    With -d, decodes base32 input; -i ignores characters outside the base32 alphabet.
    Pipeline input is encoded as UTF-8 text with a LF after every line.
    Enable the GNU name with: Enable-GnuUtil base32

    .EXAMPLE
    'hello' | Invoke-GnuBase32

    .EXAMPLE
    Invoke-GnuBase32 -d encoded.txt
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'base32' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuBaseEncodingUtil -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}
