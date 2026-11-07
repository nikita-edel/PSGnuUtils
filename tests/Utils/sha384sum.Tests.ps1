BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# The test cases live in Checksum.Suite.ps1 (shared by all *sum utils).
. (Join-Path -Path $PSScriptRoot -ChildPath 'Checksum.Suite.ps1')

Invoke-ChecksumSuite -Util 'sha384sum' -Tag 'SHA384' `
    -AbcHash 'cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7' `
    -EmptyHash '38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b' `
    -Factory { [System.Security.Cryptography.SHA384]::Create() }
