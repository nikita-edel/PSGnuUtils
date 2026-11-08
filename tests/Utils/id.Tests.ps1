BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'id' {
    Context 'with a known identity' {
        BeforeEach {
            Mock -ModuleName PSGnuUtils Get-GnuIdentity {
                if ($User -eq 'ghost') { return $null }
                if ($User -eq 'bare') { return @{ UserId = 'S-1'; UserName = 'HOST\bare'; GroupId = $null; GroupName = $null; Groups = @() } }
                $uid = '1000'
                if ($Real) { $uid = '0' }
                @{ UserId = $uid; UserName = 'alice'; GroupId = '1000'; GroupName = 'alice'; Groups = @(@{ Id = '1000'; Name = 'alice' }, @{ Id = '27'; Name = 'sudo' }, @{ Id = '99'; Name = $null }) }
            }
        }

        It 'prints uid, gid and groups by default (-a is ignored)' {
            (Invoke-TestGnu id).Output | Should -Be @('uid=1000(alice) gid=1000(alice) groups=1000(alice),27(sudo),99')
            (Invoke-TestGnu id '-a', 'alice').Output | Should -Be @('uid=1000(alice) gid=1000(alice) groups=1000(alice),27(sudo),99')
            (Invoke-TestGnu id 'bare').Output | Should -Be @('uid=S-1(HOST\bare)')
        }

        It 'prints only the user with -u / --user, names with -n / --name, real ids with -r / --real' {
            (Invoke-TestGnu id '-u').Output | Should -Be @('1000')
            (Invoke-TestGnu id '--user', '--name').Output | Should -Be @('alice')
            (Invoke-TestGnu id '-ur').Output | Should -Be @('0')
            (Invoke-TestGnu id '-u', '--real').Output | Should -Be @('0')
        }

        It 'prints only the group with -g / --group' {
            (Invoke-TestGnu id '-g').Output | Should -Be @('1000')
            (Invoke-TestGnu id '--group', '-n').Output | Should -Be @('alice')
        }

        It 'prints all groups with -G / --groups' {
            (Invoke-TestGnu id '-G').Output | Should -Be @('1000 27 99')
            (Invoke-TestGnu id '--groups', '-n').Output | Should -Be @('alice sudo 99')
            (Invoke-TestGnu id '-Gz').Output | Should -Be @("1000`027`099`0")
            (Invoke-TestGnu id '-u', '--zero', 'alice', 'alice').Output | Should -Be @("1000`01000`0")
        }

        It 'reports unknown users' {
            $r = Invoke-TestGnu id 'ghost', 'alice'
            $r.ErrorText | Should -Match "'ghost': no such user"
            $r.Output | Should -Be @('uid=1000(alice) gid=1000(alice) groups=1000(alice),27(sudo),99')
            $r.ExitCode | Should -Be 1
        }

        It 'rejects invalid option combinations' {
            (Invoke-TestGnu id '-u', '-g').ErrorText | Should -Match 'cannot print "only" of more than one choice'
            (Invoke-TestGnu id '-n').ErrorText | Should -Match 'cannot print only names or real IDs in default format'
            (Invoke-TestGnu id '-z').ErrorText | Should -Match 'option --zero not permitted in default format'
            (Invoke-TestGnu id '-Z').ErrorText | Should -Match 'SELinux'
            (Invoke-TestGnu id '--context').ExitCode | Should -Be 1
        }
    }

    It 'prints the real identity of the current user' {
        $r = Invoke-TestGnu id
        $r.Output[0] | Should -Match '^uid=\S+'
        (Invoke-TestGnu id '-un').Output[0] | Should -Not -BeNullOrEmpty
    }
}

Describe 'Identity helpers' {
    BeforeAll {
        $script:dir = Join-Path $TestDrive 'etc'
        $null = New-Item -ItemType Directory -Path $dir -Force
        $script:status = New-TestFile -Path (Join-Path $dir 'status') -Content "Name:`tbash`nUid:`t1000`t1001`t1001`t1001`nGid:`t100`t101`t101`t101`nGroups:`t101 27 999`n"
        $script:passwd = New-TestFile -Path (Join-Path $dir 'passwd') -Content "# comment`n`nroot:x:0:0:root:/root:/bin/bash`nalice:x:1001:101::/home/alice:/bin/sh`nbob:x:1002:100::/home/bob:/bin/sh`n"
        $script:group = New-TestFile -Path (Join-Path $dir 'group') -Content "root:x:0:`nusers:x:100:`nalice:x:101:`nsudo:x:27:alice,bob`n"
    }

    It 'reads the Linux identity of the current process' {
        $identity = InModuleScope PSGnuUtils -Parameters @{ S = $status; P = $passwd; G = $group } { param($S, $P, $G) Get-GnuLinuxIdentity -StatusPath $S -PasswdPath $P -GroupPath $G }
        $identity.UserId | Should -Be '1001'
        $identity.UserName | Should -Be 'alice'
        $identity.GroupName | Should -Be 'alice'
        @($identity.Groups | ForEach-Object { $_.Id }) | Should -Be @('101', '27', '999')
        @($identity.Groups | ForEach-Object { $_.Name }) | Should -Be @('alice', 'sudo', $null)
        $real = InModuleScope PSGnuUtils -Parameters @{ S = $status; P = $passwd; G = $group } { param($S, $P, $G) Get-GnuLinuxIdentity -Real -StatusPath $S -PasswdPath $P -GroupPath $G }
        $real.UserId | Should -Be '1000'
        $real.UserName | Should -BeNullOrEmpty
        $real.GroupName | Should -Be 'users'
    }

    It 'reads other Linux users from the passwd and group files' {
        $identity = InModuleScope PSGnuUtils -Parameters @{ S = $status; P = $passwd; G = $group } { param($S, $P, $G) Get-GnuLinuxIdentity -User 'bob' -StatusPath $S -PasswdPath $P -GroupPath $G }
        $identity.UserId | Should -Be '1002'
        @($identity.Groups | ForEach-Object { $_.Name }) | Should -Be @('users', 'sudo')
        $byId = InModuleScope PSGnuUtils -Parameters @{ S = $status; P = $passwd; G = $group } { param($S, $P, $G) Get-GnuLinuxIdentity -User '0' -StatusPath $S -PasswdPath $P -GroupPath $G }
        $byId.UserName | Should -Be 'root'
        InModuleScope PSGnuUtils -Parameters @{ S = $status; P = $passwd; G = $group } { param($S, $P, $G) Get-GnuLinuxIdentity -User 'ghost' -StatusPath $S -PasswdPath $P -GroupPath $G } | Should -BeNullOrEmpty
        InModuleScope PSGnuUtils { @(Read-GnuColonFile -Path (Join-Path $TestDrive 'missing')).Count } | Should -Be 0
    }

    It 'chooses the identity source for the platform' {
        InModuleScope PSGnuUtils {
            Mock Test-GnuWindows { $true }
            Mock Get-GnuWindowsIdentity { @{ UserId = 'win' } }
            (Get-GnuIdentity).UserId | Should -Be 'win'
        }
        InModuleScope PSGnuUtils {
            Mock Test-GnuWindows { $false }
            Mock Get-GnuLinuxIdentity { @{ UserId = 'linux' } }
            Mock Get-GnuNativeIdentity { @{ UserId = 'native' } }
            $expected = 'native'
            if ([System.IO.File]::Exists('/proc/self/status')) { $expected = 'linux' }
            (Get-GnuIdentity).UserId | Should -Be $expected
        }
    }

    It 'reads the Windows identity' {
        if (-not (Test-IsWindowsPlatform)) { Set-ItResult -Skipped -Because 'Windows only'; return }
        InModuleScope PSGnuUtils {
            $identity = Get-GnuWindowsIdentity
            $identity.UserId | Should -Match '^S-1-'
            $identity.GroupId | Should -Match '-513$'
            @($identity.Groups | Where-Object { $_.Id -eq $identity.GroupId }).Count | Should -Be 1
            (Get-GnuWindowsIdentity -User 'SYSTEM').UserId | Should -Be 'S-1-5-18'
            Get-GnuWindowsIdentity -User 'no-such-user-xyz-123' | Should -BeNullOrEmpty
            ConvertTo-GnuAccountName -Sid (New-Object System.Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-21-1-2-3-999') | Should -BeNullOrEmpty
        }
    }
}
