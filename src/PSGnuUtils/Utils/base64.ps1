Register-GnuUtil (New-GnuBaseEncodingSpec -Name 'base64')

function Invoke-GnuBase64 {
    <#
    .SYNOPSIS
    GNU base64: base64 encode or decode data.

    .DESCRIPTION
    Encodes FILE (or pipeline input) as base64, wrapped at 76 columns (-w COLS, 0 = no wrapping).
    With -d, decodes base64 input; -i ignores characters outside the base64 alphabet.
    Pipeline input is encoded as UTF-8 text with a LF after every line.
    Enable the GNU name with: Enable-GnuAlias base64

    .EXAMPLE
    'hello' | Invoke-GnuBase64

    .EXAMPLE
    Invoke-GnuBase64 -d encoded.txt
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'base64' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    process { if (-not $ctx.Done) { Add-GnuPipelineInput -Context $ctx -InputObject $_ } }
    end {
        if (-not $ctx.Done) { Invoke-GnuBaseEncodingUtil -Context $ctx }
        Complete-GnuUtil -Context $ctx
    }
}
