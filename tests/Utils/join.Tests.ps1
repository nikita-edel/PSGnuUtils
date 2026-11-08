BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# Every expected result below was produced by GNU coreutils join 8.32 with the same files.
Describe 'join' {
    BeforeAll {
        $script:dir = Join-Path $TestDrive 'join'
        $null = New-Item -ItemType Directory -Path $dir -Force
        $null = New-TestFile -Path (Join-Path $dir 'a') -Content "1 apple`n2 banana`n3 cherry`n5 elder`n"
        $null = New-TestFile -Path (Join-Path $dir 'b') -Content "1 red`n2 yellow`n4 green`n5 black`n"
        $null = New-TestFile -Path (Join-Path $dir 'c1') -Content "k,1`nz,2`n"
        $null = New-TestFile -Path (Join-Path $dir 'c2') -Content "k,a`nz,b`n"
        $null = New-TestFile -Path (Join-Path $dir 'j1') -Content "x 1`ny 2`n"
        $null = New-TestFile -Path (Join-Path $dir 'i1') -Content "A x`n"
        $null = New-TestFile -Path (Join-Path $dir 'i2') -Content "a y`n"
        $null = New-TestFile -Path (Join-Path $dir 'h1') -Content "id n`n1 a`n"
        $null = New-TestFile -Path (Join-Path $dir 'h2') -Content "id m`n1 b`n"
        $null = New-TestFile -Path (Join-Path $dir 'u') -Content "2 a`n1 b`n"
        $null = New-TestFile -Path (Join-Path $dir 'r') -Content "1 r x`n"
        $null = New-TestFile -Path (Join-Path $dir 'd1') -Content "1 a`n1 b`n2 c`n"
        $null = New-TestFile -Path (Join-Path $dir 'd2') -Content "1 X`n1 Y`n3 Z`n"
        $null = New-TestFile -Path (Join-Path $dir 'e1') -Content "a,,c`nb,x,y`n"
        $null = New-TestFile -Path (Join-Path $dir 'e2') -Content "a,1`nb,2`n"
        $null = New-TestFile -Path (Join-Path $dir 'u2') -Content "1 a`n3 c`n2 b`n"
    }

    It 'join <Arguments>' -ForEach @(
        @{ Arguments = @('a', 'b'); Output = @('1 apple red', '2 banana yellow', '5 elder black'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('-a1', 'a', 'b'); Output = @('1 apple red', '2 banana yellow', '3 cherry', '5 elder black'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('-a', '2', 'a', 'b'); Output = @('1 apple red', '2 banana yellow', '4 green', '5 elder black'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('-a1', '-a2', '-e', 'X', '-o', '0,1.2,2.2', 'a', 'b'); Output = @('1 apple red', '2 banana yellow', '3 cherry X', '4 X green', '5 elder black'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('-v2', 'a', 'b'); Output = @('4 green'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('-v', '1', '-v', '2', 'a', 'b'); Output = @('3 cherry', '4 green'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('-t,', 'c1', 'c2'); Output = @('k,1,a', 'z,2,b'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('-1', '2', '-2', '1', 'j1', 'b'); Output = @('1 x red', '2 y yellow'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('-j', '1', 'a', 'b'); Output = @('1 apple red', '2 banana yellow', '5 elder black'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('-i', 'i1', 'i2'); Output = @('A x y'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--ignore-case', 'i1', 'i2'); Output = @('A x y'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--header', 'h1', 'h2'); Output = @('id n m', '1 a b'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('u', 'b'); Output = @('2 a yellow'); Errors = @('join: u:2: is not sorted: 1 b', 'join: input is not in sorted order'); ExitCode = 1 }
        @{ Arguments = @('--nocheck-order', 'u', 'b'); Output = @('2 a yellow'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('--check-order', 'u', 'b'); Output = @(); Errors = @('join: u:2: is not sorted: 1 b'); ExitCode = 1 }
        @{ Arguments = @('-o', 'auto', '-a1', '-e', 'Q', 'a', 'r'); Output = @('1 apple r x', '2 banana Q Q', '3 cherry Q Q', '5 elder Q Q'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('d1', 'd2'); Output = @('1 a X', '1 a Y', '1 b X', '1 b Y'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('-a1', '-a2', 'd1', 'd2'); Output = @('1 a X', '1 a Y', '1 b X', '1 b Y', '2 c', '3 Z'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('-t', ',', '-o', '1.1,1.2,1.3,2.2', '-e', 'NA', 'e1', 'e2'); Output = @('a,NA,c,1', 'b,x,y,2'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('-o', '2.2,1.2', 'a', 'b'); Output = @('red apple', 'yellow banana', 'black elder'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('-o', '1.2', '-o', '2.2', 'a', 'b'); Output = @('apple red', 'banana yellow', 'elder black'); Errors = @(); ExitCode = 0 }
        @{ Arguments = @('-a', '1', 'u2', 'b'); Output = @('1 a red', '3 c', '2 b'); Errors = @('join: u2:3: is not sorted: 2 b', 'join: input is not in sorted order'); ExitCode = 1 }
        @{ Arguments = @('--check-order', '-a', '1', 'u2', 'b'); Output = @('1 a red', '3 c'); Errors = @('join: u2:3: is not sorted: 2 b'); ExitCode = 1 }
        @{ Arguments = @('-a', '3', 'a', 'b'); Output = @(); Errors = @('join: invalid field number: ''3'''); ExitCode = 1 }
        @{ Arguments = @('-j', 'x', 'a', 'b'); Output = @(); Errors = @('join: invalid field number: ''x'''); ExitCode = 1 }
        @{ Arguments = @('-o', '3.1', 'a', 'b'); Output = @(); Errors = @('join: invalid file number in field spec: ''3.1'''); ExitCode = 1 }
        @{ Arguments = @('a'); Output = @(); Errors = @('join: missing operand after ''a'''); ExitCode = 1 }
        @{ Arguments = @('a', 'b', 'c'); Output = @(); Errors = @('join: extra operand ''c'''); ExitCode = 1 }
        @{ Arguments = @('-t', 'ab', 'a', 'b'); Output = @(); Errors = @('join: multi-character tab ''ab'''); ExitCode = 1 }
        @{ Arguments = @('-e', 'Q', 'a', 'b'); Output = @('1 apple red', '2 banana yellow', '5 elder black'); Errors = @(); ExitCode = 0 }
    ) {
        $r = Invoke-TestGnu join $Arguments -WorkingDirectory $dir
        $r.Output | Should -Be $Output
        @($r.Errors | Where-Object { $_ -notmatch '^Try ' } | ForEach-Object { ($_ -split "`n")[0] }) | Should -Be $Errors
        $r.ExitCode | Should -Be $ExitCode
    }

    It 'reads standard input, NUL separated lines with -z / --zero-terminated and -t ''''' {
        (Invoke-TestGnu join '-', 'b' -InputObject '1 one', '5 five' -WorkingDirectory $dir).Output | Should -Be @('1 one red', '5 five black')
        $null = New-TestFile -Path (Join-Path $dir 'z1') -Content "1 a`0"
        $null = New-TestFile -Path (Join-Path $dir 'z2') -Content "1 b`0"
        (Invoke-TestGnu join '-z', 'z1', 'z2' -WorkingDirectory $dir).Output | Should -Be @("1 a b`0")
        (Invoke-TestGnu join '--zero-terminated', 'z1', 'z2' -WorkingDirectory $dir).Output | Should -Be @("1 a b`0")
        (Invoke-TestGnu join '-t', '', 'h1', 'h1' -WorkingDirectory $dir).Output | Should -Be @('id n', '1 a')
        (Invoke-TestGnu join '-t', '\0', 'c1', 'c1' -WorkingDirectory $dir).Output | Should -Be @('k,1', 'z,2')
        (Invoke-TestGnu join '-a1', '-e', 'E', 'a', 'nosuch' -WorkingDirectory $dir).ExitCode | Should -Be 1
        (Invoke-TestGnu join '-o', '0', '-a', '2', '-e', 'E', 'r', 'b' -WorkingDirectory $dir).Output | Should -Be @('1', '2', '4', '5')
        $null = New-TestFile -Path (Join-Path $dir 't1') -Content "1 x`n9 y`n3 z`n"
        $null = New-TestFile -Path (Join-Path $dir 't2') -Content "1 q`n"
        $r = Invoke-TestGnu join '--check-order', 't1', 't2' -WorkingDirectory $dir
        $r.Output | Should -Be @('1 x q')
        $r.ErrorText | Should -Be 'join: t1:3: is not sorted: 3 z'
        $null = New-TestFile -Path (Join-Path $dir 'ic') -Content "B 1`na 2`n"
        $null = New-TestFile -Path (Join-Path $dir 'ic2') -Content "a 9`nb 8`n"
        (Invoke-TestGnu join '-i', '--check-order', 'ic', 'ic2' -WorkingDirectory $dir).ErrorText | Should -Be 'join: ic:2: is not sorted: a 2'
        (Invoke-TestGnu join '-1', '3', '-a1', 'a', 'b' -WorkingDirectory $dir).Output | Should -Be @(' 1 apple', ' 2 banana', ' 3 cherry', ' 5 elder')
        (Invoke-TestGnu join '-1', '3', '-a1', '-e', 'Q', 'a', 'b' -WorkingDirectory $dir).Output | Should -Be @('Q 1 apple', 'Q 2 banana', 'Q 3 cherry', 'Q 5 elder')
        $r = Invoke-TestGnu join -WorkingDirectory $dir
        $r.ErrorText | Should -Match 'missing operand'
        $r.ExitCode | Should -Be 1
        (Invoke-TestGnu join '-o', 'x', 'a', 'b' -WorkingDirectory $dir).ErrorText | Should -Match "invalid field specifier: 'x'"
        (Invoke-TestGnu join '-o', '1.0', 'a', 'b' -WorkingDirectory $dir).ErrorText | Should -Match "invalid field number: '0'"
    }
}
