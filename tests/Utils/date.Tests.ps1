BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# Expected outputs come from GNU coreutils date (-u, fixed instants).
Describe 'date' {
    BeforeAll {
        $script:all = '+%a|%A|%b|%B|%c|%C|%d|%D|%e|%F|%g|%G|%h|%H|%I|%j|%k|%l|%m|%M|%N|%p|%P|%q|%r|%R|%s|%S|%T|%u|%U|%V|%w|%W|%x|%X|%y|%Y|%z|%:z|%::z|%:::z|%Z|%%|%-d|%_m|%05d|%^a|%#b|%#Z|%#p|%10A|%-10A|%3N|%_5Y|%Q|%'
    }

    It 'formats <Date> with every sequence' -ForEach @(
        @{ Date = '@0'; Expected = 'Thu|Thursday|Jan|January|Thu Jan  1 00:00:00 1970|19|01|01/01/70| 1|1970-01-01|70|1970|Jan|00|12|001| 0|12|01|00|000000000|AM|am|1|12:00:00 AM|00:00|0|00|00:00:00|4|00|01|4|00|01/01/70|00:00:00|70|1970|+0000|+00:00|+00:00:00|+00|UTC|%|1| 1|00001|THU|JAN|utc|am|  Thursday|Thursday|000| 1970|%Q|%' }
        @{ Date = '@1700000000.1234567'; Expected = 'Tue|Tuesday|Nov|November|Tue Nov 14 22:13:20 2023|20|14|11/14/23|14|2023-11-14|23|2023|Nov|22|10|318|22|10|11|13|123456700|PM|pm|4|10:13:20 PM|22:13|1700000000|20|22:13:20|2|46|46|2|46|11/14/23|22:13:20|23|2023|+0000|+00:00|+00:00:00|+00|UTC|%|14|11|00014|TUE|NOV|utc|pm|   Tuesday|Tuesday|123| 2023|%Q|%' }
        @{ Date = '2024-02-29 13:05:09'; Expected = 'Thu|Thursday|Feb|February|Thu Feb 29 13:05:09 2024|20|29|02/29/24|29|2024-02-29|24|2024|Feb|13|01|060|13| 1|02|05|000000000|PM|pm|1|01:05:09 PM|13:05|1709211909|09|13:05:09|4|08|09|4|09|02/29/24|13:05:09|24|2024|+0000|+00:00|+00:00:00|+00|UTC|%|29| 2|00029|THU|FEB|utc|pm|  Thursday|Thursday|000| 2024|%Q|%' }
        @{ Date = '2021-01-03 00:00:00'; Expected = 'Sun|Sunday|Jan|January|Sun Jan  3 00:00:00 2021|20|03|01/03/21| 3|2021-01-03|20|2020|Jan|00|12|003| 0|12|01|00|000000000|AM|am|1|12:00:00 AM|00:00|1609632000|00|00:00:00|7|01|53|0|00|01/03/21|00:00:00|21|2021|+0000|+00:00|+00:00:00|+00|UTC|%|3| 1|00003|SUN|JAN|utc|am|    Sunday|Sunday|000| 2021|%Q|%' }
        @{ Date = '2020-12-31 23:59:59'; Expected = 'Thu|Thursday|Dec|December|Thu Dec 31 23:59:59 2020|20|31|12/31/20|31|2020-12-31|20|2020|Dec|23|11|366|23|11|12|59|000000000|PM|pm|4|11:59:59 PM|23:59|1609459199|59|23:59:59|4|52|53|4|52|12/31/20|23:59:59|20|2020|+0000|+00:00|+00:00:00|+00|UTC|%|31|12|00031|THU|DEC|utc|pm|  Thursday|Thursday|000| 2020|%Q|%' }
    ) {
        (Invoke-TestGnu date '-u', '-d', $Date, $all).Output | Should -Be @($Expected)
    }

    It 'prints newlines, tabs and zero padded text' {
        (Invoke-TestGnu date '-u', '-d', '@0', '+%n|%t|%08a|').Output | Should -Be @('', "|`t|00000Thu|")
    }

    It 'prints ISO 8601 with -I / --iso-8601' {
        (Invoke-TestGnu date '-u', '-d', '@1700000000', '-I').Output | Should -Be @('2023-11-14')
        (Invoke-TestGnu date '-u', '-d', '@1700000000', '-Ihours').Output | Should -Be @('2023-11-14T22+00:00')
        (Invoke-TestGnu date '-u', '-d', '@1700000000', '--iso-8601=minutes').Output | Should -Be @('2023-11-14T22:13+00:00')
        (Invoke-TestGnu date '-u', '-d', '@1700000000', '-Is').Output | Should -Be @('2023-11-14T22:13:20+00:00')
        (Invoke-TestGnu date '-u', '-d', '@1700000000.5', '-Ins').Output | Should -Be @('2023-11-14T22:13:20,500000000+00:00')
        $r = Invoke-TestGnu date '-Ixyz'
        $r.ErrorText | Should -Match "invalid argument 'xyz' for '--iso-8601'"
        $r.ExitCode | Should -Be 1
    }

    It 'prints RFC 5322 with -R / --rfc-email and RFC 3339 with --rfc-3339' {
        (Invoke-TestGnu date '-u', '-d', '@1700000000', '-R').Output | Should -Be @('Tue, 14 Nov 2023 22:13:20 +0000')
        (Invoke-TestGnu date '-u', '-d', '@1700000000', '--rfc-email').Output | Should -Be @('Tue, 14 Nov 2023 22:13:20 +0000')
        (Invoke-TestGnu date '-u', '-d', '@1700000000', '--rfc-3339=date').Output | Should -Be @('2023-11-14')
        (Invoke-TestGnu date '-u', '-d', '@1700000000', '--rfc-3339=seconds').Output | Should -Be @('2023-11-14 22:13:20+00:00')
        (Invoke-TestGnu date '-u', '-d', '@1700000000.25', '--rfc-3339=ns').Output | Should -Be @('2023-11-14 22:13:20.250000000+00:00')
        (Invoke-TestGnu date '--rfc-3339=minutes').ErrorText | Should -Match "invalid argument 'minutes' for '--rfc-3339'"
    }

    It 'uses UTC with -u / --utc / --universal (also for parsing)' {
        (Invoke-TestGnu date '--utc', '-d', '2024-01-01 12:00', '+%H:%M %Z').Output | Should -Be @('12:00 UTC')
        (Invoke-TestGnu date '--universal', '-d', '2024-01-01T12:00:00+02:00', '+%H:%M').Output | Should -Be @('10:00')
        (Invoke-TestGnu date '-u', '--date=@86400', '+%F').Output | Should -Be @('1970-01-02')
    }

    It 'prints local time by default' {
        (Invoke-TestGnu date).Output | Should -Match '^\w{3} \w{3} [ \d]\d \d\d:\d\d:\d\d \S+ \d{4}$'
        (Invoke-TestGnu date '-d', '2024-01-15 08:30', '+%H:%M').Output | Should -Be @('08:30')
        (Invoke-TestGnu date '-d', 'yesterday', '+%F').Output | Should -Be @([datetime]::Now.AddDays(-1).ToString('yyyy-MM-dd'))
    }

    It 'prints one date per line with -f / --file' {
        $file = New-TestFile -Path (Join-Path $TestDrive 'dates.txt') -Content "@0`nnot a date`n@86400`n"
        $r = Invoke-TestGnu date '-u', '-f', $file, '+%F'
        $r.Output | Should -Be @('1970-01-01', '1970-01-02')
        $r.ErrorText | Should -Match "invalid date 'not a date'"
        $r.ExitCode | Should -Be 1
        (Invoke-TestGnu date '-u', '--file=-', '+%s' -InputObject '@5', '@6').Output | Should -Be @('5', '6')
    }

    It 'prints the modification time of a file with -r / --reference' {
        $file = New-TestFile -Path (Join-Path $TestDrive 'ref.txt') -Content 'x'
        [System.IO.File]::SetLastWriteTimeUtc($file, [datetime]::new(2001, 2, 3, 4, 5, 6, [System.DateTimeKind]::Utc))
        (Invoke-TestGnu date '-u', '-r', $file, '+%F %T').Output | Should -Be @('2001-02-03 04:05:06')
        $folder = Join-Path $TestDrive 'refdir'
        $null = New-Item -ItemType Directory -Path $folder -Force
        [System.IO.Directory]::SetLastWriteTimeUtc($folder, [datetime]::new(2002, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc))
        (Invoke-TestGnu date '-u', '--reference', $folder, '+%Y').Output | Should -Be @('2002')
        (Invoke-TestGnu date '-r', (Join-Path $TestDrive 'nope')).ErrorText | Should -Match 'No such file or directory'
    }

    It 'reports invalid dates and arguments' {
        $r = Invoke-TestGnu date '-d', 'xyz'
        $r.ErrorText | Should -Match "invalid date 'xyz'"
        $r.ExitCode | Should -Be 1
        (Invoke-TestGnu date 'xyz').ErrorText | Should -Match "invalid date 'xyz'"
        (Invoke-TestGnu date '+%F', '+%T').ErrorText | Should -Match "extra operand '\+%T'"
        (Invoke-TestGnu date '-R', '+%F').ErrorText | Should -Match 'multiple output formats specified'
        (Invoke-TestGnu date '-d', 'now', '-r', 'x').ErrorText | Should -Match 'mutually exclusive'
    }

    It 'does not set the date (-s / --set, MMDDhhmm)' {
        (Invoke-TestGnu date '-s', '2020-01-01').ErrorText | Should -Match 'setting the date is not supported'
        (Invoke-TestGnu date '--set=now').ErrorText | Should -Match 'setting the date is not supported'
        (Invoke-TestGnu date '01020304').ErrorText | Should -Match 'setting the date is not supported'
    }

    It 'formats numeric zones' {
        InModuleScope PSGnuUtils {
            $time = [System.DateTimeOffset]::new(2024, 1, 1, 0, 0, 0, [timespan]::FromHours(-4))
            Format-GnuDate -Time $time -Format '%z %:z %::z %:::z %:d' | Should -Be '-0400 -04:00 -04:00:00 -04 %:d'
            Format-GnuDateZone -Offset ([timespan]::FromMinutes(330)) -Colons 3 | Should -Be '+05:30'
        }
    }

    It 'finds time zone abbreviations' {
        InModuleScope PSGnuUtils {
            $rule = [System.TimeZoneInfo+AdjustmentRule]::CreateAdjustmentRule([datetime]::MinValue.Date, [datetime]::MaxValue.Date, [timespan]::FromHours(1),
                [System.TimeZoneInfo+TransitionTime]::CreateFixedDateRule([datetime]::new(1, 1, 1, 2, 0, 0), 3, 1),
                [System.TimeZoneInfo+TransitionTime]::CreateFixedDateRule([datetime]::new(1, 1, 1, 3, 0, 0), 10, 1))
            $europe = [System.TimeZoneInfo]::CreateCustomTimeZone('Test/Europe', [timespan]::FromHours(1), 'Europe', 'W. Europe Standard Time', 'W. Europe Daylight Time', @($rule))
            $winter = [System.DateTimeOffset]::new(2024, 1, 15, 12, 0, 0, [timespan]::FromHours(1))
            $summer = [System.DateTimeOffset]::new(2024, 7, 15, 12, 0, 0, [timespan]::FromHours(2))
            Get-GnuTimeZoneAbbreviation -Time $winter -TimeZone $europe | Should -Be 'CET'
            Get-GnuTimeZoneAbbreviation -Time $summer -TimeZone $europe | Should -Be 'CEST'
            $short = [System.TimeZoneInfo]::CreateCustomTimeZone('Test/Short', [timespan]::FromHours(3), 'Short', 'XYZ')
            Get-GnuTimeZoneAbbreviation -Time $winter -TimeZone $short | Should -Be 'XYZ'
            $india = [System.TimeZoneInfo]::CreateCustomTimeZone('Test/Odd', [timespan]::FromMinutes(330), 'Odd', 'Some Zone')
            Get-GnuTimeZoneAbbreviation -Time ([System.DateTimeOffset]::new(2024, 1, 1, 0, 0, 0, [timespan]::FromMinutes(330))) -TimeZone $india | Should -Be '+0530'
            $whole = [System.TimeZoneInfo]::CreateCustomTimeZone('Test/Whole', [timespan]::FromHours(2), 'Whole', 'Other Zone')
            Get-GnuTimeZoneAbbreviation -Time ([System.DateTimeOffset]::new(2024, 1, 1, 0, 0, 0, [timespan]::FromHours(2))) -TimeZone $whole | Should -Be '+02'
        }
    }
}
