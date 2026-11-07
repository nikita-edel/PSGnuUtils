BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'printenv' {
    BeforeAll {
        $env:PSGNUUTILS_TEST_A = 'alpha'
        $env:PSGNUUTILS_TEST_B = 'beta'
    }
    AfterAll {
        Remove-Item Env:\PSGNUUTILS_TEST_A, Env:\PSGNUUTILS_TEST_B -ErrorAction SilentlyContinue
    }

    It 'prints the values of the named variables' {
        $r = Invoke-TestGnu printenv 'PSGNUUTILS_TEST_A', 'PSGNUUTILS_TEST_B'
        $r.Output | Should -Be @('alpha', 'beta')
        $r.ExitCode | Should -Be 0
    }

    It 'exits with 1 if a variable is missing but prints the others' {
        $r = Invoke-TestGnu printenv 'PSGNUUTILS_TEST_A', 'PSGNUUTILS_TEST_MISSING', 'A=B'
        $r.Output | Should -Be @('alpha')
        $r.ExitCode | Should -Be 1
        $r.Errors.Count | Should -Be 0
    }

    It 'prints all variables as NAME=value sorted by name' {
        $r = Invoke-TestGnu printenv
        $r.Output | Should -Contain 'PSGNUUTILS_TEST_A=alpha'
        $names = @($r.Output | ForEach-Object { $_.Split('=')[0] })
        $sorted = [string[]]$names.Clone()
        [System.Array]::Sort($sorted, [System.StringComparer]::Ordinal)
        $names | Should -Be $sorted
    }

    It 'ends records with NUL for -0 / --null' {
        (Invoke-TestGnu printenv '-0', 'PSGNUUTILS_TEST_A', 'PSGNUUTILS_TEST_B').Output | Should -Be @("alpha`0beta`0")
        (Invoke-TestGnu printenv '--null', 'PSGNUUTILS_TEST_A').Output | Should -Be @("alpha`0")
    }
}
