# SHA-224 (FIPS 180-4): SHA-256 with different initial values, truncated to 224 bits.
# .NET has no SHA-224, so it is implemented here (64-bit integers masked to 32 bits).

$script:GnuSha256K = [long[]]@(@(
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
) | ForEach-Object { $_ -band 0xFFFFFFFFL })   # PowerShell reads 0x80000000.. literals as negative Int32

function Get-GnuRotateRight {
    param([long]$Value, [int]$Bits)
    (($Value -shr $Bits) -bor ($Value -shl (32 - $Bits))) -band 0xFFFFFFFFL
}

function Get-GnuSha224 {
    <#
    .SYNOPSIS
    The SHA-224 digest of a byte array, as a byte array.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)

    $mask = 0xFFFFFFFFL
    $state = [long[]]@(@(0xc1059ed8, 0x367cd507, 0x3070dd17, 0xf70e5939, 0xffc00b31, 0x68581511, 0x64f98fa7, 0xbefa4fa4) | ForEach-Object { $_ -band $mask })
    # Padding: 0x80, zeros, 64-bit big-endian bit length.
    $length = [long]$Bytes.Length
    $paddedLength = [int]([Math]::Floor(($length + 8) / 64) + 1) * 64
    $data = New-Object byte[] $paddedLength
    [System.Array]::Copy($Bytes, $data, $length)
    $data[$length] = 0x80
    $bits = $length * 8
    for ($i = 0; $i -lt 8; $i++) { $data[$paddedLength - 1 - $i] = [byte](($bits -shr (8 * $i)) -band 0xFF) }

    $w = New-Object long[] 64
    for ($block = 0; $block -lt $paddedLength; $block += 64) {
        for ($t = 0; $t -lt 16; $t++) {
            $o = $block + 4 * $t
            $w[$t] = ([long]$data[$o] -shl 24) -bor ([long]$data[$o + 1] -shl 16) -bor ([long]$data[$o + 2] -shl 8) -bor [long]$data[$o + 3]
        }
        for ($t = 16; $t -lt 64; $t++) {
            $s0 = (Get-GnuRotateRight $w[$t - 15] 7) -bxor (Get-GnuRotateRight $w[$t - 15] 18) -bxor ($w[$t - 15] -shr 3)
            $s1 = (Get-GnuRotateRight $w[$t - 2] 17) -bxor (Get-GnuRotateRight $w[$t - 2] 19) -bxor ($w[$t - 2] -shr 10)
            $w[$t] = ($w[$t - 16] + $s0 + $w[$t - 7] + $s1) -band $mask
        }
        $a, $b, $c, $d, $e, $f, $g, $h = $state
        for ($t = 0; $t -lt 64; $t++) {
            $sum1 = (Get-GnuRotateRight $e 6) -bxor (Get-GnuRotateRight $e 11) -bxor (Get-GnuRotateRight $e 25)
            $choice = ($e -band $f) -bxor ((-bnot $e -band $mask) -band $g)
            $temp1 = ($h + $sum1 + $choice + $script:GnuSha256K[$t] + $w[$t]) -band $mask
            $sum0 = (Get-GnuRotateRight $a 2) -bxor (Get-GnuRotateRight $a 13) -bxor (Get-GnuRotateRight $a 22)
            $majority = ($a -band $b) -bxor ($a -band $c) -bxor ($b -band $c)
            $temp2 = ($sum0 + $majority) -band $mask
            $h = $g; $g = $f; $f = $e
            $e = ($d + $temp1) -band $mask
            $d = $c; $c = $b; $b = $a
            $a = ($temp1 + $temp2) -band $mask
        }
        $values = @($a, $b, $c, $d, $e, $f, $g, $h)
        for ($i = 0; $i -lt 8; $i++) { $state[$i] = ($state[$i] + $values[$i]) -band $mask }
    }

    $digest = New-Object byte[] 28
    for ($i = 0; $i -lt 7; $i++) {
        for ($j = 0; $j -lt 4; $j++) { $digest[4 * $i + $j] = [byte](($state[$i] -shr (24 - 8 * $j)) -band 0xFF) }
    }
    , $digest
}
