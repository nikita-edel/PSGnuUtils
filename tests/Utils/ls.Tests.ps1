BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')

    function New-LsSandbox {
        $dir = Join-Path $TestDrive ('ls-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $null = New-TestFile -Path (Join-Path $dir 'b.txt') -Content 'bb'
        $null = New-TestFile -Path (Join-Path $dir 'a.txt') -Content 'a'
        $null = New-TestFile -Path (Join-Path $dir 'C.md') -Content 'cccc'
        $null = New-TestFile -Path (Join-Path $dir '.hidden') -Content 'h'
        $null = New-TestFile -Path (Join-Path $dir 'sub/inner.txt') -Content 'i'
        $dir
    }
    $script:esc = [string][char]27
}

Describe 'ls' {
    It 'lists visible entries sorted by name, one per line with -1' {
        $dir = New-LsSandbox
        $r = Invoke-TestGnu ls '-1' -WorkingDirectory $dir
        $r.Output | Should -Be @('a.txt', 'b.txt', 'C.md', 'sub')
        $r.ExitCode | Should -Be 0
    }

    It 'shows hidden entries with -a / --all and -A / --almost-all' {
        $dir = New-LsSandbox
        (Invoke-TestGnu ls '-1a' -WorkingDirectory $dir).Output | Should -Be @('.', '..', '.hidden', 'a.txt', 'b.txt', 'C.md', 'sub')
        (Invoke-TestGnu ls '-1', '--all' -WorkingDirectory $dir).Output.Count | Should -Be 7
        (Invoke-TestGnu ls '-1A' -WorkingDirectory $dir).Output | Should -Be @('.hidden', 'a.txt', 'b.txt', 'C.md', 'sub')
        (Invoke-TestGnu ls '-1', '--almost-all' -WorkingDirectory $dir).Output.Count | Should -Be 5
    }

    It 'hides entries with the Windows Hidden attribute' {
        if (-not (Test-IsWindowsPlatform)) { Set-ItResult -Skipped -Because 'Windows only' }
        $dir = New-LsSandbox
        $file = New-TestFile -Path (Join-Path $dir 'desktop.ini') -Content 'x'
        (Get-Item -LiteralPath $file).Attributes = 'Hidden'
        (Invoke-TestGnu ls '-1' -WorkingDirectory $dir).Output | Should -Not -Contain 'desktop.ini'
        (Invoke-TestGnu ls '-1A' -WorkingDirectory $dir).Output | Should -Contain 'desktop.ini'
    }

    It 'orders with -r / --reverse, -t, -S and -U' {
        $dir = New-LsSandbox
        (Invoke-TestGnu ls '-1r' -WorkingDirectory $dir).Output | Should -Be @('sub', 'C.md', 'b.txt', 'a.txt')
        (Invoke-TestGnu ls '-1', '--reverse' -WorkingDirectory $dir).Output[0] | Should -Be 'sub'
        $times = @{ 'a.txt' = '2020-01-01'; 'b.txt' = '2022-01-01'; 'C.md' = '2021-01-01'; 'sub' = '2019-01-01' }
        foreach ($name in $times.Keys) { (Get-Item -LiteralPath (Join-Path $dir $name)).LastWriteTime = [datetime]$times[$name] }
        (Invoke-TestGnu ls '-1t' -WorkingDirectory $dir).Output | Should -Be @('b.txt', 'C.md', 'a.txt', 'sub')
        (Invoke-TestGnu ls '-1tr' -WorkingDirectory $dir).Output[0] | Should -Be 'sub'
        (Invoke-TestGnu ls '-1S' -WorkingDirectory $dir).Output | Should -Be @('C.md', 'b.txt', 'a.txt', 'sub')
        @((Invoke-TestGnu ls '-1U' -WorkingDirectory $dir).Output | Sort-Object) | Should -Be @('a.txt', 'b.txt', 'C.md', 'sub')
        $null = New-TestFile -Path (Join-Path $dir 'same.txt') -Content 'cccc'
        (Get-Item -LiteralPath (Join-Path $dir 'same.txt')).LastWriteTime = [datetime]'2022-01-01'
        (Invoke-TestGnu ls '-1S' -WorkingDirectory $dir).Output[0..1] | Should -Be @('C.md', 'same.txt')
        (Invoke-TestGnu ls '-1t' -WorkingDirectory $dir).Output[0..1] | Should -Be @('b.txt', 'same.txt')
    }

    It 'lists directories themselves with -d / --directory and several operands with headers' {
        $dir = New-LsSandbox
        (Invoke-TestGnu ls '-1d', 'sub' -WorkingDirectory $dir).Output | Should -Be @('sub')
        (Invoke-TestGnu ls '-1', '--directory', 'sub', 'a.txt' -WorkingDirectory $dir).Output | Should -Be @('a.txt', 'sub')
        (Invoke-TestGnu ls '-1', 'b.txt', 'sub', 'a.txt' -WorkingDirectory $dir).Output | Should -Be @('a.txt', 'b.txt', '', 'sub:', 'inner.txt')
        (Invoke-TestGnu ls '-1', 'sub' -WorkingDirectory $dir).Output | Should -Be @('inner.txt')
    }

    It 'recurses with -R / --recursive' {
        $dir = New-LsSandbox
        $null = New-TestFile -Path (Join-Path $dir 'sub/deeper/z.txt') -Content 'z'
        $r = Invoke-TestGnu ls '-1R' -WorkingDirectory $dir
        $r.Output | Should -Be @('.:', 'a.txt', 'b.txt', 'C.md', 'sub', '', './sub:', 'deeper', 'inner.txt', '', './sub/deeper:', 'z.txt')
        (Invoke-TestGnu ls '-1', '--recursive', '-a', 'sub' -WorkingDirectory $dir).Output[0] | Should -Be 'sub:'
    }

    It 'appends indicators with -F / --classify and -p' {
        $dir = New-LsSandbox
        $program = 'run.cmd'
        if (-not (Test-IsWindowsPlatform)) { $program = 'run.sh' }
        $null = New-TestFile -Path (Join-Path $dir $program) -Content 'echo'
        if (-not (Test-IsWindowsPlatform)) { & chmod +x (Join-Path $dir $program) }
        $classified = (Invoke-TestGnu ls '-1F' -WorkingDirectory $dir).Output
        $classified | Should -Contain 'sub/'
        $classified | Should -Contain "$program*"
        $classified | Should -Contain 'a.txt'
        (Invoke-TestGnu ls '-1', '--classify' -WorkingDirectory $dir).Output | Should -Contain 'sub/'
        $slash = (Invoke-TestGnu ls '-1p' -WorkingDirectory $dir).Output
        $slash | Should -Contain 'sub/'
        $slash | Should -Contain $program
        if (New-TestDirectoryLink -Path (Join-Path $dir 'link') -Target (Join-Path $dir 'sub')) {
            (Invoke-TestGnu ls '-1F' -WorkingDirectory $dir).Output | Should -Contain 'link@'
            (Invoke-TestGnu ls '-1p' -WorkingDirectory $dir).Output | Should -Contain 'link'
        }
    }

    It 'prints the long format with -l and human sizes with -h / --human-readable' {
        $dir = New-LsSandbox
        $null = New-TestFile -Path (Join-Path $dir 'big.bin') -Bytes (New-Object byte[] 2000)
        $r = Invoke-TestGnu ls '-l' -WorkingDirectory $dir
        $r.Output[0] | Should -Match '^total \d+$'
        $r.Output | Where-Object { $_ -like '*a.txt' } | Should -Match '^-r[w-][x-]r-[x-]r-[x-] 1 \S+ +\S+ +1 [A-Z][a-z]{2} [ \d]\d (\d\d:\d\d| \d{4}) a\.txt$'
        $r.Output | Where-Object { $_ -like '* sub' } | Should -Match '^d'
        (Invoke-TestGnu ls '-lh' -WorkingDirectory $dir).Output | Where-Object { $_ -like '*big.bin' } | Should -Match ' 2\.0K '
        (Invoke-TestGnu ls '-l', '--human-readable' -WorkingDirectory $dir).Output[0] | Should -Match '^total \d+(\.\d)?K$'
        (Get-Item -LiteralPath (Join-Path $dir 'a.txt')).IsReadOnly = $true
        (Invoke-TestGnu ls '-l', 'a.txt' -WorkingDirectory $dir).Output | Should -Match '^-r-'
        $empty = Join-Path $dir 'empty'
        $null = New-Item -ItemType Directory -Path $empty
        (Invoke-TestGnu ls '-l', 'empty' -WorkingDirectory $dir).Output | Should -Be @('total 0')
        if (New-TestDirectoryLink -Path (Join-Path $dir 'link') -Target (Join-Path $dir 'sub')) {
            (Invoke-TestGnu ls '-l' -WorkingDirectory $dir).Output | Where-Object { $_ -like '*link*' } | Should -Match '^l.* link -> .*sub$'
        }
    }

    It 'lays out columns with -C and -w / --width' {
        $dir = New-LsSandbox
        (Invoke-TestGnu ls '-C', '-w', '20' -WorkingDirectory $dir).Output | Should -Be @('a.txt  C.md', 'b.txt  sub')
        (Invoke-TestGnu ls '-C', '--width=80' -WorkingDirectory $dir).Output | Should -Be @('a.txt  b.txt  C.md  sub')
        (Invoke-TestGnu ls '-C', '-w', '0' -WorkingDirectory $dir).Output | Should -Be @('a.txt  b.txt  C.md  sub')
        (Invoke-TestGnu ls '-C', '-w', '1' -WorkingDirectory $dir).Output | Should -Be @('a.txt', 'b.txt', 'C.md', 'sub')
        $saved = $env:COLUMNS
        try {
            $env:COLUMNS = '12'
            (Invoke-TestGnu ls '-C' -WorkingDirectory $dir).Output | Should -Be @('a.txt  C.md', 'b.txt  sub')
        }
        finally { $env:COLUMNS = $saved }
        (Invoke-TestGnu ls '-C', '-w', 'x' -WorkingDirectory $dir).ErrorText | Should -Match "invalid line width: 'x'"
        (Invoke-TestGnu ls '-C', 'empty-nothing' -WorkingDirectory $dir).ExitCode | Should -Be 2
    }

    It 'uses columns on the console and one name per line in pipelines' {
        $dir = New-LsSandbox
        Push-Location -LiteralPath $dir
        try {
            $env:COLUMNS = '80'
            InModuleScope PSGnuUtils { Mock Test-GnuConsoleOutput { $true }; Invoke-GnuLs } | Should -Be @('a.txt  b.txt  C.md  sub')
            InModuleScope PSGnuUtils { Mock Test-GnuConsoleOutput { $false }; Invoke-GnuLs } | Should -Be @('a.txt', 'b.txt', 'C.md', 'sub')
            Remove-Item Env:\COLUMNS
            @(InModuleScope PSGnuUtils { Mock Test-GnuConsoleOutput { $true }; Invoke-GnuLs }).Count | Should -BeGreaterThan 0
        }
        finally {
            Pop-Location
            Remove-Item Env:\COLUMNS -ErrorAction SilentlyContinue
        }
    }

    It 'colors names with --color=WHEN and LS_COLORS' {
        $dir = New-LsSandbox
        $saved = $env:LS_COLORS
        try {
            Remove-Item Env:\LS_COLORS -ErrorAction SilentlyContinue
            (Invoke-TestGnu ls '-1', '--color=always' -WorkingDirectory $dir).Output | Should -Contain "$esc[01;34msub$esc[0m"
            (Invoke-TestGnu ls '-1', '--color' -WorkingDirectory $dir).Output | Should -Contain 'a.txt'
            $env:LS_COLORS = 'di=31:fi=33:*.md=35'
            $colored = (Invoke-TestGnu ls '-1', '--color=yes' -WorkingDirectory $dir).Output
            $colored | Should -Contain "$esc[31msub$esc[0m"
            $colored | Should -Contain "$esc[35mC.md$esc[0m"
            $colored | Should -Contain "$esc[33ma.txt$esc[0m"
            (Invoke-TestGnu ls '-C', '-w', '20', '--color=always' -WorkingDirectory $dir).Output.Count | Should -Be 2
            (Invoke-TestGnu ls '-1', '--color=never' -WorkingDirectory $dir).Output | Should -Contain 'sub'
            Push-Location -LiteralPath $dir
            try { InModuleScope PSGnuUtils { Mock Test-GnuConsoleOutput { $false }; Invoke-GnuLs --color=auto } | Should -Contain 'sub' }
            finally { Pop-Location }
            (Invoke-TestGnu ls '--color=rainbow' -WorkingDirectory $dir).ErrorText | Should -Match "invalid argument 'rainbow' for '--color'"
            if (New-TestDirectoryLink -Path (Join-Path $dir 'link') -Target (Join-Path $dir 'sub')) {
                $env:LS_COLORS = 'ln=36'
                (Invoke-TestGnu ls '-1', '--color=always' -WorkingDirectory $dir).Output | Should -Contain "$esc[36mlink$esc[0m"
            }
            $program = 'run.cmd'
            if (-not (Test-IsWindowsPlatform)) { $program = 'run.sh' }
            $null = New-TestFile -Path (Join-Path $dir $program) -Content 'echo'
            if (-not (Test-IsWindowsPlatform)) { & chmod +x (Join-Path $dir $program) }
            $env:LS_COLORS = 'ex=32'
            (Invoke-TestGnu ls '-1', '--color=always' -WorkingDirectory $dir).Output | Should -Contain "$esc[32m$program$esc[0m"
        }
        finally { $env:LS_COLORS = $saved }
    }

    It 'reports missing operands and unreadable directories' {
        $dir = New-LsSandbox
        $r = Invoke-TestGnu ls '-1', 'nope', 'a.txt' -WorkingDirectory $dir
        $r.ErrorText | Should -BeExactly "ls: cannot access 'nope': No such file or directory"
        $r.Output | Should -Be @('a.txt')
        $r.ExitCode | Should -Be 2
        Push-Location -LiteralPath $dir
        try {
            $errors = InModuleScope PSGnuUtils {
                Mock Get-GnuLsEntry { throw (New-Object System.UnauthorizedAccessException 'denied') }
                Invoke-GnuLs -1 sub 2>&1
            }
            "$errors" | Should -Match "cannot open directory 'sub': Permission denied"
        }
        finally { Pop-Location }
    }
}

Describe 'ls helpers' {
    It 'formats human sizes like GNU' -ForEach @(
        @{ Size = 0; Human = $true; Expected = '0' }
        @{ Size = 1023; Human = $true; Expected = '1023' }
        @{ Size = 1024; Human = $true; Expected = '1.0K' }
        @{ Size = 1025; Human = $true; Expected = '1.1K' }
        @{ Size = 1536; Human = $true; Expected = '1.5K' }
        @{ Size = 10240; Human = $true; Expected = '10K' }
        @{ Size = 10300; Human = $true; Expected = '11K' }
        @{ Size = 10239; Human = $true; Expected = '10K' }
        @{ Size = 1048575; Human = $true; Expected = '1.0M' }
        @{ Size = 5368709120; Human = $true; Expected = '5.0G' }
        @{ Size = 5000; Human = $false; Expected = '5000' }
    ) {
        InModuleScope PSGnuUtils -Parameters @{ S = $Size; H = $Human } { param($S, $H) Format-GnuLsSize -Size $S -Human $H } | Should -Be $Expected
    }

    It 'formats recent and old times' {
        InModuleScope PSGnuUtils {
            $now = [datetime]'2024-06-15 12:00'
            Format-GnuLsTime -Time ([datetime]'2024-06-05 08:09') -Now $now | Should -Be 'Jun  5 08:09'
            Format-GnuLsTime -Time ([datetime]'2023-01-20 08:09') -Now $now | Should -Be 'Jan 20  2023'
            Format-GnuLsTime -Time ([datetime]'2025-01-20 08:09') -Now $now | Should -Be 'Jan 20  2025'
        }
    }

    It 'builds Unix permission strings when modes are available' {
        $file = New-TestFile -Path (Join-Path $TestDrive 'mode.txt') -Content 'x'
        InModuleScope PSGnuUtils -Parameters @{ F = $file } {
            param($F)
            Mock Get-GnuUnixFileMode { 493 }
            Get-GnuLsMode -Item (Get-Item -LiteralPath $F) | Should -Be '-rwxr-xr-x'
            Mock Get-GnuUnixFileMode { 416 }
            Get-GnuLsMode -Item (Get-Item -LiteralPath $F) | Should -Be '-rw-r-----'
            Mock Test-GnuWindows { $false }
            Mock Get-GnuUnixFileMode { 493 }
            Test-GnuLsExecutable -Item (Get-Item -LiteralPath $F) | Should -BeTrue
        }
    }

    It 'reads owners from User/Group properties and falls back to -' {
        InModuleScope PSGnuUtils {
            $fake = [pscustomobject]@{ FullName = 'x'; User = 'alice'; Group = 'staff' }
            $owner = Get-GnuLsOwner -Item ([System.IO.FileInfo]::new([System.IO.Path]::GetTempFileName()))
            $owner.Owner | Should -Not -BeNullOrEmpty
            Mock Get-Acl { }
            $none = Get-GnuLsOwner -Item ([System.IO.FileInfo]::new([System.IO.Path]::GetTempFileName()))
            if (-not ((Get-Item -LiteralPath $PSHOME).PSObject.Properties['User'])) { $none.Owner | Should -Be '-' }
            $null = $fake
        }
    }


}

Describe 'ls edge cases' {
    It 'marks only files as executable and uses default extensions without PATHEXT' {
        $dir = Join-Path $TestDrive 'ls-exec'
        $null = New-Item -ItemType Directory -Path $dir
        $exe = New-TestFile -Path (Join-Path $dir 'tool.exe') -Content 'x'
        InModuleScope PSGnuUtils -Parameters @{ D = $dir; E = $exe } {
            param($D, $E)
            Test-GnuLsExecutable -Item (Get-Item -LiteralPath $D) | Should -BeFalse
            Mock Test-GnuWindows { $true }
            $saved = $env:PATHEXT
            try {
                Remove-Item Env:\PATHEXT -ErrorAction SilentlyContinue
                Test-GnuLsExecutable -Item (Get-Item -LiteralPath $E) | Should -BeTrue
            }
            finally { $env:PATHEXT = $saved }
        }
    }

    It 'reads owners from User and Group properties (Unix)' {
        $file = New-TestFile -Path (Join-Path $TestDrive 'owned.txt') -Content 'x'
        InModuleScope PSGnuUtils -Parameters @{ F = $file } {
            param($F)
            $item = Get-Item -LiteralPath $F
            Add-Member -InputObject $item -NotePropertyName User -NotePropertyValue 'alice' -Force
            Add-Member -InputObject $item -NotePropertyName Group -NotePropertyValue 'staff' -Force
            $owner = Get-GnuLsOwner -Item $item
            $owner.Owner | Should -Be 'alice'
            $owner.Group | Should -Be 'staff'
        }
    }

    It 'skips entries that vanish while listing' {
        $dir = Join-Path $TestDrive 'ls-vanish'
        $null = New-TestFile -Path (Join-Path $dir 'stays.txt') -Content 'x'
        $null = New-TestFile -Path (Join-Path $dir 'vanish.txt') -Content 'x'
        InModuleScope PSGnuUtils -Parameters @{ D = $dir } {
            param($D)
            $real = Get-Command -Name Get-Item -CommandType Cmdlet
            Mock Get-Item { & $real @PesterBoundParameters }
            Mock Get-Item { } -ParameterFilter { $LiteralPath -like '*vanish.txt' }
            $entries = Get-GnuLsEntry -Path $D -Settings @{ Show = 'visible'; Sort = 'name'; Reverse = $false }
            @($entries | ForEach-Object { $_.Name }) | Should -Be @('stays.txt')
        }
    }

    It 'breaks name ties ordinally and leaves short last columns empty' {
        InModuleScope PSGnuUtils {
            $sorted = Get-GnuLsSortedEntry -Entries @(@{ Name = 'a' }, @{ Name = 'A' }) -Settings @{ Sort = 'name'; Reverse = $false }
            @($sorted | ForEach-Object { $_.Name }) | Should -Be @('A', 'a')
            $names = [string[]]@('aa', 'bb', 'cc', 'dd', 'ee')
            @(Format-GnuLsColumns -Names $names -Lengths ([int[]]@(2, 2, 2, 2, 2)) -Width 10) | Should -Be @('aa  cc  ee', 'bb  dd')
        }
    }
}

