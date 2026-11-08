BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'groups' {
    It 'prints the group names of the current user and of each USERNAME' {
        Mock -ModuleName PSGnuUtils Get-GnuIdentity {
            if ($User -eq 'ghost') { return $null }
            @{ UserId = '1'; UserName = 'u'; GroupId = '1'; GroupName = 'staff'; Groups = @(@{ Id = '1'; Name = 'staff' }, @{ Id = '42'; Name = $null }) }
        }
        (Invoke-TestGnu groups).Output | Should -Be @('staff 42')
        $r = Invoke-TestGnu groups 'alice', 'ghost'
        $r.Output | Should -Be @('alice : staff 42')
        $r.ErrorText | Should -Match "'ghost': no such user"
        $r.ExitCode | Should -Be 1
    }

    It 'prints the real groups of the current user' {
        (Invoke-TestGnu groups).Output[0] | Should -Not -BeNullOrEmpty
    }
}
