BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
    $script:shell = (Get-Process -Id $PID).Path
}

Describe 'env' {
    AfterEach {
        # env must always restore the environment.
        $env:PSGNU_TEST_A | Should -BeNullOrEmpty
    }

    It 'prints the environment sorted by name' {
        $env:PSGNU_TEST_PRINT = 'shown'
        try { (Invoke-TestGnu env).Output | Should -Contain 'PSGNU_TEST_PRINT=shown' }
        finally { Remove-Item Env:\PSGNU_TEST_PRINT }
    }

    It 'starts empty with -i / --ignore-environment or -' {
        (Invoke-TestGnu env '-i', 'PSGNU_TEST_B=2', 'PSGNU_TEST_A=1').Output | Should -Be @('PSGNU_TEST_A=1', 'PSGNU_TEST_B=2')
        (Invoke-TestGnu env '--ignore-environment', 'PSGNU_TEST_A=x').Output | Should -Be @('PSGNU_TEST_A=x')
        (Invoke-TestGnu env '-', 'PSGNU_TEST_A=y').Output | Should -Be @('PSGNU_TEST_A=y')
        $env:PATH | Should -Not -BeNullOrEmpty
    }

    It 'ends lines with NUL with -0 / --null' {
        (Invoke-TestGnu env '-0', '-i', 'PSGNU_TEST_A=1', 'PSGNU_TEST_B=2').Output | Should -Be @("PSGNU_TEST_A=1`0PSGNU_TEST_B=2`0")
        (Invoke-TestGnu env '--null', '-i').Output | Should -BeNullOrEmpty
    }

    It 'removes variables with -u / --unset' {
        $env:PSGNU_TEST_U = 'gone'
        try {
            (Invoke-TestGnu env '-u', 'PSGNU_TEST_U').Output | Should -Not -Contain 'PSGNU_TEST_U=gone'
            (Invoke-TestGnu env '--unset=PSGNU_TEST_U').Output | Should -Not -Contain 'PSGNU_TEST_U=gone'
            $env:PSGNU_TEST_U | Should -Be 'gone'
        }
        finally { Remove-Item Env:\PSGNU_TEST_U }
        $r = Invoke-TestGnu env '-u', 'A=B'
        $r.ErrorText | Should -Match "cannot unset 'A=B': Invalid argument"
        $r.ExitCode | Should -Be 125
    }

    It 'runs native programs with the modified environment' {
        $r = Invoke-TestGnu env 'PSGNU_TEST_A=hello', $shell, '-NoProfile', '-Command', 'echo $env:PSGNU_TEST_A; exit 4'
        $r.Output | Should -Be @('hello')
        $r.ExitCode | Should -Be 4
        (Invoke-TestGnu env $shell, '-NoProfile', '-Command', '$input | ForEach-Object { ''in:'' + $_ }' -InputObject 'p', 'q').Output | Should -Be @('in:p', 'in:q')
    }

    It 'runs PowerShell commands, with pipeline input' {
        (Invoke-TestGnu env 'PSGNU_TEST_A=1', 'Write-Output', 'hi').Output | Should -Be @('hi')
        (Invoke-TestGnu env 'Select-Object', '-Last', '1' -InputObject 'a', 'b').Output | Should -Be @('b')
        (Invoke-TestGnu env 'Get-Item', '-LiteralPath', (Join-Path $TestDrive 'nope')).ExitCode | Should -Be 1
        $r = Invoke-TestGnu env 'Get-Item', '-LiteralPath', (Join-Path $TestDrive 'nope'), '-ErrorAction', 'Stop'
        $r.ExitCode | Should -Be 126
    }

    It 'changes the directory with -C / --chdir' {
        (Invoke-TestGnu env '-C', $TestDrive, $shell, '-NoProfile', '-Command', '(Get-Location).Path').Output | Should -Be @($TestDrive)
        (Invoke-TestGnu env "--chdir=$TestDrive", 'Get-Location').Output | Should -Be @($TestDrive)
        $r = Invoke-TestGnu env '-C', (Join-Path $TestDrive 'nope'), 'Get-Date'
        $r.ErrorText | Should -Match 'cannot change directory'
        $r.ExitCode | Should -Be 125
    }

    It 'splits a string into arguments with -S / --split-string' {
        (Invoke-TestGnu env '-i', '-S', 'PSGNU_TEST_A=1 PSGNU_TEST_B=2').Output | Should -Be @('PSGNU_TEST_A=1', 'PSGNU_TEST_B=2')
        (Invoke-TestGnu env '--split-string=Write-Output "a b" ''c d''').Output | Should -Be @('a b', 'c d')
        InModuleScope PSGnuUtils {
            $backslash = [string][char]92
            $env:PSGNU_TEST_S = 'val'
            try {
                (Split-GnuEnvString -Text ('x' + $backslash + 't' + $backslash + 'n ${PSGNU_TEST_S} # comment')).Arguments | Should -Be @("x`t`n", 'val')
                (Split-GnuEnvString -Text ('a' + $backslash + '_b "c' + $backslash + '_d"')).Arguments | Should -Be @('a', 'b', 'c d')
                (Split-GnuEnvString -Text ('one two' + $backslash + 'c three')).Arguments | Should -Be @('one', 'two')
                (Split-GnuEnvString -Text ($backslash + 'r' + $backslash + 'f' + $backslash + 'v' + $backslash + '$' + $backslash + '#' + $backslash + $backslash)).Arguments | Should -Be @("`r$([char]12)$([char]11)`$#$backslash")
                (Split-GnuEnvString -Text ($backslash + 'q')).Error | Should -Match 'invalid sequence'
                (Split-GnuEnvString -Text '$HOME').Error | Should -Match 'only \$\{VARNAME\} expansion is supported'
                (Split-GnuEnvString -Text '"open').Error | Should -Match 'no terminating quote'
                (Split-GnuEnvString -Text '').Arguments | Should -BeNullOrEmpty
            }
            finally { Remove-Item Env:\PSGNU_TEST_S }
        }
        $r = Invoke-TestGnu env '-S', '"open'
        $r.ErrorText | Should -Match 'no terminating quote'
        $r.ExitCode | Should -Be 125
    }

    It 'reports bad combinations and missing commands' {
        (Invoke-TestGnu env '-0', 'Get-Date').ErrorText | Should -Match 'cannot specify --null \(-0\) with command'
        (Invoke-TestGnu env '-C', $TestDrive).ErrorText | Should -Match 'must specify command with --chdir \(-C\)'
        $r = Invoke-TestGnu env 'no-such-command-xyz'
        $r.ErrorText | Should -Match "'no-such-command-xyz': No such file or directory"
        $r.ExitCode | Should -Be 127
    }
}
