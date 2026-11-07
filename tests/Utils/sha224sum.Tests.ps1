BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# The test cases live in Checksum.Suite.ps1 (shared by all *sum utils).
. (Join-Path -Path $PSScriptRoot -ChildPath 'Checksum.Suite.ps1')

# .NET has no SHA-224, so the reference hasher of the suite is the module's own implementation;
# the vectors below (from Python's hashlib) check that implementation.
Invoke-ChecksumSuite -Util 'sha224sum' -Tag 'SHA224' `
    -AbcHash '23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7' `
    -EmptyHash 'd14a028c2a3a2bc9476102bb288234c415a2b01f828ea62ac5b3e42f' `
    -Factory {
    New-Module -AsCustomObject -ScriptBlock {
        function ComputeHash { param([byte[]]$Bytes) & (Get-Module PSGnuUtils) { param($Data) Get-GnuSha224 -Bytes $Data } $Bytes }
        function Dispose { }
    }
}

Describe 'Get-GnuSha224' {
    It 'hashes <Name>' -ForEach @(
        @{ Name = 'hello LF'; Bytes = [byte[]][System.Text.Encoding]::ASCII.GetBytes("hello`n"); Expected = '2d6d67d91d0badcdd06cbbba1fe11538a68a37ec9c2e26457ceff12b' }
        @{ Name = '1000 a (16 blocks)'; Bytes = [byte[]][System.Text.Encoding]::ASCII.GetBytes('a' * 1000); Expected = '4e8f0ce90b64661a2b5e84be6d93a7d9b76871062f1814433d04a03d' }
        @{ Name = 'every byte value 3 times'; Bytes = [byte[]](@(0..255) * 3); Expected = '591b51555cc8c83f6951d9ec73d834d6d17865fecdb543605471a562' }
    ) {
        $digest = InModuleScope PSGnuUtils -Parameters @{ Bytes = $Bytes } { param($Bytes) Get-GnuSha224 -Bytes $Bytes }
        ([System.BitConverter]::ToString([byte[]]$digest) -replace '-', '').ToLowerInvariant() | Should -Be $Expected
    }
}
