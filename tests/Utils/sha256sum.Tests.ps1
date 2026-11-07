BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# The test cases live in Checksum.Suite.ps1 (shared by all *sum utils).
. (Join-Path -Path $PSScriptRoot -ChildPath 'Checksum.Suite.ps1')

Invoke-ChecksumSuite -Util 'sha256sum' -Tag 'SHA256' `
    -AbcHash 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' `
    -EmptyHash 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' `
    -Factory { [System.Security.Cryptography.SHA256]::Create() }
