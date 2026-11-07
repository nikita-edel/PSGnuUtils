BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'uname' {
    BeforeAll {
        $script:info = InModuleScope PSGnuUtils { Get-GnuOsInfo }
    }

    It 'prints the kernel name by default and with -s / --kernel-name' {
        (Invoke-TestGnu uname).Output | Should -Be @($info.KernelName)
        (Invoke-TestGnu uname '-s').Output | Should -Be @($info.KernelName)
        (Invoke-TestGnu uname '--kernel-name').Output | Should -Be @($info.KernelName)
    }

    It 'prints single fields' {
        (Invoke-TestGnu uname '-n').Output | Should -Be @($info.NodeName)
        (Invoke-TestGnu uname '--nodename').Output | Should -Be @($info.NodeName)
        (Invoke-TestGnu uname '-r').Output | Should -Be @($info.KernelRelease)
        (Invoke-TestGnu uname '--kernel-release').Output | Should -Be @($info.KernelRelease)
        (Invoke-TestGnu uname '-v').Output | Should -Be @($info.KernelVersion)
        (Invoke-TestGnu uname '--kernel-version').Output | Should -Be @($info.KernelVersion)
        (Invoke-TestGnu uname '-m').Output | Should -Be @($info.Machine)
        (Invoke-TestGnu uname '--machine').Output | Should -Be @($info.Machine)
        (Invoke-TestGnu uname '-p').Output | Should -Be @('unknown')
        (Invoke-TestGnu uname '--processor').Output | Should -Be @('unknown')
        (Invoke-TestGnu uname '-i').Output | Should -Be @('unknown')
        (Invoke-TestGnu uname '--hardware-platform').Output | Should -Be @('unknown')
        (Invoke-TestGnu uname '-o').Output | Should -Be @($info.OperatingSystem)
        (Invoke-TestGnu uname '--operating-system').Output | Should -Be @($info.OperatingSystem)
    }

    It 'prints fields in GNU order regardless of option order' {
        (Invoke-TestGnu uname '-ms').Output | Should -Be @("$($info.KernelName) $($info.Machine)")
    }

    It 'prints everything except unknown fields with -a / --all' {
        $expected = @($info.KernelName, $info.NodeName, $info.KernelRelease, $info.KernelVersion, $info.Machine, $info.OperatingSystem) -join ' '
        (Invoke-TestGnu uname '-a').Output | Should -Be @($expected)
        (Invoke-TestGnu uname '--all').Output | Should -Be @($expected)
    }

    It 'rejects operands' {
        $r = Invoke-TestGnu uname 'x'
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match "extra operand 'x'"
    }
}
