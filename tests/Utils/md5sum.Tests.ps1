BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# The test cases live in Checksum.Suite.ps1 (shared by all *sum utils).
. (Join-Path -Path $PSScriptRoot -ChildPath 'Checksum.Suite.ps1')

Invoke-ChecksumSuite -Util 'md5sum' -Tag 'MD5' `
    -AbcHash '900150983cd24fb0d6963f7d28e17f72' `
    -EmptyHash 'd41d8cd98f00b204e9800998ecf8427e' `
    -Factory { [System.Security.Cryptography.MD5]::Create() }
