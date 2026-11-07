BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# Expected orders come from GNU coreutils tsort.
Describe 'tsort' {
    It 'sorts pairs topologically in the GNU order' {
        $r = Invoke-TestGnu tsort -InputObject 'a b', 'b c', 'd d', 'x y', 'c e'
        $r.Output | Should -Be @('a', 'd', 'x', 'b', 'y', 'c', 'e')
        $r.ExitCode | Should -Be 0
    }

    It 'accepts any whitespace and repeated pairs' {
        (Invoke-TestGnu tsort -InputObject "a b`ta b b c", 'a c').Output | Should -Be @('a', 'b', 'c')
        (Invoke-TestGnu tsort -InputObject 'z a y b x c w d 3 1 2 3').Output | Should -Be @('2', 'w', 'x', 'y', 'z', '3', 'd', 'c', 'b', 'a', '1')
    }

    It 'reports loops, breaks them and still prints every item' {
        $r = Invoke-TestGnu tsort -InputObject 'a b', 'b a'
        $r.Output | Should -Be @('a', 'b')
        $r.Errors | Should -Be @('tsort: -: input contains a loop:', 'tsort: a', 'tsort: b')
        $r.ExitCode | Should -Be 1
    }

    It 'handles several loops' {
        $r = Invoke-TestGnu tsort -InputObject 'a b', 'b c', 'c a', 'c d', 'd e', 'e c', 'x x', 'm n n m'
        $r.Output | Should -Be @('x', 'd', 'e', 'a', 'b', 'c', 'm', 'n')
        @($r.Errors | Where-Object { $_ -match 'input contains a loop' }).Count | Should -Be 3
    }

    It 'rejects an odd number of tokens' {
        $r = Invoke-TestGnu tsort -InputObject 'a b c'
        $r.ErrorText | Should -Be 'tsort: -: input contains an odd number of tokens'
        $r.Output | Should -BeNullOrEmpty
        $r.ExitCode | Should -Be 1
    }

    It 'reads a file and rejects extra operands' {
        $file = New-TestFile -Path (Join-Path $TestDrive 'pairs.txt') -Content "b c`na b`n"
        (Invoke-TestGnu tsort $file).Output | Should -Be @('a', 'b', 'c')
        (Invoke-TestGnu tsort $file, 'x').ErrorText | Should -Match "extra operand 'x'"
        (Invoke-TestGnu tsort (Join-Path $TestDrive 'nope')).ExitCode | Should -Be 1
    }

    It 'prints nothing for empty input' {
        (Invoke-TestGnu tsort -InputObject '').Output | Should -BeNullOrEmpty
    }
}
