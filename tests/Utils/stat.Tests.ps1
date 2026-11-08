BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'stat' {
    BeforeAll {
        $script:dir = Join-Path $TestDrive 'stat'
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'sub') -Force
        $script:file = New-TestFile -Path (Join-Path $dir 'f') -Content "hello`n"
        $null = New-TestFile -Path (Join-Path $dir 'e') -Content ''
        $null = New-TestFile -Path (Join-Path $dir 'a b') -Content 'x'
        $null = New-TestFile -Path (Join-Path $dir '50%') -Content 'x'
    }

    It 'prints the default format' {
        $r = Invoke-TestGnu stat 'f' -WorkingDirectory $dir
        $r.Output.Count | Should -Be 8
        $r.Output[0] | Should -Be '  File: f'
        $r.Output[1] | Should -Match "^  Size: 6\s+`tBlocks: 8\s+IO Block: 4096\s+regular file$"
        $r.Output[2] | Should -Be "Device: 0h/0d`tInode: 0           Links: 1"
        $r.Output[3] | Should -Match '^Access: \(0\d{3}/-[rwx-]{9}\)  Uid: \(\s*\d+/\s*\S+\)   Gid: \(\s*\d+/\s*\S+\)$'
        $r.Output[4] | Should -Match '^Access: \d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{9} [+-]\d{4}$'
        $r.Output[5] | Should -Match '^Modify: '
        $r.Output[6] | Should -Match '^Change: '
        $r.Output[7] | Should -Match '^ Birth: '
        $r.ExitCode | Should -Be 0
        (Invoke-TestGnu stat 'a b' -WorkingDirectory $dir).Output[0] | Should -Be "  File: 'a b'"
        (Invoke-TestGnu stat '50%' -WorkingDirectory $dir).Output[0] | Should -Be '  File: 50%'
        (Invoke-TestGnu stat 'sub', 'e' -WorkingDirectory $dir).Output | Where-Object { $_ -match '^  Size' } | ForEach-Object { ($_ -split '\s+')[-1] } |
            Should -Be @('directory', 'file')
    }

    It 'prints file types with %F' {
        (Invoke-TestGnu stat '-c', '%F', 'f', 'e', 'sub' -WorkingDirectory $dir).Output | Should -Be @('regular file', 'regular empty file', 'directory')
    }

    It 'prints the format sequences with -c / --format' {
        $item = Get-Item -LiteralPath $file
        $r = Invoke-TestGnu stat '--format=%n|%s|%b|%B|%o|%h|%i|%d|%D|%t|%T|%%|%Q|%N', 'f' -WorkingDirectory $dir
        $r.Output | Should -Be @("f|6|8|512|4096|1|0|0|0|0|0|%|?|'f'")
        $seconds = [System.DateTimeOffset]::new($item.LastWriteTimeUtc).ToUnixTimeSeconds()
        (Invoke-TestGnu stat '-c', '%Y %Z', 'f' -WorkingDirectory $dir).Output | Should -Be @("$seconds $seconds")
        (Invoke-TestGnu stat '-c', '%X', 'f' -WorkingDirectory $dir).Output | Should -Be @([string][System.DateTimeOffset]::new($item.LastAccessTimeUtc).ToUnixTimeSeconds())
        (Invoke-TestGnu stat '-c', '%W', 'f' -WorkingDirectory $dir).Output | Should -Be @([string][System.DateTimeOffset]::new($item.CreationTimeUtc).ToUnixTimeSeconds())
        (Invoke-TestGnu stat '-c', '%x|%y|%z|%w', 'f' -WorkingDirectory $dir).Output | Should -Match '^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{9} [+-]\d{4}\|?){4}$'
        $modes = (Invoke-TestGnu stat '-c', '%a %A %f', 'f', 'sub' -WorkingDirectory $dir).Output
        foreach ($line in $modes) {
            $parts = $line -split ' '
            $typeBits = 0x8000
            if ($parts[1].StartsWith('d')) { $typeBits = 0x4000 }
            $parts[2] | Should -Be ([System.Convert]::ToString($typeBits -bor [System.Convert]::ToInt32($parts[0], 8), 16))
        }
        (Invoke-TestGnu stat '-c', '%u %g %U %G', 'f' -WorkingDirectory $dir).Output | Should -Match '^\d+ \d+ \S+ \S+$'
        (Invoke-TestGnu stat '-c', '%10s|%-6n|%06s|%.3n|%.2F|%', 'f' -WorkingDirectory $dir).Output | Should -Be @('         6|f     |000006|f|re|%')
    }

    It 'interprets escapes and adds no newline with --printf' {
        (Invoke-TestGnu stat '--printf=%n %s\n', 'f', 'e' -WorkingDirectory $dir).Output | Should -Be @('f 6', 'e 0')
        (Invoke-TestGnu stat '--printf=%n,', 'f', 'e' -WorkingDirectory $dir).Output | Should -Be @('f,e,')
    }

    It 'prints the terse form with -t / --terse' {
        $fields = @((Invoke-TestGnu stat '-t', 'f' -WorkingDirectory $dir).Output[0] -split ' ')
        $fields.Count | Should -Be 16
        $fields[0..2] | Should -Be @('f', '6', '8')
        @((Invoke-TestGnu stat '--terse', 'sub' -WorkingDirectory $dir).Output[0] -split ' ').Count | Should -Be 16
    }

    It 'prints file system status with -f / --file-system' {
        $r = Invoke-TestGnu stat '-f', '.' -WorkingDirectory $dir
        $r.Output.Count | Should -Be 5
        $r.Output[0] | Should -Be '  File: "."'
        $r.Output[1] | Should -Match '^    ID: \S+\s+Namelen: 255\s+Type: \S+'
        $r.Output[2] | Should -Be 'Block size: 4096       Fundamental block size: 4096'
        $r.Output[3] | Should -Match '^Blocks: Total: \d+\s+Free: \d+\s+Available: \d+$'
        $r.Output[4] | Should -Be 'Inodes: Total: ?          Free: ?'
        @((Invoke-TestGnu stat '--file-system', '--terse', '.' -WorkingDirectory $dir).Output[0] -split ' ').Count | Should -Be 11
        (Invoke-TestGnu stat '-f', '-c', '%n|%s|%S|%l|%c|%d', '.' -WorkingDirectory $dir).Output | Should -Be @('.|4096|4096|255|?|?')
        (Invoke-TestGnu stat '-f', 'nosuch' -WorkingDirectory $dir).ErrorText | Should -Be "stat: cannot read file system information for 'nosuch': No such file or directory"
    }

    It 'names known and unknown file systems' {
        Mock -ModuleName PSGnuUtils Get-GnuStatDrive {
            [pscustomobject]@{ IsReady = $false; RootDirectory = [pscustomobject]@{ FullName = 'Z:\' } }
            [pscustomobject]@{ IsReady = $true; RootDirectory = [pscustomobject]@{ FullName = [System.IO.Path]::GetPathRoot($TestDrive) }; DriveFormat = 'WeirdFS'; TotalSize = 8192; TotalFreeSpace = 4096; AvailableFreeSpace = 4096 }
        }
        (Invoke-TestGnu stat '-f', '-c', '%t %T %b %f %a', '.' -WorkingDirectory $dir).Output | Should -Be @('0 weirdfs 2 1 1')
    }

    It 'falls back to the drive of the path root' {
        Mock -ModuleName PSGnuUtils Get-GnuStatDrive { }
        (Invoke-TestGnu stat '-f', '-c', '%s', '.' -WorkingDirectory $dir).Output | Should -Be @('4096')
    }

    It 'shows links and follows them with -L / --dereference' {
        $link = Join-Path $dir 'link'
        if (-not (New-TestDirectoryLink -Path $link -Target (Join-Path $dir 'sub'))) { Set-ItResult -Skipped -Because 'links cannot be created here'; return }
        $r = Invoke-TestGnu stat 'link' -WorkingDirectory $dir
        $r.Output[0] | Should -BeLike "  File: 'link' -> '*sub'"
        $r.Output[1] | Should -Match 'symbolic link$'
        (Invoke-TestGnu stat '-c', '%F', 'link' -WorkingDirectory $dir).Output | Should -Be @('symbolic link')
        (Invoke-TestGnu stat '-L', '-c', '%F', 'link' -WorkingDirectory $dir).Output | Should -Be @('directory')
        (Invoke-TestGnu stat '--dereference', '-c', '%F', 'f' -WorkingDirectory $dir).Output | Should -Be @('regular file')
        $dangling = Join-Path $dir 'gone'
        $null = New-Item -ItemType Directory -Path $dangling
        $null = New-TestDirectoryLink -Path (Join-Path $dir 'dangling') -Target $dangling
        Remove-Item -LiteralPath $dangling
        (Invoke-TestGnu stat '-L', 'dangling' -WorkingDirectory $dir).ErrorText | Should -Be "stat: cannot stat 'dangling': No such file or directory"
    }

    It 'maps Unix file types and modes' {
        Mock -ModuleName PSGnuUtils Get-GnuUnixModeString { 'crw-rw-rw-' }
        Mock -ModuleName PSGnuUtils Get-GnuUnixFileMode { 438 }
        (Invoke-TestGnu stat '-c', '%F %a %A %f', 'f' -WorkingDirectory $dir).Output | Should -Be @('character special file 666 crw-rw-rw- 21b6')
    }

    It 'maps other Unix file types' -ForEach @(
        @{ Mode = 'brw-rw----'; Type = 'block special file' }
        @{ Mode = 'prw-r--r--'; Type = 'fifo' }
        @{ Mode = 'srwxr-xr-x'; Type = 'socket' }
    ) {
        Mock -ModuleName PSGnuUtils Get-GnuUnixModeString { $Mode }
        (Invoke-TestGnu stat '-c', '%F', 'f' -WorkingDirectory $dir).Output | Should -Be @($Type)
    }

    It 'maps owners to numeric ids' {
        InModuleScope PSGnuUtils {
            Get-GnuStatId -Name '-' | Should -Be '0'
            Get-GnuStatId -Name '' | Should -Be '0'
        }
        if (Test-IsWindowsPlatform) {
            InModuleScope PSGnuUtils {
                Get-GnuStatId -Name 'SYSTEM' | Should -Be '18'
                Get-GnuStatId -Name 'no-such-account-xyz' | Should -Be '0'
                $rid = [long](([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value -split '-')[-1])
                Get-GnuStatId -Name ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) | Should -Be ([string](0x30000 + $rid))
            }
        }
        InModuleScope PSGnuUtils {
            Mock Test-GnuWindows { $false }
            Mock Get-GnuIdentity { if ($User -eq 'ghost') { return $null }; @{ UserId = '1000'; GroupId = '100' } }
            Get-GnuStatId -Name 'alice' | Should -Be '1000'
            Get-GnuStatId -Name 'alice' -Group | Should -Be '100'
            Get-GnuStatId -Name 'ghost' | Should -Be '0'
        }
    }

    It 'reports errors' {
        $r = Invoke-TestGnu stat 'nosuch', 'f' -WorkingDirectory $dir
        $r.ErrorText | Should -Be "stat: cannot stat 'nosuch': No such file or directory"
        $r.Output[0] | Should -Be '  File: f'
        $r.ExitCode | Should -Be 1
        $r = Invoke-TestGnu stat
        $r.ErrorText | Should -Match 'missing operand'
        $r.ExitCode | Should -Be 1
    }
}
