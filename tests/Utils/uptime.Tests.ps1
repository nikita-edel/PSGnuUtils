BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'uptime' {
    It 'prints the coreutils line' {
        Mock -ModuleName PSGnuUtils Get-GnuUptime { New-TimeSpan -Days 3 -Hours 2 -Minutes 4 }
        Mock -ModuleName PSGnuUtils Get-GnuUserCount { 2 }
        Mock -ModuleName PSGnuUtils Get-GnuLoadAverage { , [double[]]@(0, 0.5, 1.25) }
        (Invoke-TestGnu uptime).Output | Should -Match '^ \d\d:\d\d:\d\d  up 3 days  2:04,  2 users,  load average: 0\.00, 0\.50, 1\.25$'
    }

    It 'formats days, users and missing load averages' {
        InModuleScope PSGnuUtils {
            $now = [datetime]::new(2024, 1, 1, 9, 5, 7)
            Format-GnuUptimeLine -Now $now -Uptime (New-TimeSpan -Hours 5 -Minutes 3) -Users 1 -Load $null | Should -Be ' 09:05:07  up   5:03,  1 user'
            Format-GnuUptimeLine -Now $now -Uptime (New-TimeSpan -Days 1 -Hours 12) -Users 0 -Load $null | Should -Be ' 09:05:07  up 1 day 12:00,  0 users'
        }
    }

    It 'prints the pretty format with -p / --pretty' {
        Mock -ModuleName PSGnuUtils Get-GnuUptime { New-TimeSpan -Days 9 -Hours 1 -Minutes 2 }
        (Invoke-TestGnu uptime '-p').Output | Should -Be @('up 1 week, 2 days, 1 hour, 2 minutes')
        (Invoke-TestGnu uptime '--pretty').Output | Should -Be @('up 1 week, 2 days, 1 hour, 2 minutes')
        InModuleScope PSGnuUtils {
            Format-GnuUptimePretty -Uptime (New-TimeSpan -Days 15 -Minutes 1) | Should -Be 'up 2 weeks, 1 day, 1 minute'
            Format-GnuUptimePretty -Uptime (New-TimeSpan -Seconds 20) | Should -Be 'up 0 minutes'
        }
    }

    It 'prints the boot time with -s / --since' {
        Mock -ModuleName PSGnuUtils Get-GnuUptime { New-TimeSpan -Hours 1 }
        $expected = (Get-Date).AddHours(-1)
        $text = (Invoke-TestGnu uptime '--since').Output[0]
        $text | Should -Match '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$'
        ([datetime]::ParseExact($text, 'yyyy-MM-dd HH:mm:ss', $null) - $expected).Duration().TotalSeconds | Should -BeLessThan 5
        (Invoke-TestGnu uptime '-s').Output[0] | Should -Match '^\d{4}-'
    }

    It 'reads the real uptime, users and load averages' {
        InModuleScope PSGnuUtils {
            (Get-GnuUptime).TotalSeconds | Should -BeGreaterThan 0
            (Get-GnuUptime -Property 'NoSuchProperty').TotalSeconds | Should -BeGreaterThan 0
            Get-GnuUserCount | Should -BeGreaterOrEqual 0
            if (Test-GnuWindows) { Get-GnuLoadAverage | Should -BeNullOrEmpty }
        }
    }

    It 'reads /proc/loadavg off Windows' {
        $file = New-TestFile -Path (Join-Path $TestDrive 'loadavg') -Content "0.10 0.20 0.30 1/100 1234`n"
        InModuleScope PSGnuUtils -Parameters @{ Path = $file } {
            param($Path)
            Mock Test-GnuWindows { $false }
            $load = Get-GnuLoadAverage -Path $Path
            $load | Should -Be @(0.1, 0.2, 0.3)
            Get-GnuUserCount | Should -BeGreaterOrEqual 0
            { Get-GnuLoadAverage -Path (Join-Path $TestDrive 'none') } | Should -Not -Throw
        }
    }

    It 'rejects operands' {
        (Invoke-TestGnu uptime 'x').ErrorText | Should -Match "extra operand 'x'"
    }
}
