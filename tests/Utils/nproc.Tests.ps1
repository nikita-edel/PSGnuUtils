BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'nproc' {
    BeforeEach {
        $script:savedOmp = $env:OMP_NUM_THREADS
        $script:savedLimit = $env:OMP_THREAD_LIMIT
        Remove-Item Env:\OMP_NUM_THREADS -ErrorAction SilentlyContinue
        Remove-Item Env:\OMP_THREAD_LIMIT -ErrorAction SilentlyContinue
    }
    AfterEach {
        $env:OMP_NUM_THREADS = $script:savedOmp
        $env:OMP_THREAD_LIMIT = $script:savedLimit
    }

    It 'prints the processor count' {
        (Invoke-TestGnu nproc).Output | Should -Be @([string][System.Environment]::ProcessorCount)
    }

    It 'subtracts --ignore but never goes below 1' {
        $count = [System.Environment]::ProcessorCount
        (Invoke-TestGnu nproc '--ignore=1').Output | Should -Be @([string][Math]::Max(1, $count - 1))
        (Invoke-TestGnu nproc '--ignore', '100000').Output | Should -Be @('1')
    }

    It 'honors OMP_NUM_THREADS and OMP_THREAD_LIMIT unless --all is given' {
        $env:OMP_NUM_THREADS = '3'
        (Invoke-TestGnu nproc).Output | Should -Be @('3')
        $env:OMP_THREAD_LIMIT = '2'
        (Invoke-TestGnu nproc).Output | Should -Be @('2')
        (Invoke-TestGnu nproc '--all').Output | Should -Be @([string][System.Environment]::ProcessorCount)
    }

    It 'rejects invalid --ignore values and operands' {
        $r = Invoke-TestGnu nproc '--ignore=abc'
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match "invalid number: 'abc'"
        (Invoke-TestGnu nproc 'x').ErrorText | Should -Match "extra operand 'x'"
    }
}
