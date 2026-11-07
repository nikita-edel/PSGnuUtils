BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# The test cases live in Checksum.Suite.ps1 (shared by all *sum utils).
. (Join-Path -Path $PSScriptRoot -ChildPath 'Checksum.Suite.ps1')

Invoke-ChecksumSuite -Util 'sha1sum' -Tag 'SHA1' `
    -AbcHash 'a9993e364706816aba3e25717850c26c9cd0d89d' `
    -EmptyHash 'da39a3ee5e6b4b0d3255bfef95601890afd80709' `
    -Factory { [System.Security.Cryptography.SHA1]::Create() }
