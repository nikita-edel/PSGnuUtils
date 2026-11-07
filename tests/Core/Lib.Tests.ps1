BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'ConvertFrom-GnuSize' {
    It 'parses <Text> as <Expected>' -ForEach @(
        @{ Text = '10'; Expected = 10 }
        @{ Text = '2b'; Expected = 1024 }
        @{ Text = '1K'; Expected = 1024 }
        @{ Text = '1k'; Expected = 1024 }
        @{ Text = '1KiB'; Expected = 1024 }
        @{ Text = '1kB'; Expected = 1000 }
        @{ Text = '1KB'; Expected = 1000 }
        @{ Text = '2M'; Expected = 2097152 }
        @{ Text = '1MB'; Expected = 1000000 }
        @{ Text = '1G'; Expected = 1073741824 }
        @{ Text = '1T'; Expected = 1099511627776 }
    ) {
        InModuleScope PSGnuUtils -Parameters @{ Text = $Text } { param($Text) ConvertFrom-GnuSize -Text $Text } | Should -Be $Expected
    }

    It 'rejects <Text>' -ForEach @(@{ Text = '' }, @{ Text = 'abc' }, @{ Text = '1X' }, @{ Text = '1Kx' }, @{ Text = '-1' }, @{ Text = '1.5' }) {
        InModuleScope PSGnuUtils -Parameters @{ Text = $Text } { param($Text) ConvertFrom-GnuSize -Text $Text } | Should -BeNullOrEmpty
    }

    It 'clamps huge values' {
        InModuleScope PSGnuUtils {
            ConvertFrom-GnuSize -Text '1Q' | Should -Be ([decimal]::MaxValue)
            ConvertFrom-GnuSize -Text '99999999999999999999999999999999' | Should -Be ([decimal]::MaxValue)
            ConvertTo-GnuInt64 -Value ([decimal]::MaxValue) | Should -Be ([long]::MaxValue)
            ConvertTo-GnuInt64 -Value ([decimal]::MinValue) | Should -Be ([long]::MinValue)
            ConvertTo-GnuInt64 -Value 42 | Should -Be 42
        }
    }
}

Describe 'ConvertFrom-GnuEscape' {
    It 'interprets <Text>' -ForEach @(
        @{ Text = 'a\tb'; Expected = "a`tb" }
        @{ Text = 'a\nb'; Expected = "a`nb" }
        @{ Text = '\\'; Expected = '\' }
        @{ Text = '\x41\x4a'; Expected = 'AJ' }
        @{ Text = '\0101'; Expected = 'A' }
        @{ Text = '\0'; Expected = [string][char]0 }
        @{ Text = '\a\b\e\f\r\v'; Expected = [string]([char]7) + [char]8 + [char]27 + [char]12 + [char]13 + [char]11 }
        @{ Text = '\q'; Expected = '\q' }
        @{ Text = '\x'; Expected = '\x' }
        @{ Text = 'end\'; Expected = 'end\' }
    ) {
        $result = InModuleScope PSGnuUtils -Parameters @{ Text = $Text } { param($Text) ConvertFrom-GnuEscape -Text $Text }
        $result.Text | Should -BeExactly $Expected
        $result.Stop | Should -BeFalse
    }

    It 'stops at \c' {
        $result = InModuleScope PSGnuUtils { ConvertFrom-GnuEscape -Text 'ab\cde' }
        $result.Text | Should -BeExactly 'ab'
        $result.Stop | Should -BeTrue
    }
}

Describe 'Base32' {
    It 'encodes the RFC 4648 test vector <Plain>' -ForEach @(
        @{ Plain = ''; Encoded = '' }
        @{ Plain = 'f'; Encoded = 'MY======' }
        @{ Plain = 'fo'; Encoded = 'MZXQ====' }
        @{ Plain = 'foo'; Encoded = 'MZXW6===' }
        @{ Plain = 'foob'; Encoded = 'MZXW6YQ=' }
        @{ Plain = 'fooba'; Encoded = 'MZXW6YTB' }
        @{ Plain = 'foobar'; Encoded = 'MZXW6YTBOI======' }
    ) {
        InModuleScope PSGnuUtils -Parameters @{ Plain = $Plain; Encoded = $Encoded } {
            param($Plain, $Encoded)
            ConvertTo-GnuBase32 -Bytes ([System.Text.Encoding]::ASCII.GetBytes($Plain)) | Should -BeExactly $Encoded
            $decoded = ConvertFrom-GnuBase32 -Text $Encoded
            [System.Text.Encoding]::ASCII.GetString($decoded) | Should -BeExactly $Plain
        }
    }

    It 'rejects invalid input <Text>' -ForEach @(@{ Text = 'MZXW6YT' }, @{ Text = 'MZ======MZXW6YTB' }, @{ Text = 'mzxw6ytb' }, @{ Text = 'M=======' }) {
        InModuleScope PSGnuUtils -Parameters @{ Text = $Text } { param($Text) ConvertFrom-GnuBase32 -Text $Text } | Should -BeNullOrEmpty
    }
}

Describe 'Format-GnuFloat' {
    It 'formats <Value> with %<Flags><Width>.<Precision><Conversion> as <Expected>' -ForEach @(
        @{ Value = 3.14159; Conversion = 'f'; Precision = 2; Flags = ''; Width = 0; Expected = '3.14' }
        @{ Value = 1.0; Conversion = 'f'; Precision = -1; Flags = ''; Width = 0; Expected = '1.000000' }
        @{ Value = 1234.5; Conversion = 'e'; Precision = 2; Flags = ''; Width = 0; Expected = '1.23e+03' }
        @{ Value = 0.000123; Conversion = 'E'; Precision = 1; Flags = ''; Width = 0; Expected = '1.2E-04' }
        @{ Value = 100000; Conversion = 'g'; Precision = -1; Flags = ''; Width = 0; Expected = '100000' }
        @{ Value = 1000000; Conversion = 'g'; Precision = -1; Flags = ''; Width = 0; Expected = '1e+06' }
        @{ Value = 0.0001; Conversion = 'g'; Precision = -1; Flags = ''; Width = 0; Expected = '0.0001' }
        @{ Value = 0.00001; Conversion = 'G'; Precision = -1; Flags = ''; Width = 0; Expected = '1E-05' }
        @{ Value = 1.5; Conversion = 'g'; Precision = -1; Flags = ''; Width = 0; Expected = '1.5' }
        @{ Value = 2; Conversion = 'g'; Precision = 3; Flags = '#'; Width = 0; Expected = '2.00' }
        @{ Value = 0; Conversion = 'g'; Precision = 0; Flags = ''; Width = 0; Expected = '0' }
        @{ Value = -2.5; Conversion = 'f'; Precision = 1; Flags = ''; Width = 6; Expected = '  -2.5' }
        @{ Value = 2.5; Conversion = 'f'; Precision = 1; Flags = '0'; Width = 6; Expected = '0002.5' }
        @{ Value = -2.5; Conversion = 'f'; Precision = 1; Flags = '0'; Width = 6; Expected = '-002.5' }
        @{ Value = 2.5; Conversion = 'f'; Precision = 1; Flags = '-'; Width = 6; Expected = '2.5   ' }
        @{ Value = 2.5; Conversion = 'f'; Precision = 1; Flags = '+'; Width = 0; Expected = '+2.5' }
        @{ Value = 2.5; Conversion = 'f'; Precision = 1; Flags = ' '; Width = 0; Expected = ' 2.5' }
    ) {
        $parameters = @{ Value = $Value; Conversion = $Conversion; Precision = $Precision; Flags = $Flags; Width = $Width }
        InModuleScope PSGnuUtils -Parameters $parameters {
            param($Value, $Conversion, $Precision, $Flags, $Width)
            Format-GnuFloat -Value $Value -Conversion $Conversion -Precision $Precision -Flags $Flags -Width $Width
        } | Should -BeExactly $Expected
    }

    It 'formats infinity and NaN' {
        InModuleScope PSGnuUtils {
            Format-GnuFloat -Value ([double]::PositiveInfinity) -Conversion 'f' | Should -BeExactly 'inf'
            Format-GnuFloat -Value ([double]::NaN) -Conversion 'G' | Should -BeExactly 'NAN'
        }
    }

    It 'reads the scale of decimals' {
        InModuleScope PSGnuUtils {
            # [decimal]'1.50' would drop the trailing zero; Parse keeps the scale.
            $invariant = [System.Globalization.CultureInfo]::InvariantCulture
            Get-GnuDecimalScale -Value ([decimal]::Parse('1.50', $invariant)) | Should -Be 2
            Get-GnuDecimalScale -Value ([decimal]::Parse('7', $invariant)) | Should -Be 0
        }
    }
}

Describe 'Checksum line parsing' {
    It 'parses GNU, binary-marker and BSD lines' {
        InModuleScope PSGnuUtils {
            $hash = 'd41d8cd98f00b204e9800998ecf8427e'
            (ConvertFrom-GnuChecksumLine -Line "$hash  file.txt" -Tag 'MD5' -HexLength 32).Name | Should -Be 'file.txt'
            (ConvertFrom-GnuChecksumLine -Line "$hash *bin.dat" -Tag 'MD5' -HexLength 32).Name | Should -Be 'bin.dat'
            (ConvertFrom-GnuChecksumLine -Line "MD5 (x y) = $hash" -Tag 'MD5' -HexLength 32).Name | Should -Be 'x y'
            (ConvertFrom-GnuChecksumLine -Line ("\$hash  a\\b\nc") -Tag 'MD5' -HexLength 32).Name | Should -BeExactly "a\b`nc"
            (ConvertFrom-GnuChecksumLine -Line ("\$hash  a\rb\qc") -Tag 'MD5' -HexLength 32).Name | Should -BeExactly "a`rb\qc"
            ConvertFrom-GnuChecksumLine -Line 'garbage' -Tag 'MD5' -HexLength 32 | Should -BeNullOrEmpty
            ConvertFrom-GnuChecksumLine -Line "abc  short" -Tag 'MD5' -HexLength 32 | Should -BeNullOrEmpty
        }
    }

    It 'escapes names with backslashes and newlines' {
        InModuleScope PSGnuUtils {
            $escaped = ConvertTo-GnuChecksumName -Name "a\b`nc"
            $escaped.Escaped | Should -BeTrue
            $escaped.Name | Should -BeExactly 'a\\b\nc'
            (ConvertTo-GnuChecksumName -Name 'plain').Escaped | Should -BeFalse
        }
    }
}
