BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')

    function Invoke-TestDd {
        # dd with its statistics (information stream) captured separately.
        param([string[]]$Arguments, [string]$Directory, [object[]]$InputObject)
        Push-Location -LiteralPath $Directory
        try {
            $global:LASTEXITCODE = -1
            if ($PSBoundParameters.ContainsKey('InputObject')) { $records = @($InputObject | Invoke-GnuDd @Arguments 6>&1 2>&1 3>&1) }
            else { $records = @(Invoke-GnuDd @Arguments 6>&1 2>&1 3>&1) }
            $exitCode = $global:LASTEXITCODE
        }
        finally { Pop-Location }
        [pscustomobject]@{
            Output   = @($records | Where-Object { $_ -is [string] })
            Info     = @($records | Where-Object { $_ -is [System.Management.Automation.InformationRecord] } | ForEach-Object { [string]$_.MessageData })
            Errors   = @($records | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { $_.Exception.Message })
            Warnings = @($records | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $_.Message })
            ExitCode = $exitCode
        }
    }

    function Get-TestBytes {
        param([string]$Path)
        [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($Path))
    }
}

# Expected results were compared with GNU coreutils dd 8.32.
Describe 'dd' {
    BeforeEach {
        $script:dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $null = New-Item -ItemType Directory -Path $dir
        $null = New-TestFile -Path (Join-Path $dir 'in') -Content ((1..1000 | ForEach-Object { "$_`n" }) -join '')
        $null = New-TestFile -Path (Join-Path $dir 'txt') -Content "Hello World abc`n"
        $null = New-TestFile -Path (Join-Path $dir 'o') -Content 'XXXXXXXXXXXXXXXXXXXX'
    }

    It 'copies blocks with bs, count and skip' {
        $r = Invoke-TestDd -Arguments 'if=in', 'of=o', 'bs=100', 'count=3' -Directory $dir
        (Get-Item -LiteralPath (Join-Path $dir 'o')).Length | Should -Be 300
        $r.Info[0..1] | Should -Be @('3+0 records in', '3+0 records out')
        $r.Info[2] | Should -Match '^300 bytes copied, [\d.e-]+ s, [\d.]+ [kMG]?B/s$'
        $null = Invoke-TestDd -Arguments 'if=in', 'of=o', 'bs=100', 'skip=2', 'count=2', 'status=none' -Directory $dir
        (Get-TestBytes (Join-Path $dir 'o')).Substring(0, 4) | Should -Be "`n71`n"
    }

    It 'counts partial records with different ibs and obs' {
        $r = Invoke-TestDd -Arguments 'if=in', 'of=o', 'ibs=7', 'obs=5', 'count=4', 'status=noxfer' -Directory $dir
        $r.Info | Should -Be @('4+0 records in', '5+1 records out')
        (Get-Item -LiteralPath (Join-Path $dir 'o')).Length | Should -Be 28
        $r = Invoke-TestDd -Arguments 'if=in', 'of=o', 'bs=1K' -Directory $dir
        $r.Info[0..1] | Should -Be @('3+1 records in', '3+1 records out')
        $r.Info[2] | Should -Match '^3893 bytes \(3\.9 kB, 3\.9 KiB\) copied'
    }

    It 'converts with conv=ucase, lcase, swab and sync' {
        $null = Invoke-TestDd -Arguments 'if=txt', 'of=o', 'conv=ucase', 'status=none' -Directory $dir
        Get-TestBytes (Join-Path $dir 'o') | Should -Be "HELLO WORLD ABC`n"
        $null = Invoke-TestDd -Arguments 'if=txt', 'of=o', 'conv=lcase,swab', 'status=none' -Directory $dir
        Get-TestBytes (Join-Path $dir 'o') | Should -Be "ehll oowlr dba`nc"
        $null = Invoke-TestDd -Arguments 'if=txt', 'of=o', 'bs=10', 'conv=sync', 'status=none' -Directory $dir
        Get-TestBytes (Join-Path $dir 'o') | Should -Be ("Hello World abc`n" + ([string][char]0) * 4)
        (Invoke-TestDd -Arguments 'if=txt', 'of=o', 'conv=lcase,ucase' -Directory $dir).Errors | Should -Be @('dd: cannot combine lcase and ucase')
    }

    It 'swaps pairs across odd blocks with conv=swab' {
        $null = Invoke-TestDd -Arguments 'if=txt', 'of=o', 'bs=3', 'conv=swab', 'status=none' -Directory $dir
        Get-TestBytes (Join-Path $dir 'o') | Should -Be "eHll ooWlr dba`nc"
    }

    It 'reads a size without digits as one of that unit' {
        $null = Invoke-TestDd -Arguments 'if=txt', 'of=o', 'bs=w', 'count=1', 'status=none' -Directory $dir
        Get-TestBytes (Join-Path $dir 'o') | Should -Be 'He'
    }

    It 'reports directories as input and output' {
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'folder') -Force
        $r = Invoke-TestDd -Arguments 'if=folder', 'of=o' -Directory $dir
        $r.Errors | Should -Be @("dd: error reading 'folder': Is a directory")
        $r.Info[0..1] | Should -Be @('0+0 records in', '0+0 records out')
        $r.ExitCode | Should -Be 1
        (Invoke-TestDd -Arguments 'if=txt', 'of=folder' -Directory $dir).Errors | Should -Be @("dd: failed to open 'folder': Is a directory")
    }

    It 'seeks in the output with seek and keeps the rest with conv=notrunc' {
        $null = Invoke-TestDd -Arguments 'if=txt', 'of=o', 'seek=1', 'bs=4', 'status=none' -Directory $dir
        Get-TestBytes (Join-Path $dir 'o') | Should -Be "XXXXHello World abc`n"
        $null = New-TestFile -Path (Join-Path $dir 'o') -Content 'XXXXXXXXXXXXXXXXXXXXXXXX'
        $null = Invoke-TestDd -Arguments 'if=txt', 'of=o', 'oflag=seek_bytes', 'seek=3', 'conv=notrunc', 'status=none' -Directory $dir
        Get-TestBytes (Join-Path $dir 'o') | Should -Be "XXXHello World abc`nXXXXX"
        $null = Invoke-TestDd -Arguments 'if=txt', 'of=o', 'oflag=append', 'conv=notrunc', 'status=none' -Directory $dir
        (Get-Item -LiteralPath (Join-Path $dir 'o')).Length | Should -Be 40
        $null = Invoke-TestDd -Arguments 'if=txt', 'of=o', 'oseek=1', 'bs=2', 'status=none' -Directory $dir
        (Get-TestBytes (Join-Path $dir 'o')).Substring(0, 3) | Should -Be 'XXH'
    }

    It 'counts and skips bytes with iflag=skip_bytes,count_bytes' {
        $null = Invoke-TestDd -Arguments 'if=txt', 'of=o', 'iflag=skip_bytes,count_bytes', 'skip=6', 'count=5', 'status=none' -Directory $dir
        Get-TestBytes (Join-Path $dir 'o') | Should -Be 'World'
        $null = Invoke-TestDd -Arguments 'if=txt', 'of=o', 'iseek=1', 'bs=6', 'iflag=fullblock', 'count=1', 'status=none' -Directory $dir
        Get-TestBytes (Join-Path $dir 'o') | Should -Be 'World '
        $null = Invoke-TestDd -Arguments 'if=txt', 'of=o', 'bs=2x2', 'count=1', 'status=none' -Directory $dir
        Get-TestBytes (Join-Path $dir 'o') | Should -Be 'Hell'
        $null = Invoke-TestDd -Arguments 'if=txt', 'of=o', 'bs=1w', 'count=1', 'status=none' -Directory $dir
        Get-TestBytes (Join-Path $dir 'o') | Should -Be 'He'
        $null = Invoke-TestDd -Arguments 'if=txt', 'of=o', 'bs=3c', 'count=1', 'status=none' -Directory $dir
        Get-TestBytes (Join-Path $dir 'o') | Should -Be 'Hel'
    }

    It 'handles empty copies and skipping past the end' {
        $r = Invoke-TestDd -Arguments 'if=txt', 'of=o', 'count=0' -Directory $dir
        $r.Info[0..1] | Should -Be @('0+0 records in', '0+0 records out')
        $r.Info[2] | Should -Match '^0 bytes copied'
        $r = Invoke-TestDd -Arguments 'if=txt', 'of=o', 'skip=100', 'status=noxfer' -Directory $dir
        $r.Warnings | Should -Be @('dd: txt: cannot skip to specified offset')
        $r = Invoke-TestDd -Arguments 'of=o', 'bs=1', 'count=1' -Directory $dir -InputObject 'a'
        $r.Info[2] | Should -Match '^1 byte copied'
    }

    It 'reads the pipeline and writes the pipeline' {
        (Invoke-TestDd -Arguments 'status=none' -Directory $dir -InputObject 'one', 'two').Output | Should -Be @('one', 'two')
        (Invoke-TestDd -Arguments 'if=txt', 'conv=ucase', 'status=none' -Directory $dir).Output | Should -Be @('HELLO WORLD ABC')
        (Invoke-TestDd -Arguments 'if=txt', 'count=0', 'status=none' -Directory $dir).Output | Should -BeNullOrEmpty
    }

    It 'honours conv=excl, nocreat, fsync and fdatasync' {
        (Invoke-TestDd -Arguments 'if=txt', 'of=o', 'conv=excl' -Directory $dir).Errors | Should -Be @("dd: failed to open 'o': File exists")
        (Invoke-TestDd -Arguments 'if=txt', 'of=new', 'conv=nocreat' -Directory $dir).Errors | Should -Be @("dd: failed to open 'new': No such file or directory")
        (Invoke-TestDd -Arguments 'if=txt', 'of=new', 'conv=excl,fsync', 'status=none' -Directory $dir).ExitCode | Should -Be 0
        (Invoke-TestDd -Arguments 'if=txt', 'of=new', 'conv=fdatasync,noerror', 'status=none' -Directory $dir).ExitCode | Should -Be 0
        (Invoke-TestDd -Arguments 'if=txt', 'of=o', 'conv=excl,nocreat' -Directory $dir).Errors | Should -Be @('dd: cannot combine excl and nocreat')
        (Invoke-TestDd -Arguments 'if=txt', 'of=no/such/dir' -Directory $dir).Errors | Should -Match "failed to open 'no/such/dir'"
    }

    It 'rejects bad operands' {
        $r = Invoke-TestDd -Arguments 'bad=1' -Directory $dir
        $r.Errors[0] | Should -Match "^dd: unrecognized operand 'bad=1'"
        $r.ExitCode | Should -Be 1
        (Invoke-TestDd -Arguments 'oops' -Directory $dir).Errors[0] | Should -Match "unrecognized operand 'oops'"
        (Invoke-TestDd -Arguments 'bs=x' -Directory $dir).Errors | Should -Be @("dd: invalid number: 'x'")
        (Invoke-TestDd -Arguments 'bs=0' -Directory $dir).Errors | Should -Be @("dd: invalid number: '0'")
        (Invoke-TestDd -Arguments 'conv=xyz' -Directory $dir).Errors[0] | Should -Match "invalid conversion: 'xyz'"
        (Invoke-TestDd -Arguments 'iflag=xyz' -Directory $dir).Errors[0] | Should -Match "invalid input flag: 'xyz'"
        (Invoke-TestDd -Arguments 'oflag=xyz' -Directory $dir).Errors[0] | Should -Match "invalid output flag: 'xyz'"
        (Invoke-TestDd -Arguments 'status=loud' -Directory $dir).Errors[0] | Should -Match "^dd: invalid status level: 'loud'"
        (Invoke-TestDd -Arguments 'count=99999999999999999999' -Directory $dir).Errors | Should -Be @("dd: invalid number: '99999999999999999999': Value too large for defined data type")
        (Invoke-TestDd -Arguments 'count=79228162514264337593543950335x2' -Directory $dir).Errors | Should -Match 'Value too large'
        (Invoke-TestDd -Arguments 'if=nosuch', 'of=o' -Directory $dir).Errors | Should -Be @("dd: failed to open 'nosuch': No such file or directory")
        (Invoke-TestDd -Arguments 'if=nosuch' -Directory $dir).ExitCode | Should -Be 1
        (Invoke-TestDd -Arguments 'if=txt', 'of=' -Directory $dir).Errors | Should -Be @("dd: failed to open '': No such file or directory")
    }

    It 'formats transfer rates with three significant digits' {
        InModuleScope PSGnuUtils {
            $stats = @{ FullIn = 1; PartialIn = 0; FullOut = 1; PartialOut = 0; Bytes = [long]5000 }
            $lines = @(Write-GnuDdStatus -Stats $stats -Level 'progress' -Seconds 0.001 6>&1 | ForEach-Object { [string]$_.MessageData })
            $lines[2] | Should -Be '5000 bytes (5.0 kB, 4.9 KiB) copied, 0.001 s, 5.00 MB/s'
            $stats.Bytes = 27000
            @(Write-GnuDdStatus -Stats $stats -Level 'progress' -Seconds 0.001 6>&1 | ForEach-Object { [string]$_.MessageData })[2] | Should -Match ', 27\.0 MB/s$'
            @(Write-GnuDdStatus -Stats $stats -Level 'progress' -Seconds 0.0001 6>&1 | ForEach-Object { [string]$_.MessageData })[2] | Should -Match ', 270 MB/s$'
            @(Write-GnuDdStatus -Stats $stats -Level 'progress' -Seconds 0 6>&1 | ForEach-Object { [string]$_.MessageData })[2] | Should -Match ', Infinity B/s$'
        }
    }
}
