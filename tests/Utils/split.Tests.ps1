BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')

    function New-SplitDirectory {
        # A fresh directory with the input files of the GNU comparison.
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $null = New-Item -ItemType Directory -Path $dir
        $null = New-TestFile -Path (Join-Path $dir 'n') -Content ((1..25 | ForEach-Object { "$_`n" }) -join '')
        $null = New-TestFile -Path (Join-Path $dir 'comma') -Content 'a,b,c'
        $null = New-TestFile -Path (Join-Path $dir 'big') -Content ((1..2000 | ForEach-Object { "$_`n" }) -join '')
        $null = New-TestFile -Path (Join-Path $dir 'long') -Content "short`nthis line is definitely longer than twenty bytes`nend`n"
        $dir
    }

    function Get-SplitFile {
        param([string]$Directory)
        @(Get-ChildItem -LiteralPath $Directory -File | Where-Object { @('n', 'comma', 'big', 'long') -notcontains $_.Name } |
                Sort-Object -Property Name | ForEach-Object { "$($_.Name):$($_.Length)" })
    }
}

# Every expected result below was produced by GNU coreutils split 8.32 with the same input files.
Describe 'split' {
    It 'split <Arguments>' -ForEach @(
        @{ Arguments = @('-l', '10', 'n'); Output = @(); Errors = @(); ExitCode = 0; Files = @('xaa:21', 'xab:30', 'xac:15') }
        @{ Arguments = @('-b', '20', '-d', 'n', 'part'); Output = @(); Errors = @(); ExitCode = 0; Files = @('part00:20', 'part01:20', 'part02:20', 'part03:6') }
        @{ Arguments = @('-n', '3', 'n', 'chunk'); Output = @(); Errors = @(); ExitCode = 0; Files = @('chunkaa:22', 'chunkab:22', 'chunkac:22') }
        @{ Arguments = @('-l', '10', '-a', '3', '--additional-suffix=.txt', 'n', 's_'); Output = @(); Errors = @(); ExitCode = 0; Files = @('s_aaa.txt:21', 's_aab.txt:30', 's_aac.txt:15') }
        @{ Arguments = @('-n', 'l/3', 'n', 'L'); Output = @(); Errors = @(); ExitCode = 0; Files = @('Laa:24', 'Lab:21', 'Lac:21') }
        @{ Arguments = @('-C', '20', 'n', 'C'); Output = @(); Errors = @(); ExitCode = 0; Files = @('Caa:18', 'Cab:18', 'Cac:18', 'Cad:12') }
        @{ Arguments = @('--verbose', '-l', '20', 'n', 'v'); Output = @('creating file ''vaa''', 'creating file ''vab'''); Errors = @(); ExitCode = 0; Files = @('vaa:51', 'vab:15') }
        @{ Arguments = @('-l', '0', 'n'); Output = @(); Errors = @('split: invalid number of lines: ''0'': Numerical result out of range'); ExitCode = 1; Files = @() }
        @{ Arguments = @('-e', '-n', '30', 'n', 'e'); Output = @(); Errors = @(); ExitCode = 0; Files = @('eaa:2', 'eab:2', 'eac:2', 'ead:2', 'eae:2', 'eaf:2', 'eag:2', 'eah:2', 'eai:2', 'eaj:2', 'eak:2', 'eal:2', 'eam:2', 'ean:2', 'eao:2', 'eap:2', 'eaq:2', 'ear:2', 'eas:2', 'eat:2', 'eau:2', 'eav:2', 'eaw:2', 'eax:2', 'eay:2', 'eaz:2', 'eba:2', 'ebb:2', 'ebc:2', 'ebd:8') }
        @{ Arguments = @('-n', 'r/3', 'n', 'R'); Output = @(); Errors = @(); ExitCode = 0; Files = @('Raa:24', 'Rab:21', 'Rac:21') }
        @{ Arguments = @('-x', '-l', '10', 'n', 'hx'); Output = @(); Errors = @(); ExitCode = 0; Files = @('hx00:21', 'hx01:30', 'hx02:15') }
        @{ Arguments = @('--numeric-suffixes=5', '-l', '10', 'n', 'ns'); Output = @(); Errors = @(); ExitCode = 0; Files = @('ns05:21', 'ns06:30', 'ns07:15') }
        @{ Arguments = @('-t', ',', '-l', '1', 'comma', 'T'); Output = @(); Errors = @(); ExitCode = 0; Files = @('Taa:2', 'Tab:2', 'Tac:1') }
        @{ Arguments = @('-C', '20', 'long', 'lb'); Output = @(); Errors = @(); ExitCode = 0; Files = @('lbaa:6', 'lbab:20', 'lbac:20', 'lbad:13') }
        @{ Arguments = @('-n', '2/3', 'n'); Output = @('1', '12', '13', '14', '15', '16', '17', '18'); Errors = @(); ExitCode = 0; Files = @() }
        @{ Arguments = @('-n', 'l/2/3', 'n'); Output = @('12', '13', '14', '15', '16', '17', '18'); Errors = @(); ExitCode = 0; Files = @() }
        @{ Arguments = @('-n', 'r/2/3', 'n'); Output = @('2', '5', '8', '11', '14', '17', '20', '23'); Errors = @(); ExitCode = 0; Files = @() }
        @{ Arguments = @('-n', '4/3', 'n'); Output = @(); Errors = @('split: invalid chunk number: ''4'': Numerical result out of range'); ExitCode = 1; Files = @() }
        @{ Arguments = @('-n', '0', 'n'); Output = @(); Errors = @('split: invalid number of chunks: ''0'': Numerical result out of range'); ExitCode = 1; Files = @() }
        @{ Arguments = @('-l', '5', '-b', '5', 'n'); Output = @(); Errors = @('split: cannot split in more than one way'); ExitCode = 1; Files = @() }
        @{ Arguments = @('-a', '1', '-n', '30', 'n', 'z'); Output = @(); Errors = @('split: the suffix length needs to be at least 2'); ExitCode = 1; Files = @() }
        @{ Arguments = @('-b', '1K', 'big', 'kb'); Output = @(); Errors = @(); ExitCode = 0; Files = @('kbaa:1024', 'kbab:1024', 'kbac:1024', 'kbad:1024', 'kbae:1024', 'kbaf:1024', 'kbag:1024', 'kbah:1024', 'kbai:701') }
        @{ Arguments = @('--lines=10', 'n', 'lines'); Output = @(); Errors = @(); ExitCode = 0; Files = @('linesaa:21', 'linesab:30', 'linesac:15') }
        @{ Arguments = @('--bytes=30', 'n', 'bb'); Output = @(); Errors = @(); ExitCode = 0; Files = @('bbaa:30', 'bbab:30', 'bbac:6') }
        @{ Arguments = @('--number=2', 'n', 'nn'); Output = @(); Errors = @(); ExitCode = 0; Files = @('nnaa:33', 'nnab:33') }
        @{ Arguments = @('--line-bytes=30', 'n', 'lbb'); Output = @(); Errors = @(); ExitCode = 0; Files = @('lbbaa:30', 'lbbab:30', 'lbbac:6') }
        @{ Arguments = @('--suffix-length=4', 'n', 'sl'); Output = @(); Errors = @(); ExitCode = 0; Files = @('slaaaa:66') }
        @{ Arguments = @('--elide-empty-files', '-n', 'l/5', 'long', 'el'); Output = @(); Errors = @(); ExitCode = 0; Files = @('elaa:55', 'elab:4') }
        @{ Arguments = @('--separator=,', '--lines=2', 'comma', 'sep'); Output = @(); Errors = @(); ExitCode = 0; Files = @('sepaa:4', 'sepab:1') }
        @{ Arguments = @('-u', '-n', 'r/2', 'n', 'un'); Output = @(); Errors = @(); ExitCode = 0; Files = @('unaa:34', 'unab:32') }
        @{ Arguments = @('-l', 'x', 'n'); Output = @(); Errors = @('split: invalid number of lines: ''x'''); ExitCode = 1; Files = @() }
        @{ Arguments = @('-t', 'ab', 'n'); Output = @(); Errors = @('split: multi-character separator ''ab'''); ExitCode = 1; Files = @() }
        @{ Arguments = @('n', 'a', 'b'); Output = @(); Errors = @('split: extra operand ''b'''); ExitCode = 1; Files = @() }
    ) {
        $dir = New-SplitDirectory
        $r = Invoke-TestGnu split $Arguments -WorkingDirectory $dir
        $r.Output | Should -Be $Output
        @($r.Errors | ForEach-Object { ($_ -split "`n")[0] }) | Should -Be $Errors
        $r.ExitCode | Should -Be $ExitCode
        Get-SplitFile -Directory $dir | Should -Be $Files
    }

    It 'widens alphabetic and numeric suffixes like GNU' {
        $dir = New-SplitDirectory
        $null = Invoke-TestGnu split '-l', '3', 'big', 'auto' -WorkingDirectory $dir
        $names = @(Get-ChildItem -LiteralPath $dir -Filter 'auto*' -Name | Sort-Object)
        $names.Count | Should -Be 667
        $names[649] | Should -Be 'autoyz'
        $names[650] | Should -Be 'autozaaa'
        $null = Invoke-TestGnu split '-d', '-l', '3', 'big', 'dauto' -WorkingDirectory $dir
        $names = @(Get-ChildItem -LiteralPath $dir -Filter 'dauto*' -Name | Sort-Object)
        $names[89] | Should -Be 'dauto89'
        $names[90] | Should -Be 'dauto9000'
        $r = Invoke-TestGnu split '-l', '1', '-a', '1', 'big', 'tiny' -WorkingDirectory $dir
        $r.ErrorText | Should -Be 'split: output file suffixes exhausted'
        @(Get-ChildItem -LiteralPath $dir -Filter 'tiny*').Count | Should -Be 26
    }

    It 'reads standard input and counts hex suffixes from FROM' {
        $dir = New-SplitDirectory
        $null = Invoke-TestGnu split '-l', '1', '-', 'in_' -InputObject 'a', 'b' -WorkingDirectory $dir
        @(Get-ChildItem -LiteralPath $dir -Filter 'in_*' -Name | Sort-Object) | Should -Be @('in_aa', 'in_ab')
        $null = Invoke-TestGnu split '--hex-suffixes=a', '-l', '10', 'n', 'hh' -WorkingDirectory $dir
        @(Get-ChildItem -LiteralPath $dir -Filter 'hh*' -Name | Sort-Object) | Should -Be @('hh0a', 'hh0b', 'hh0c')
        $null = Invoke-TestGnu split '--numeric-suffixes=5', '-n', '3', 'n', 'c' -WorkingDirectory $dir
        @(Get-ChildItem -LiteralPath $dir -Filter 'c*' -Name | Where-Object { $_ -ne 'comma' } | Sort-Object) | Should -Be @('c05', 'c06', 'c07')
        $null = Invoke-TestGnu split '--numeric-suffixes', '-l', '10', 'n', 'z' -WorkingDirectory $dir
        @(Get-ChildItem -LiteralPath $dir -Filter 'z*' -Name | Sort-Object) | Should -Be @('z00', 'z01', 'z02')
    }

    It 'reports problems like GNU' {
        $dir = New-SplitDirectory
        (Invoke-TestGnu split '--filter=cat', 'n' -WorkingDirectory $dir).ErrorText | Should -Match '--filter is not supported'
        (Invoke-TestGnu split '-a', 'x', 'n' -WorkingDirectory $dir).ErrorText | Should -Match "invalid suffix length: 'x'"
        (Invoke-TestGnu split '-a', '1', '-n', '30', 'n' -WorkingDirectory $dir).ErrorText | Should -Match 'the suffix length needs to be at least 2'
        (Invoke-TestGnu split '--numeric-suffixes=x', 'n' -WorkingDirectory $dir).ErrorText | Should -Match "invalid number: 'x'"
        (Invoke-TestGnu split '--additional-suffix=a/b', 'n' -WorkingDirectory $dir).ErrorText | Should -Match 'contains directory separator'
        (Invoke-TestGnu split '-n', 'x', 'n' -WorkingDirectory $dir).ErrorText | Should -Match "invalid number of chunks: 'x'"
        (Invoke-TestGnu split '-b', 'x', 'n' -WorkingDirectory $dir).ErrorText | Should -Match "invalid number of bytes: 'x'"
        (Invoke-TestGnu split '-t', '', 'n' -WorkingDirectory $dir).ErrorText | Should -Match 'empty record separator'
        (Invoke-TestGnu split '-t', '\0', '-l', '1', 'n', 'nul' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu split 'nosuch' -WorkingDirectory $dir).ExitCode | Should -Be 1
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'xaa')
        (Invoke-TestGnu split 'n' -WorkingDirectory $dir).ExitCode | Should -Be 1
    }

    It 'refuses to overwrite its input' {
        $dir = New-SplitDirectory
        $null = New-TestFile -Path (Join-Path $dir 'xaa') -Content "1`n2`n"
        $r = Invoke-TestGnu split '-l', '1', 'xaa' -WorkingDirectory $dir
        $r.ErrorText | Should -Be "split: 'xaa' would overwrite input; aborting"
        $r.ExitCode | Should -Be 1
    }
}
