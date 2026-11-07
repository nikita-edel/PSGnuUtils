BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'touch' {
    BeforeEach {
        $script:dir = Join-Path $TestDrive ('touch-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $null = New-Item -ItemType Directory -Path $dir
        $script:old = New-Object System.DateTime -ArgumentList 2001, 2, 3, 4, 5, 6
    }

    It 'creates missing files and updates existing ones to now' {
        $file = New-TestFile -Path (Join-Path $dir 'old.txt') -Content 'x'
        (Get-Item -LiteralPath $file).LastWriteTime = $old
        $r = Invoke-TestGnu touch 'new.txt', 'old.txt' -WorkingDirectory $dir
        $r.ExitCode | Should -Be 0
        (Get-Item -LiteralPath (Join-Path $dir 'new.txt')).Length | Should -Be 0
        (Get-Item -LiteralPath $file).LastWriteTime | Should -BeGreaterThan ([datetime]::Now.AddMinutes(-1))
        [System.IO.File]::ReadAllText($file) | Should -Be 'x'
    }

    It 'does not create files with -c / --no-create or -h / --no-dereference' {
        foreach ($option in @('-c', '--no-create', '-h', '--no-dereference')) {
            (Invoke-TestGnu touch $option, 'absent' -WorkingDirectory $dir).ExitCode | Should -Be 0
        }
        Test-Path -LiteralPath (Join-Path $dir 'absent') | Should -BeFalse
    }

    It 'uses a date with -d / --date' {
        $null = Invoke-TestGnu touch '-d', '2001-02-03 04:05:06', 'f' -WorkingDirectory $dir
        (Get-Item -LiteralPath (Join-Path $dir 'f')).LastWriteTime | Should -Be $old
        $null = Invoke-TestGnu touch '--date=@0', 'g' -WorkingDirectory $dir
        (Get-Item -LiteralPath (Join-Path $dir 'g')).LastWriteTimeUtc | Should -Be (New-Object System.DateTime -ArgumentList 1970, 1, 1, 0, 0, 0, ([System.DateTimeKind]::Utc))
        (Invoke-TestGnu touch '-d', 'not a date', 'h' -WorkingDirectory $dir).ErrorText | Should -Match "invalid date format 'not a date'"
    }

    It 'uses a stamp with -t' {
        $null = Invoke-TestGnu touch '-t', '200102030405.06', 'f' -WorkingDirectory $dir
        (Get-Item -LiteralPath (Join-Path $dir 'f')).LastWriteTime | Should -Be $old
        (Invoke-TestGnu touch '-t', '1302301200', 'f' -WorkingDirectory $dir).ErrorText | Should -Match "invalid date format '1302301200'"
        (Invoke-TestGnu touch '-t', 'abc', 'f' -WorkingDirectory $dir).ErrorText | Should -Match "invalid date format 'abc'"
    }

    It 'copies times from -r / --reference' {
        $reference = New-TestFile -Path (Join-Path $dir 'ref') -Content 'r'
        (Get-Item -LiteralPath $reference).LastWriteTime = $old
        $null = Invoke-TestGnu touch '-r', 'ref', 'f' -WorkingDirectory $dir
        (Get-Item -LiteralPath (Join-Path $dir 'f')).LastWriteTime | Should -Be $old
        $null = Invoke-TestGnu touch '--reference=ref', '-d', '1 day', 'g' -WorkingDirectory $dir
        (Get-Item -LiteralPath (Join-Path $dir 'g')).LastWriteTime | Should -Be $old.AddDays(1)
        (Invoke-TestGnu touch '-r', 'missing', 'f' -WorkingDirectory $dir).ErrorText | Should -Match "failed to get attributes of 'missing'"
    }

    It 'changes only one time with -a, -m and --time=WORD' {
        $file = New-TestFile -Path (Join-Path $dir 'f') -Content 'x'
        $item = Get-Item -LiteralPath $file
        $item.LastWriteTime = $old
        $item.LastAccessTime = $old
        $null = Invoke-TestGnu touch '-a', '-d', '2005-01-01', 'f' -WorkingDirectory $dir
        (Get-Item -LiteralPath $file).LastWriteTime | Should -Be $old
        $null = Invoke-TestGnu touch '-m', '-d', '2006-01-01', 'f' -WorkingDirectory $dir
        (Get-Item -LiteralPath $file).LastWriteTime.Year | Should -Be 2006
        $null = Invoke-TestGnu touch '--time=mtime', '-d', '2007-01-01', 'f' -WorkingDirectory $dir
        (Get-Item -LiteralPath $file).LastWriteTime.Year | Should -Be 2007
        $null = Invoke-TestGnu touch '--time=atime', '-d', '2008-01-01', 'f' -WorkingDirectory $dir
        (Get-Item -LiteralPath $file).LastWriteTime.Year | Should -Be 2007
        (Invoke-TestGnu touch '--time=never', 'f' -WorkingDirectory $dir).ErrorText | Should -Match "invalid argument 'never' for '--time'"
    }

    It 'ignores -f and the - operand, rejects two time sources' {
        (Invoke-TestGnu touch '-f', '-', 'f' -WorkingDirectory $dir).ExitCode | Should -Be 0
        Test-Path -LiteralPath (Join-Path $dir '-') | Should -BeFalse
        (Invoke-TestGnu touch '-d', 'now', '-t', '200101010000', 'f' -WorkingDirectory $dir).ErrorText | Should -Match 'cannot specify times from more than one source'
    }

    It 'updates directories' {
        $sub = Join-Path $dir 'sub'
        $null = New-Item -ItemType Directory -Path $sub
        $null = Invoke-TestGnu touch '-d', '2001-02-03 04:05:06', 'sub' -WorkingDirectory $dir
        (Get-Item -LiteralPath $sub).LastWriteTime | Should -Be $old
    }

    It 'reports errors' {
        (Invoke-TestGnu touch).ErrorText | Should -Match 'missing file operand'
        $r = Invoke-TestGnu touch 'no/dir/f' -WorkingDirectory $dir
        $r.ErrorText | Should -Match "cannot touch 'no/dir/f': No such file or directory"
        $r.ExitCode | Should -Be 1
        $file = New-TestFile -Path (Join-Path $dir 'denied') -Content 'x'
        $errors = InModuleScope PSGnuUtils -Parameters @{ F = $file } {
            param($F)
            Mock Get-Item { throw (New-Object System.UnauthorizedAccessException 'denied') }
            Invoke-GnuTouch $F 2>&1
        }
        "$errors" | Should -Match "setting times of '.*denied': Permission denied"
    }
}

Describe 'Date parsing' {
    BeforeAll {
        $script:now = New-Object System.DateTime -ArgumentList 2024, 1, 15, 12, 0, 0
    }

    It 'parses <Text>' -ForEach @(
        @{ Text = 'now'; Expected = '2024-01-15 12:00:00' }
        @{ Text = 'today'; Expected = '2024-01-15 12:00:00' }
        @{ Text = ''; Expected = '2024-01-15 12:00:00' }
        @{ Text = 'yesterday'; Expected = '2024-01-14 12:00:00' }
        @{ Text = 'tomorrow'; Expected = '2024-01-16 12:00:00' }
        @{ Text = '2 days ago'; Expected = '2024-01-13 12:00:00' }
        @{ Text = '+3 hours'; Expected = '2024-01-15 15:00:00' }
        @{ Text = '1 year 2 months'; Expected = '2025-03-15 12:00:00' }
        @{ Text = 'week'; Expected = '2024-01-22 12:00:00' }
        @{ Text = '1 fortnight ago'; Expected = '2024-01-01 12:00:00' }
        @{ Text = '-30 min'; Expected = '2024-01-15 11:30:00' }
        @{ Text = '10 seconds'; Expected = '2024-01-15 12:00:10' }
        @{ Text = '5 minutes'; Expected = '2024-01-15 12:05:00' }
        @{ Text = '2020-05-06'; Expected = '2020-05-06 00:00:00' }
        @{ Text = '2020-05-06 07:08:09'; Expected = '2020-05-06 07:08:09' }
        @{ Text = '2020-05-06 +1 day'; Expected = '2020-05-07 00:00:00' }
        @{ Text = 'tomorrow 2 hours ago'; Expected = '2024-01-16 10:00:00' }
    ) {
        $result = InModuleScope PSGnuUtils -Parameters @{ T = $Text; N = $now } { param($T, $N) ConvertFrom-GnuDateString -Text $T -Now $N }
        $result.ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture) | Should -Be $Expected
    }

    It 'parses epoch seconds and offsets' {
        InModuleScope PSGnuUtils {
            (ConvertFrom-GnuDateString -Text '@1.5').ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss.fff', [System.Globalization.CultureInfo]::InvariantCulture) | Should -Be '1970-01-01 00:00:01.500'
            (ConvertFrom-GnuDateString -Text '2020-01-01T00:00:00Z').ToUniversalTime().Hour | Should -Be 0
            ConvertFrom-GnuDateString -Text 'garbage' | Should -BeNullOrEmpty
            (ConvertFrom-GnuDateString -Text 'now') | Should -BeOfType [datetime]
        }
    }

    It 'parses touch stamps' {
        InModuleScope PSGnuUtils {
            $now = New-Object System.DateTime -ArgumentList 2024, 6, 1
            (ConvertFrom-GnuTouchStamp -Stamp '01020304' -Now $now).ToString('yyyy-MM-dd HH:mm') | Should -Be '2024-01-02 03:04'
            (ConvertFrom-GnuTouchStamp -Stamp '6901020304').Year | Should -Be 1969
            (ConvertFrom-GnuTouchStamp -Stamp '6801020304').Year | Should -Be 2068
            (ConvertFrom-GnuTouchStamp -Stamp '199901020304.59').Second | Should -Be 59
            (ConvertFrom-GnuTouchStamp -Stamp '01020304').Year | Should -Be ([datetime]::Now.Year)
            ConvertFrom-GnuTouchStamp -Stamp '9999' | Should -BeNullOrEmpty
        }
    }
}
