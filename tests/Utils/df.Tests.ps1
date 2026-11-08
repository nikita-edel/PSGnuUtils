BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# The column layout and header rules follow GNU coreutils df 8.32.
Describe 'df' {
    BeforeAll {
        $script:root = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($TestDrive))
    }

    BeforeEach {
        Mock -ModuleName PSGnuUtils Get-GnuDfFileSystem {
            @{ Source = 'C:'; Type = 'ntfs'; Total = [double]1073741824; Free = [double]536870912; Available = [double]268435456; Target = $root; Local = $true; Ready = $true }
            @{ Source = '//srv/share'; Type = 'smbfs'; Total = [double]2147483648; Free = [double]1073741824; Available = [double]1073741824; Target = 'Z:\'; Local = $false; Ready = $true }
            @{ Source = 'proc'; Type = 'proc'; Total = [double]0; Free = [double]0; Available = [double]0; Target = 'P:\'; Local = $true; Ready = $true }
            @{ Source = 'X:'; Type = '-'; Total = [double]0; Free = [double]0; Available = [double]0; Target = 'X:\'; Local = $true; Ready = $false }
        }
    }

    It 'lists the real file systems in 1K blocks' {
        $r = Invoke-TestGnu df
        $r.Output | Should -Be @(
            'Filesystem     1K-blocks    Used Available Use% Mounted on',
            "C:               1048576  524288    262144  67% $root",
            '//srv/share      2097152 1048576   1048576  50% Z:\')
        $r.ExitCode | Should -Be 0
    }

    It 'prints human readable sizes with -h / --human-readable and -H / --si' {
        (Invoke-TestGnu df '-h').Output | Should -Be @(
            'Filesystem      Size  Used Avail Use% Mounted on',
            "C:              1.0G  512M  256M  67% $root",
            '//srv/share     2.0G  1.0G  1.0G  50% Z:\')
        (Invoke-TestGnu df '--human-readable').Output[1] | Should -Match '^C:\s+1\.0G'
        (Invoke-TestGnu df '-H').Output[1] | Should -Match '^C:\s+1\.1G\s+537M\s+269M'
        (Invoke-TestGnu df '--si').Output[1] | Should -Match '^C:\s+1\.1G'
    }

    It 'scales with -B / --block-size, -k and -m' {
        (Invoke-TestGnu df '-B', '1M').Output[0] | Should -Be 'Filesystem     1M-blocks  Used Available Use% Mounted on'
        (Invoke-TestGnu df '--block-size=M').Output[1] | Should -Match '^C:\s+1024M\s+512M\s+256M' -Because 'a size without digits prints its unit'
        (Invoke-TestGnu df '-m').Output[1] | Should -Match '^C:\s+1024\s+512\s+256'
        (Invoke-TestGnu df '-k').Output[1] | Should -Match '^C:\s+1048576'
        (Invoke-TestGnu df '-B', 'x').ErrorText | Should -Match "invalid -B argument 'x'"
        (Invoke-TestGnu df '--block-size=x').ErrorText | Should -Match "invalid --block-size argument 'x'"
    }

    It 'labels the size column like GNU' -ForEach @(
        @{ Size = '1024'; Label = '1K' }, @{ Size = '1000'; Label = '1kB' }, @{ Size = '512'; Label = '512B' }, @{ Size = '1'; Label = '1B' },
        @{ Size = '1K'; Label = '1K' }, @{ Size = 'KB'; Label = '1kB' }, @{ Size = '1MB'; Label = '1MB' }, @{ Size = 'KiB'; Label = '1KiB' },
        @{ Size = 'MiB'; Label = '1MiB' }, @{ Size = '2K'; Label = '2K' }, @{ Size = '1048576'; Label = '1M' }, @{ Size = '1500'; Label = '1.5kB' }
    ) {
        (Invoke-TestGnu df "-B$Size").Output[0] | Should -Match "^Filesystem\s+$([regex]::Escape($Label))-blocks "
    }

    It 'uses the last size option' {
        (Invoke-TestGnu df '-h', '-BM').Output[0] | Should -Match '1M-blocks'
        (Invoke-TestGnu df '-BM', '-k').Output[0] | Should -Match '1K-blocks'
        (Invoke-TestGnu df '-k', '-h').Output[0] | Should -Match 'Size'
    }

    It 'prints the size in bytes for -P headers and keeps human headers with -P -h' {
        (Invoke-TestGnu df '-P', '-BM').Output[0] | Should -Match '^Filesystem\s+1048576-blocks'
        (Invoke-TestGnu df '-P', '-h').Output[0] | Should -Match '^Filesystem\s+Size\s+Used\s+Avail\s+Use%'
    }

    It 'adds the type with -T / --print-type and inodes with -i / --inodes' {
        (Invoke-TestGnu df '-T').Output[0] | Should -Be 'Filesystem     Type  1K-blocks    Used Available Use% Mounted on'
        (Invoke-TestGnu df '--print-type').Output[1] | Should -Match '^C:\s+ntfs\s+1048576'
        (Invoke-TestGnu df '-i').Output | Should -Be @(
            'Filesystem     Inodes IUsed IFree IUse% Mounted on',
            "C:                  -     -     -     - $root",
            '//srv/share         -     -     -     - Z:\')
        (Invoke-TestGnu df '--inodes').ExitCode | Should -Be 0
    }

    It 'uses the POSIX format with -P / --portability' {
        (Invoke-TestGnu df '-P').Output[0] | Should -Be 'Filesystem     1024-blocks    Used Available Capacity Mounted on'
        (Invoke-TestGnu df '--portability').Output[1] | Should -Match '^C:\s+1048576\s+524288\s+262144\s+67%'
    }

    It 'selects columns with --output' {
        (Invoke-TestGnu df '--output=source,fstype,size,avail,pcent,target').Output | Should -Be @(
            'Filesystem     Type  1K-blocks   Avail Use% Mounted on',
            "C:             ntfs    1048576  262144  67% $root",
            '//srv/share    smbfs   2097152 1048576  50% Z:\')
        (Invoke-TestGnu df '--output').Output[0] | Should -Be 'Filesystem     Type  Inodes IUsed IFree IUse% 1K-blocks    Used   Avail Use% File Mounted on'
        (Invoke-TestGnu df '--output=file,source', $TestDrive).Output | Should -Be @("File$(' ' * ($TestDrive.Length - 3))Filesystem", "$TestDrive C:")
        (Invoke-TestGnu df '--output=xyz').ErrorText | Should -Match "option --output: field 'xyz' unknown"
    }

    It 'rejects -P, -i and -T together with --output' -ForEach @(@{ Option = '-P' }, @{ Option = '-i' }, @{ Option = '-T' }) {
        $r = Invoke-TestGnu df $Option, '--output=size'
        $r.ErrorText | Should -Match "^df: options $Option and --output are mutually exclusive"
        $r.ExitCode | Should -Be 1
    }

    It 'rejects a type that is both selected and excluded' {
        $r = Invoke-TestGnu df '-t', 'ntfs', '-x', 'ntfs'
        $r.ErrorText | Should -Be "df: file system type 'ntfs' both selected and excluded"
        $r.ExitCode | Should -Be 1
    }

    It 'filters with -t / --type, -x / --exclude-type, -l / --local and -a / --all' {
        (Invoke-TestGnu df '-t', 'ntfs').Output.Count | Should -Be 2
        (Invoke-TestGnu df '--type=smbfs', '--type=ntfs').Output.Count | Should -Be 3
        (Invoke-TestGnu df '-x', 'ntfs').Output[1] | Should -Match '^//srv/share'
        (Invoke-TestGnu df '--exclude-type=smbfs').Output.Count | Should -Be 2
        (Invoke-TestGnu df '-l').Output.Count | Should -Be 2
        (Invoke-TestGnu df '--local').Output[1] | Should -Match '^C:'
        $all = (Invoke-TestGnu df '-a').Output
        $all.Count | Should -Be 5
        $all[3] | Should -Match '^proc\s+0\s+0\s+0\s+-\s+P:'
        (Invoke-TestGnu df '--all').Output.Count | Should -Be 5
        $r = Invoke-TestGnu df '-t', 'xfs'
        $r.ErrorText | Should -Be 'df: no file systems processed'
        $r.ExitCode | Should -Be 1
    }

    It 'adds a total with --total' {
        $r = Invoke-TestGnu df '--total'
        $r.Output[-1] | Should -Be 'total            3145728 1572864   1310720  55% -'
        (Invoke-TestGnu df '--total', '-T').Output[-1] | Should -Match '^total\s+-\s+3145728'
    }

    It 'reports the file system of each FILE' {
        $r = Invoke-TestGnu df $TestDrive, 'nosuch'
        $r.Output[1] | Should -Match '^C:\s+1048576'
        $r.ErrorText | Should -Be 'df: nosuch: No such file or directory'
        $r.ExitCode | Should -Be 1
        $r = Invoke-TestGnu df 'nosuch'
        $r.Output | Should -BeNullOrEmpty
        $r.ErrorText | Should -Be 'df: nosuch: No such file or directory'
    }

    It 'accepts --sync and --no-sync' {
        (Invoke-TestGnu df '--sync').ExitCode | Should -Be 0
        (Invoke-TestGnu df '--no-sync').ExitCode | Should -Be 0
    }
}

Describe 'df file systems' {
    It 'reads the real drives' {
        $systems = @(InModuleScope PSGnuUtils { Get-GnuDfFileSystem })
        $systems.Count | Should -BeGreaterThan 0
        @($systems | Where-Object { $_.Ready -and $_.Total -gt 0 }).Count | Should -BeGreaterThan 0
        (Invoke-TestGnu df $TestDrive).Output.Count | Should -Be 2
    }

    It 'takes Linux sources from /proc/mounts' {
        $drive = @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady })[0]
        $mounts = New-TestFile -Path (Join-Path $TestDrive 'mounts') -Content "/dev/sda1 $($drive.Name) ext4 rw 0 0`nshort`n"
        InModuleScope PSGnuUtils -Parameters @{ Mounts = $mounts; Name = $drive.Name } {
            param($Mounts, $Name)
            Mock Test-GnuWindows { $false }
            $systems = @(Get-GnuDfFileSystem -MountsPath $Mounts)
            @($systems | Where-Object { $_.Target -eq $Name })[0].Source | Should -Be '/dev/sda1'
        }
    }
}
