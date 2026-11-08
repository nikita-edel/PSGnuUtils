BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')

    function Invoke-TestFind {
        # find in the sandbox, with the output sorted like a listing (GNU visits in directory order).
        param([object[]]$Arguments, [switch]$Unsorted)
        $r = Invoke-TestGnu find $Arguments -WorkingDirectory $dir
        if (-not $Unsorted) { $sorted = [string[]]@($r.Output); [Array]::Sort($sorted, [System.StringComparer]::Ordinal); $r.Output = $sorted }
        $r
    }
}

# Expected results were compared with GNU findutils 4.10 and 4.11 (see docs/DEVLOG.md).
Describe 'find' {
    BeforeEach {
        $script:dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        foreach ($folder in 'd/sub/deep', 'd/empty') { $null = New-Item -ItemType Directory -Path (Join-Path $dir $folder) -Force }
        $null = New-TestFile -Path (Join-Path $dir 'd/a.txt') -Content 'hello'
        $null = New-TestFile -Path (Join-Path $dir 'd/b.log') -Bytes (New-Object byte[] 2000)
        $null = New-TestFile -Path (Join-Path $dir 'd/.hidden') -Content 'h'
        $null = New-TestFile -Path (Join-Path $dir 'd/sub/c.txt') -Content ''
        $null = New-TestFile -Path (Join-Path $dir 'd/sub/deep/e.TXT') -Content "deep`n"
        $old = New-TestFile -Path (Join-Path $dir 'd/old.txt') -Content 'old'
        [System.IO.File]::SetLastWriteTimeUtc($old, [datetime]'2020-01-02T03:04:05Z')
        $ref = New-TestFile -Path (Join-Path $dir 'ref') -Content 'ref'
        [System.IO.File]::SetLastWriteTimeUtc($ref, [datetime]'2020-06-01T00:00:00Z')
        # Directories have a size of 0 on Windows and 4096 elsewhere; .NET only knows a change time on Windows.
        $script:dirSize = 4096
        $script:changed = 5
        if (Test-IsWindowsPlatform) { $script:dirSize = 0; $script:changed = 6 }
        $script:all = @('d', 'd/.hidden', 'd/a.txt', 'd/b.log', 'd/empty', 'd/old.txt', 'd/sub', 'd/sub/c.txt', 'd/sub/deep', 'd/sub/deep/e.TXT')
    }

    Context 'starting points' {
        It 'lists everything below a starting point, in name order' {
            $r = Invoke-TestFind @('d') -Unsorted
            $r.Output | Should -Be $all
            $r.ExitCode | Should -Be 0
        }

        It 'keeps the starting point as written' {
            (Invoke-TestFind @('d/', '-maxdepth', '1', '-name', 'a.txt')).Output | Should -Be @('d/a.txt')
            (Invoke-TestFind @('./d', '-name', 'a.txt')).Output | Should -Be @('./d/a.txt')
            (Invoke-TestFind @('ref')).Output | Should -Be @('ref')
            (Invoke-TestFind @('d', 'ref', '-name', 'ref')).Output | Should -Be @('ref')
        }

        It 'uses . by default' {
            (Invoke-TestFind @('-name', 'a.txt')).Output | Should -Be @('./d/a.txt')
            (Invoke-TestFind @()).Output[0] | Should -Be '.'
        }

        It 'reports missing starting points and goes on' {
            $r = Invoke-TestFind @('nosuch', 'd', '-name', 'a.txt')
            $r.ErrorText | Should -Be "find: 'nosuch': No such file or directory"
            $r.Output | Should -Be @('d/a.txt')
            $r.ExitCode | Should -Be 1
        }

        It 'accepts -H, -L, -P, -O and --' {
            foreach ($option in '-H', '-L', '-P', '-O3') { (Invoke-TestFind @($option, 'd', '-name', 'a.txt')).Output | Should -Be @('d/a.txt') }
            (Invoke-TestFind @('--', 'd', '-name', 'a.txt')).Output | Should -Be @('d/a.txt')
        }
    }

    Context 'name tests' {
        It 'matches <Test> <Pattern>' -ForEach @(
            @{ Test = '-name'; Pattern = '*.txt'; Expected = @('d/a.txt', 'd/old.txt', 'd/sub/c.txt') }
            @{ Test = '-iname'; Pattern = '*.txt'; Expected = @('d/a.txt', 'd/old.txt', 'd/sub/c.txt', 'd/sub/deep/e.TXT') }
            @{ Test = '-name'; Pattern = '.*'; Expected = @('d/.hidden') }
            @{ Test = '-name'; Pattern = '[ab].*'; Expected = @('d/a.txt', 'd/b.log') }
            @{ Test = '-name'; Pattern = '[!abcdeo]*'; Expected = @('d/.hidden', 'd/sub') }
            @{ Test = '-name'; Pattern = '[^abcdeo]*'; Expected = @('d/.hidden', 'd/sub') }
            @{ Test = '-name'; Pattern = '?.txt'; Expected = @('d/a.txt', 'd/sub/c.txt') }
            @{ Test = '-name'; Pattern = 'a\.txt'; Expected = @('d/a.txt') }
            @{ Test = '-name'; Pattern = '[a-b]*'; Expected = @('d/a.txt', 'd/b.log') }
            @{ Test = '-name'; Pattern = '[[:upper:]]*'; Expected = @() }
            @{ Test = '-name'; Pattern = '*[[:upper:]]'; Expected = @('d/sub/deep/e.TXT') }
            @{ Test = '-name'; Pattern = '[]a]*'; Expected = @('d/a.txt') }
            @{ Test = '-name'; Pattern = '[a-]*'; Expected = @('d/a.txt') }
            @{ Test = '-name'; Pattern = '[\]]*'; Expected = @() }
            @{ Test = '-name'; Pattern = '[unclosed'; Expected = @() }
            @{ Test = '-name'; Pattern = 'd'; Expected = @('d') }
            @{ Test = '-path'; Pattern = '*sub*'; Expected = @('d/sub', 'd/sub/c.txt', 'd/sub/deep', 'd/sub/deep/e.TXT') }
            @{ Test = '-path'; Pattern = 'd/sub/*'; Expected = @('d/sub/c.txt', 'd/sub/deep', 'd/sub/deep/e.TXT') }
            @{ Test = '-ipath'; Pattern = '*DEEP*'; Expected = @('d/sub/deep', 'd/sub/deep/e.TXT') }
            @{ Test = '-wholename'; Pattern = 'd/a.txt'; Expected = @('d/a.txt') }
            @{ Test = '-iwholename'; Pattern = 'D/A.TXT'; Expected = @('d/a.txt') }
            @{ Test = '-regex'; Pattern = '.*\.txt'; Expected = @('d/a.txt', 'd/old.txt', 'd/sub/c.txt') }
            @{ Test = '-regex'; Pattern = '.*\(log\|TXT\)'; Expected = @('d/b.log', 'd/sub/deep/e.TXT') }
            @{ Test = '-regex'; Pattern = '.*s+ub'; Expected = @('d/sub') }
            @{ Test = '-regex'; Pattern = 'd/b\.lo?g'; Expected = @('d/b.log') }
            @{ Test = '-regex'; Pattern = 'd/b\.lo\?g'; Expected = @() }
            @{ Test = '-regex'; Pattern = 'd/b\+'; Expected = @() }
            @{ Test = '-regex'; Pattern = 'd/\{x\}'; Expected = @() }
            @{ Test = '-regex'; Pattern = 'd/[ab]\..*'; Expected = @('d/a.txt', 'd/b.log') }
            @{ Test = '-iregex'; Pattern = '.*\.TXT'; Expected = @('d/a.txt', 'd/old.txt', 'd/sub/c.txt', 'd/sub/deep/e.TXT') }
        ) {
            (Invoke-TestFind @('d', $Test, $Pattern)).Output | Should -Be $Expected
        }

        It 'strips trailing slashes before matching -name' {
            (Invoke-TestFind @('d/', '-name', 'd')).Output | Should -Be @('d/')
            (Invoke-TestFind @('.', '-maxdepth', '0', '-name', '.')).Output | Should -Be @('.')
        }

        It 'chooses the regex syntax with -regextype' {
            (Invoke-TestFind @('d', '-regextype', 'posix-extended', '-regex', '.*\.(log|TXT)')).Output | Should -Be @('d/b.log', 'd/sub/deep/e.TXT')
            (Invoke-TestFind @('d', '-regextype', 'egrep', '-regex', '.*/[a-c]\.[a-z]+')).Output | Should -Be @('d/a.txt', 'd/b.log', 'd/sub/c.txt')
            (Invoke-TestFind @('d', '-regextype', 'posix-basic', '-regex', '.*/c\.txt')).Output | Should -Be @('d/sub/c.txt')
            (Invoke-TestFind @('d', '-regextype', 'findutils-default', '-regex', '.*\.txt')).Output.Count | Should -Be 3
        }

        It 'reports bad regular expressions and regex types' {
            $r = Invoke-TestFind @('d', '-regextype', 'posix-extended', '-regex', '(')
            $r.ErrorText | Should -Be "find: failed to compile regular expression '(': Unmatched ( or \("
            $r.ExitCode | Should -Be 1
            (Invoke-TestFind @('d', '-regextype', 'posix-extended', '-regex', 'a)')).ErrorText | Should -Match 'Unmatched \) or \\\)'
            (Invoke-TestFind @('d', '-regextype', 'posix-extended', '-regex', '[[:bad:]]')).ErrorText | Should -Match 'Invalid character class name'
            (Invoke-TestFind @('d', '-regex', '(')).ExitCode | Should -Be 0 -Because 'in emacs syntax ( is a plain character'
            (Invoke-TestFind @('d', '-regextype', 'foo')).ErrorText | Should -Match "^find: Unknown regular expression type 'foo'; valid types are"
        }

        It 'matches link targets with -lname and -ilname' {
            $link = Join-Path $dir 'd/link'
            if (-not (New-TestDirectoryLink -Path $link -Target (Join-Path $dir 'd/sub'))) { Set-ItResult -Skipped -Because 'links cannot be created here'; return }
            try {
                (Invoke-TestFind @('d', '-lname', '*sub')).Output | Should -Be @('d/link')
                (Invoke-TestFind @('d', '-ilname', '*SUB')).Output | Should -Be @('d/link')
                (Invoke-TestFind @('d', '-type', 'l')).Output | Should -Be @('d/link')
                (Invoke-TestFind @('d', '-xtype', 'd', '-name', 'link')).Output | Should -Be @('d/link')
                (Invoke-TestFind @('-L', 'd', '-name', 'c.txt')).Output | Should -Be @('d/link/c.txt', 'd/sub/c.txt')
                (Invoke-TestFind @('-L', 'd', '-type', 'l')).Output | Should -BeNullOrEmpty
                (Invoke-TestFind @('d', '-follow', '-name', 'c.txt')).Output.Count | Should -Be 2
                (Invoke-TestFind @('-H', 'd/link', '-name', 'c.txt')).Output | Should -Be @('d/link/c.txt')
                (Invoke-TestFind @('d', '-name', 'link', '-size', '-2k')).Output | Should -Be @('d/link')
                (Invoke-TestFind @('-L', 'd', '-name', 'link', '-mmin', '-60')).Output | Should -Be @('d/link')
            }
            finally { [System.IO.Directory]::Delete($link) }
        }

        It 'reports link loops with -L' {
            $loop = Join-Path $dir 'd/sub/loop'
            if (-not (New-TestDirectoryLink -Path $loop -Target (Join-Path $dir 'd'))) { Set-ItResult -Skipped -Because 'links cannot be created here'; return }
            try {
                $r = Invoke-TestFind @('-L', 'd', '-name', 'a.txt')
                $r.Output | Should -Be @('d/a.txt')
                $r.ErrorText | Should -Be "find: File system loop detected; 'd/sub/loop' is part of the same file system loop as 'd'."
                $r.ExitCode | Should -Be 1
            }
            finally { [System.IO.Directory]::Delete($loop) }
        }
    }

    Context 'type, size and time tests' {
        It 'selects types with -type and -xtype' {
            (Invoke-TestFind @('d', '-type', 'd')).Output | Should -Be @('d', 'd/empty', 'd/sub', 'd/sub/deep')
            (Invoke-TestFind @('d', '-type', 'f', '-name', '*.log')).Output | Should -Be @('d/b.log')
            (Invoke-TestFind @('d', '-type', 'f,d')).Output.Count | Should -Be 10
            (Invoke-TestFind @('d', '-xtype', 'f', '-name', '*.log')).Output | Should -Be @('d/b.log')
            (Invoke-TestFind @('d', '-type', 'l')).Output | Should -BeNullOrEmpty
        }

        It 'reports bad -type lists: <Text>' -ForEach @(
            @{ Text = 'q'; Message = 'find: Unknown argument to -type: q' }
            @{ Text = 'fd'; Message = "find: Must separate multiple arguments to -type using: ','" }
            @{ Text = 'f,'; Message = "find: Last file type in list argument to -type is missing, i.e., list is ending on: ','" }
            @{ Text = 'f,f'; Message = "find: Duplicate file type 'f' in the argument list to -type." }
            @{ Text = 'D'; Message = 'find: -type D is not supported because Solaris doors are not supported on the platform find was compiled on.' }
        ) {
            (Invoke-TestFind @('d', '-type', $Text)).ErrorText | Should -Be $Message
        }

        It 'reports -xtype D' {
            (Invoke-TestFind @('d', '-xtype', 'D')).ErrorText | Should -Be 'find: -xtype D is not supported because Solaris doors are not supported on the platform find was compiled on.'
        }

        It 'compares sizes with -size <Size>' -ForEach @(
            @{ Size = '0'; Expected = @('d/empty', 'd/sub/c.txt') }
            @{ Size = '-1'; Expected = @('d/empty', 'd/sub/c.txt') }
            @{ Size = '4'; Expected = @('d/b.log') }
            @{ Size = '+3'; Expected = @('d/b.log') }
            @{ Size = '5c'; Expected = @('d/a.txt', 'd/sub/deep/e.TXT') }
            @{ Size = '+4c'; Expected = @('d/a.txt', 'd/b.log', 'd/sub/deep/e.TXT') }
            @{ Size = '2k'; Expected = @('d/b.log') }
            @{ Size = '1000w'; Expected = @('d/b.log') }
            @{ Size = '4b'; Expected = @('d/b.log') }
            @{ Size = '1M'; Expected = @('d/.hidden', 'd/a.txt', 'd/b.log', 'd/old.txt', 'd/sub/deep/e.TXT') }
            @{ Size = '-1G'; Expected = @('d/sub/c.txt') }
        ) {
            (Invoke-TestFind @('d', '-type', 'f', '-size', $Size)).Output | Should -Be @($Expected | Where-Object { $_ -ne 'd/empty' })
        }

        It 'reports bad sizes' {
            (Invoke-TestFind @('d', '-size', '5x')).ErrorText | Should -Be 'find: invalid -size type `x'''
            (Invoke-TestFind @('d', '-size', 'x')).ErrorText | Should -Be 'find: invalid -size type `x'''
            (Invoke-TestFind @('d', '-size', 'k')).ErrorText | Should -Be "find: Invalid argument ``k' to -size"
        }

        It 'finds empty files and directories with -empty' {
            (Invoke-TestFind @('d', '-empty')).Output | Should -Be @('d/empty', 'd/sub/c.txt')
        }

        It 'compares times with -mtime, -mmin, -atime, -amin, -ctime and -cmin' {
            (Invoke-TestFind @('d', '-mtime', '+1000')).Output | Should -Be @('d/old.txt')
            (Invoke-TestFind @('d', '-type', 'f', '-mtime', '0')).Output.Count | Should -Be 5
            (Invoke-TestFind @('d', '-type', 'f', '-mtime', '-1')).Output.Count | Should -Be 5
            (Invoke-TestFind @('d', '-type', 'f', '-mmin', '-60')).Output.Count | Should -Be 5
            (Invoke-TestFind @('d', '-type', 'f', '-mmin', '+60')).Output | Should -Be @('d/old.txt')
            (Invoke-TestFind @('d', '-type', 'f', '-ctime', '-1')).Output.Count | Should -Be $changed -Because 'a new file with an old modification time changed status now'
            (Invoke-TestFind @('d', '-type', 'f', '-cmin', '-60')).Output.Count | Should -Be $changed
            (Invoke-TestFind @('d', '-name', 'a.txt', '-atime', '-1')).Output | Should -Be @('d/a.txt')
            (Invoke-TestFind @('d', '-name', 'a.txt', '-amin', '-60')).Output | Should -Be @('d/a.txt')
            (Invoke-TestFind @('d', '-daystart', '-type', 'f', '-mtime', '0')).Output.Count | Should -Be 5
        }

        It 'reports bad time arguments' {
            (Invoke-TestFind @('d', '-mtime', 'x')).ErrorText | Should -Be "find: invalid argument ``x' to ``-mtime'"
            (Invoke-TestFind @('d', '-mmin', 'x1')).ErrorText | Should -Be "find: invalid argument ``x1' to ``-mmin'"
            (Invoke-TestFind @('d', '-mtime', '1.5')).ExitCode | Should -Be 0 -Because 'fractions are allowed'
            (Invoke-TestFind @('d', '-type', 'f', '-mtime', '-0.5')).Output.Count | Should -Be 5
        }

        It 'compares with a reference file with -newer, -anewer and -cnewer' {
            (Invoke-TestFind @('d', '-type', 'f', '!', '-newer', 'ref')).Output | Should -Be @('d/old.txt')
            (Invoke-TestFind @('d', '-type', 'f', '-cnewer', 'ref')).Output.Count | Should -Be $changed
            (Invoke-TestFind @('d', '-name', 'a.txt', '-anewer', 'ref')).Output | Should -Be @('d/a.txt')
            $r = Invoke-TestFind @('d', '-newer', 'nofile')
            $r.ErrorText | Should -Be "find: 'nofile': No such file or directory"
            $r.Output | Should -BeNullOrEmpty
        }

        It 'counts a directory as 4096 bytes off Windows' {
            InModuleScope PSGnuUtils -Parameters @{ D = (Join-Path $dir 'd') } {
                param($D)
                Mock Test-GnuWindows { $false }
                Get-GnuFindSize -Entry @{ Full = $D; Follow = $false } | Should -Be 4096
            }
        }

        It 'reads Unix file types from the mode' {
            InModuleScope PSGnuUtils -Parameters @{ F = (Join-Path $dir 'd/a.txt') } {
                param($F)
                Mock Get-GnuUnixModeString { 'prw-r--r--' }
                Get-GnuFindType -Entry @{ Full = $F } -Follow $false | Should -Be 'p'
            }
        }

        It 'treats a file that vanished as having no times' {
            InModuleScope PSGnuUtils {
                $entry = @{ Full = 'C:\no\such\file'; Follow = $false; Item = $null }
                Test-GnuFindNode -State @{ Quit = $false } -Node @{ Kind = 'test'; Name = '-mtime'; Value = @{ Sign = ''; Number = 0; Unit = 86400; Field = 'm'; Reference = [datetime]::UtcNow } } -Entry $entry | Should -BeFalse
                Test-GnuFindNode -State @{ Quit = $false } -Node @{ Kind = 'test'; Name = '-newer'; Value = [datetime]::UtcNow } -Entry $entry | Should -BeFalse
                Get-GnuFindSize -Entry @{ Full = 'C:\no\such\file'; Follow = $false; Item = $null; Typefalse = 'f' } | Should -Be 0
            }
        }
    }

    Context 'depth and operators' {
        It 'limits the depth with -maxdepth and -mindepth' {
            (Invoke-TestFind @('d', '-maxdepth', '0')).Output | Should -Be @('d')
            (Invoke-TestFind @('d', '-maxdepth', '1', '-type', 'd')).Output | Should -Be @('d', 'd/empty', 'd/sub')
            (Invoke-TestFind @('d', '-mindepth', '2')).Output | Should -Be @('d/sub/c.txt', 'd/sub/deep', 'd/sub/deep/e.TXT')
            (Invoke-TestFind @('d', '-mindepth', '3', '-maxdepth', '2')).Output | Should -BeNullOrEmpty
            (Invoke-TestFind @('d', '-name', 'a.txt', '-maxdepth', '1')).Output | Should -Be @('d/a.txt')
            (Invoke-TestFind @('d', '-maxdepth', '+1', '-name', 'sub')).Output | Should -Be @('d/sub')
        }

        It 'reports bad depths' {
            (Invoke-TestFind @('d', '-maxdepth', 'x')).ErrorText | Should -Be "find: Expected a positive decimal integer argument to -maxdepth, but got 'x'"
            (Invoke-TestFind @('d', '-mindepth', '-1')).ErrorText | Should -Be "find: Expected a positive decimal integer argument to -mindepth, but got '-1'"
            (Invoke-TestFind @('d', '-maxdepth')).ErrorText | Should -Be "find: missing argument to ``-maxdepth'"
        }

        It 'lists contents before their directory with -depth and -d' {
            (Invoke-TestFind @('d', '-depth', '-path', 'd/sub*') -Unsorted).Output | Should -Be @('d/sub/c.txt', 'd/sub/deep/e.TXT', 'd/sub/deep', 'd/sub')
            (Invoke-TestFind @('d', '-d', '-name', 'sub')).Output | Should -Be @('d/sub')
        }

        It 'combines with ! -not -a -and -o -or , and parentheses' {
            (Invoke-TestFind @('d', '!', '-type', 'd', '-name', '*.txt')).Output | Should -Be @('d/a.txt', 'd/old.txt', 'd/sub/c.txt')
            (Invoke-TestFind @('d', '-not', '-type', 'f')).Output | Should -Be @('d', 'd/empty', 'd/sub', 'd/sub/deep')
            (Invoke-TestFind @('d', '-type', 'f', '-a', '-name', '*.log')).Output | Should -Be @('d/b.log')
            (Invoke-TestFind @('d', '-type', 'f', '-and', '-name', '*.log')).Output | Should -Be @('d/b.log')
            (Invoke-TestFind @('d', '-name', 'a.txt', '-o', '-name', 'b.log')).Output | Should -Be @('d/a.txt', 'd/b.log')
            (Invoke-TestFind @('d', '-name', 'a.txt', '-or', '-name', 'b.log')).Output | Should -Be @('d/a.txt', 'd/b.log')
            (Invoke-TestFind @('d', '(', '-name', 'a.txt', '-o', '-name', 'b.log', ')', '-print')).Output | Should -Be @('d/a.txt', 'd/b.log')
            (Invoke-TestFind @('d', '-name', 'a.txt', '-o', '-name', 'b.log', '-print')).Output | Should -Be @('d/b.log')
            (Invoke-TestFind @('d', '-name', 'a.txt', '-print', ',', '-name', 'b.log', '-print')).Output | Should -Be @('d/a.txt', 'd/b.log')
            (Invoke-TestFind @('d', '-name', 'a.txt', ',', '-name', 'b.log')).Output | Should -Be @('d/b.log')
            (Invoke-TestFind @('d', '-true', '-name', 'a.txt')).Output | Should -Be @('d/a.txt')
            (Invoke-TestFind @('d', '-false')).Output | Should -BeNullOrEmpty
        }

        It 'accepts the options that change nothing here' {
            foreach ($option in '-noleaf', '-warn', '-nowarn', '-ignore_readdir_race', '-noignore_readdir_race', '-xdev', '-mount') {
                (Invoke-TestFind @('d', $option, '-name', 'a.txt')).Output | Should -Be @('d/a.txt')
            }
        }

        It 'stays on the starting volume with -xdev' {
            InModuleScope PSGnuUtils -Parameters @{ D = (Join-Path $dir 'd') } {
                param($D)
                $state = @{ Volumes = @('X:\', ((Join-Path $D 'sub') + [System.IO.Path]::DirectorySeparatorChar)) }
                Get-GnuFindVolume -State $state -Path ((Join-Path $D 'sub/deep') + '/') | Should -Be ((Join-Path $D 'sub') + [System.IO.Path]::DirectorySeparatorChar)
            }
        }
    }

    Context 'expression errors' {
        It 'reports <Name>' -ForEach @(
            @{ Name = 'unknown predicates'; Arguments = @('-foo'); Message = "find: unknown predicate ``-foo'" }
            @{ Name = 'missing arguments'; Arguments = @('-name'); Message = "find: missing argument to ``-name'" }
            @{ Name = 'an open parenthesis'; Arguments = @('('); Message = "find: invalid expression; expected to find a ')' but didn't see one. Perhaps you need an extra predicate after '('" }
            @{ Name = 'an unclosed parenthesis'; Arguments = @('(', '-true'); Message = "find: invalid expression; expected to find a ')' but didn't see one. Perhaps you need an extra predicate after '('" }
            @{ Name = 'empty parentheses'; Arguments = @('(', ')'); Message = 'find: invalid expression; empty parentheses are not allowed.' }
            @{ Name = 'a trailing )'; Arguments = @('-true', ')'); Message = "find: invalid expression; you have too many ')'" }
            @{ Name = 'a lone !'; Arguments = @('!'); Message = "find: expected an expression after '!'" }
            @{ Name = '! before an operator'; Arguments = @('!', '-o', '-print'); Message = "find: invalid expression; you have used a binary operator '-o' with nothing before it." }
            @{ Name = '! before )'; Arguments = @('(', '!', ')'); Message = "find: expected an expression after '!'" }
            @{ Name = 'a leading -o'; Arguments = @('-o'); Message = "find: invalid expression; you have used a binary operator '-o' with nothing before it." }
            @{ Name = 'a leading -a'; Arguments = @('-a'); Message = "find: invalid expression; you have used a binary operator '-a' with nothing before it." }
            @{ Name = 'a trailing -o'; Arguments = @('-true', '-o'); Message = "find: expected an expression after '-o'" }
            @{ Name = 'a trailing -a'; Arguments = @('-true', '-a'); Message = "find: expected an expression after '-a'" }
            @{ Name = 'a trailing comma'; Arguments = @('-true', ','); Message = "find: expected an expression after ','" }
            @{ Name = '-o before )'; Arguments = @('(', '-true', '-o', ')'); Message = "find: invalid expression; you have used a binary operator '-o' with nothing after it." }
            @{ Name = '-a before )'; Arguments = @('(', '-true', '-a', ')'); Message = "find: invalid expression; you have used a binary operator '-a' with nothing after it." }
            @{ Name = 'a comma before )'; Arguments = @('(', '-true', ',', ')'); Message = "find: invalid expression; you have used a binary operator ',' with nothing after it." }
            @{ Name = 'an empty -type'; Arguments = @('-type', ''); Message = "find: missing argument to ``-type'" }
            @{ Name = '-ls'; Arguments = @('-ls'); Message = 'find: -ls is not supported by PSGnuUtils' }
            @{ Name = 'paths after the expression'; Arguments = @('-name', 'a', 'y'); Message = "find: paths must precede expression: ``y'" }
            @{ Name = 'unsupported predicates'; Arguments = @('-perm', '644'); Message = 'find: -perm is not supported by PSGnuUtils' }
            @{ Name = '-delete with -prune'; Arguments = @('-delete', '-prune'); Message = 'find: The -delete action automatically turns on -depth, but -prune does nothing when -depth is in effect.  If you want to carry on anyway, just explicitly use the -depth option.' }
        ) {
            $r = Invoke-TestFind (@('d') + $Arguments)
            $r.ErrorText | Should -Be $Message
            $r.Output | Should -BeNullOrEmpty
            $r.ExitCode | Should -Be 1
        }
    }

    Context 'paths that look like operators' {
        It 'takes a leading ) or , as a file name' {
            $r = Invoke-TestFind @('d', ')', '-maxdepth', '0')
            $r.ErrorText | Should -Be "find: ')': No such file or directory"
            $r.Output | Should -Be @('d')
            $r.ExitCode | Should -Be 1
        }
    }

    Context 'printf' {
        It 'formats <Format>' -ForEach @(
            @{ Format = '%p|%f|%h|%P|%H|%d\n'; Expected = @('d|d|.||d|0', 'd/a.txt|a.txt|d|a.txt|d|1') }
            @{ Format = '%s %y %Y %l|\n'; Expected = @('{0} d d |', '5 f f |') }
            @{ Format = '%-6f|%6s|%.2f|%03d\n'; Expected = @('d     |{1}|d|000', 'a.txt |     5|a.|001') }
            @{ Format = '%n %i %D\n'; Expected = @('1 0 0', '1 0 0') }
            @{ Format = '%%|\t|\101|\\|x\n'; Expected = @("%|`t|A|\|x", "%|`t|A|\|x") }
            @{ Format = '%p\0'; Expected = @("d`0d/a.txt`0") }
            @{ Format = '%p\cignored\n'; Expected = @('dd/a.txt') }
            @{ Format = '%f '; Expected = @('d a.txt ') }
        ) {
            $wanted = @($Expected | ForEach-Object { $_.Replace('{0}', [string]$dirSize).Replace('{1}', ([string]$dirSize).PadLeft(6)) })
            (Invoke-TestFind @('d', '(', '-name', 'd', '-o', '-name', 'a.txt', ')', '-printf', $Format) -Unsorted).Output | Should -Be $wanted
        }

        It 'prints times and the size in blocks' {
            $r = Invoke-TestFind @('d', '-name', 'old.txt', '-printf', '%TY-%Tm-%Td|%T@|%A+|%t|%a|%c|%C@|%TS|%TT|%k|%b|%S\n')
            $fields = $r.Output[0].Split('|')
            $fields[0] | Should -Be ([datetime]'2020-01-02T03:04:05Z').ToLocalTime().ToString('yyyy-MM-dd')
            $fields[1] | Should -Be '1577934245.0000000000'
            $fields[2] | Should -Match '^\d{4}-\d\d-\d\d\+\d\d:\d\d:\d\d\.\d{10}$'
            $fields[3] | Should -Match '^[A-Z][a-z]{2} [A-Z][a-z]{2} [ \d]\d \d\d:\d\d:\d\d\.\d{10} 2020$'
            $fields[7] | Should -Be '05.0000000000'
            $fields[8] | Should -Match '^\d\d:04:05\.0000000000$'
            $fields[9..11] | Should -Be @('4', '8', '1365.333333')
            (Invoke-TestFind @('d', '-name', 'c.txt', '-printf', '%S\n')).Output | Should -Be @('1')
        }

        It 'prints modes, owners and the file system' {
            $r = Invoke-TestFind @('d', '-maxdepth', '0', '-printf', '%m|%M|%u|%g|%U|%G|%F\n')
            $fields = $r.Output[0].Split('|')
            $fields[0] | Should -Match '^[0-7]{3}$'
            $fields[1] | Should -Match '^d[-rwx]{9}$'
            $fields[4] | Should -Match '^\d+$'
            $fields[5] | Should -Match '^\d+$'
            $fields[6] | Should -Not -BeNullOrEmpty
        }

        It 'shows link targets with %l and %Y' {
            $link = Join-Path $dir 'd/link'
            if (-not (New-TestDirectoryLink -Path $link -Target (Join-Path $dir 'd/nowhere'))) { Set-ItResult -Skipped -Because 'links cannot be created here'; return }
            try { (Invoke-TestFind @('d', '-name', 'link', '-printf', '%y %Y %l\n')).Output[0] | Should -Match '^l N .*nowhere$' }
            # A dangling link is no directory on Unix.
            finally { if ([System.IO.Directory]::Exists($link)) { [System.IO.Directory]::Delete($link) } else { [System.IO.File]::Delete($link) } }
        }

        It 'warns about unknown directives and escapes and prints them as written' {
            $r = Invoke-TestFind @('d', '-maxdepth', '0', '-printf', '%q|\x41|%T!|%\n')
            $r.Output | Should -Be @('%q|\x41|%T!|%\n')
            $r.Warnings | Should -Be @("find: warning: unrecognized format directive ``%q'", "find: warning: unrecognized escape ``\x'", "find: warning: unrecognized format directive ``%T!'", "find: warning: unrecognized format directive ``%\'")
        }

        It 'writes to a file with -fprintf' {
            $null = Invoke-TestFind @('d', '-maxdepth', '0', '-fprintf', 'out.txt', '[%p]')
            [System.IO.File]::ReadAllText((Join-Path $dir 'out.txt')) | Should -Be '[d]'
            (Invoke-TestFind @('d', '-fprintf', 'no/such/dir/x', '%p')).ErrorText | Should -Match '^find: no/such/dir/x: '
        }

        It 'returns nothing for times of a vanished file' {
            InModuleScope PSGnuUtils {
                $entry = @{ Full = 'C:\no\such\file'; Path = 'x'; Follow = $false; Item = $null; Typefalse = 'f'; Depth = 0; Start = 'x' }
                Get-GnuFindDirective -State @{} -Entry $entry -Part @{ Kind = 'T'; Letter = '@' } | Should -Be ''
                Get-GnuFindDirective -State @{} -Entry $entry -Part @{ Kind = ''; Letter = 'M' } | Should -Be ''
                Get-GnuFindDirective -State @{ Volumes = @() } -Entry $entry -Part @{ Kind = ''; Letter = 'F' } | Should -Be 'unknown'
                Get-GnuFindDirective -State @{} -Entry $entry -Part @{ Kind = ''; Letter = 'Z' } | Should -Be ''
                Get-GnuFindDirective -State @{} -Entry @{ Full = 'C:\x'; Path = 'x'; Follow = $false; Item = $null; Typefalse = 'l'; TypeTrue = 'l' } -Part @{ Kind = ''; Letter = 'Y' } | Should -Be 'N'
                Get-GnuFindDirective -State @{} -Entry @{ Full = 'C:\x'; Path = '/'; Follow = $false; Item = $null; Typefalse = 'f' } -Part @{ Kind = ''; Letter = 'h' } | Should -Be '/'
                Get-GnuFindDirective -State @{} -Entry @{ Full = 'C:\x'; Path = '/x'; Follow = $false; Item = $null; Typefalse = 'f' } -Part @{ Kind = ''; Letter = 'h' } | Should -Be '/'
            }
        }
    }

    Context 'actions' {
        It 'prints with -print and -print0' {
            (Invoke-TestFind @('d', '-name', 'a.txt', '-print')).Output | Should -Be @('d/a.txt')
            (Invoke-TestFind @('d', '-name', '*.log', '-print0')).Output | Should -Be @("d/b.log`0")
            (Invoke-TestFind @('d', '-name', '?.*', '-print0') -Unsorted).Output | Should -Be @("d/a.txt`0d/b.log`0d/sub/c.txt`0d/sub/deep/e.TXT`0")
            (Invoke-TestFind @('d', '-name', 'a.txt', '-print0', '-o', '-name', 'b.log', '-print') -Unsorted).Output | Should -Be @("d/a.txt`0d/b.log")
        }

        It 'writes to files with -fprint and -fprint0' {
            $out = Join-Path $dir 'out.txt'
            (Invoke-TestFind @('d', '-name', '*.log', '-fprint', 'out.txt')).Output | Should -BeNullOrEmpty
            [System.IO.File]::ReadAllText($out) | Should -Be "d/b.log`n"
            $null = Invoke-TestFind @('d', '-name', '*.log', '-fprint0', 'out.txt')
            [System.IO.File]::ReadAllText($out) | Should -Be "d/b.log`0"
            (Invoke-TestFind @('d', '-fprint', 'no/such/dir/x')).ErrorText | Should -Match '^find: no/such/dir/x: '
        }

        It 'stops descending with -prune and stops completely with -quit' {
            (Invoke-TestFind @('d', '-name', 'sub', '-prune', '-o', '-print')).Output | Should -Be @('d', 'd/.hidden', 'd/a.txt', 'd/b.log', 'd/empty', 'd/old.txt')
            (Invoke-TestFind @('d', '-path', 'd/sub', '-prune')).Output | Should -Be @('d/sub')
            (Invoke-TestFind @('d', '-depth', '-name', 'sub', '-prune', '-o', '-print')).Output.Count | Should -Be 9
            (Invoke-TestFind @('d', '-name', 'a.txt', '-print', '-quit')).Output | Should -Be @('d/a.txt')
            (Invoke-TestFind @('d', 'ref', '-print', '-quit')).Output | Should -Be @('d')
            (Invoke-TestFind @('d', '-name', 'nope', '-o', '-quit')).Output | Should -BeNullOrEmpty
            (Invoke-TestFind @('d', '-depth', '-name', 'e.TXT', '-print', '-quit')).Output | Should -Be @('d/sub/deep/e.TXT')
        }

        It 'runs commands with -exec ... ;' {
            (Invoke-TestFind @('d', '-name', 'a.txt', '-exec', 'echo', 'found', '{}', ';')).Output | Should -Be @('found d/a.txt')
            (Invoke-TestFind @('d', '-name', 'a.txt', '-exec', 'echo', 'x{}y', '\;')).Output | Should -Be @('xd/a.txty')
            (Invoke-TestFind @('d', '-name', 'a.txt', '-exec', 'echo', {}, ';')).Output | Should -Be @('d/a.txt') -Because 'an unquoted {} works'
            (Invoke-TestFind @('d', '-type', 'f', '-exec', 'test', '-s', '{}', ';', '-name', '*.txt', '-print')).Output | Should -Be @('d/a.txt', 'd/old.txt')
            (Invoke-TestFind @('d', '-name', 'a.txt', '-exec', 'false', ';', '-o', '-print')).Output | Should -Contain 'd/a.txt'
            (Invoke-TestFind @('d', '-name', 'a.txt', '-exec', 'Write-Output', 'ps', '{}', ';')).Output | Should -Be @('d/a.txt', 'ps') -Because 'PowerShell commands get the arguments as they are'
        }

        It 'collects arguments with -exec ... {} +' {
            (Invoke-TestFind @('d', '-name', '*.txt', '-exec', 'echo', 'start', '{}', '+')).Output | Should -Be @('start d/a.txt d/old.txt d/sub/c.txt')
            $r = Invoke-TestFind @('d', '-name', '*.txt', '-exec', 'false', '{}', '+')
            $r.ExitCode | Should -Be 1
            InModuleScope PSGnuUtils {
                $runs = New-Object 'System.Collections.Generic.List[object]'
                Mock Invoke-GnuFindCommand { $runs.Add($Words); $true }
                $state = @{ Limit = 10; Context = @{ ExitCode = 0 } }
                $node = @{ Name = '-exec'; Batch = $true; Words = @('echo'); Pending = (New-Object 'System.Collections.Generic.List[string]'); PendingDir = $null }
                foreach ($path in 'aaaa', 'bbbb', 'cccc') { $null = Invoke-GnuFindExec -State $state -Node $node -Entry @{ Path = $path; Full = $path; Depth = 1 } }
                $runs.Count | Should -Be 1 -Because 'a batch is sent when it gets too long'
            }
        }

        It 'runs commands in the directory of the file with -execdir' {
            (Invoke-TestFind @('d', '-name', 'a.txt', '-execdir', 'echo', '{}', ';')).Output | Should -Be @('./a.txt')
            (Invoke-TestFind @('d', '-name', '?.txt', '-execdir', 'echo', '{}', '+')).Output | Should -Be @('./a.txt', './c.txt')
            (Invoke-TestFind @('d', '-name', 'c.txt', '-execdir', 'pwd', ';')).Output | Should -Be @((Resolve-Path -LiteralPath (Join-Path $dir 'd/sub')).ProviderPath)
            (Invoke-TestFind @('.', '-maxdepth', '0', '-execdir', 'echo', '{}', ';')).Output | Should -Be @('.')
        }

        It 'reports commands it cannot run' {
            $r = Invoke-TestFind @('d', '-name', 'a.txt', '-exec', 'nosuchcmd-psgnu', '{}', ';')
            $r.ErrorText | Should -Be "find: 'nosuchcmd-psgnu': No such file or directory"
            $r.ExitCode | Should -Be 0 -Because 'in GNU only the child process fails'
        }

        It 'reports bad -exec commands' -ForEach @(
            @{ Arguments = @('-exec'); Message = "find: missing argument to ``-exec'" }
            @{ Arguments = @('-exec', 'echo'); Message = "find: missing argument to ``-exec'" }
            @{ Arguments = @('-exec', ';'); Message = "find: invalid argument ``;' to ``-exec'" }
            @{ Arguments = @('-exec', 'echo', '{}', '{}', '+'); Message = 'find: Only one instance of {} is supported with -exec ... +' }
            @{ Arguments = @('-exec', 'echo', '{}x', '{}', '+'); Message = 'find: Only one instance of {} is supported with -exec ... +' }
        ) {
            (Invoke-TestFind (@('d') + $Arguments)).ErrorText | Should -Be $Message
        }

        It 'treats + as an argument unless it follows {}' {
            (Invoke-TestFind @('d', '-maxdepth', '0', '-exec', 'echo', '+', ';')).Output | Should -Be @('+')
        }

        It 'asks before running with -ok and -okdir' {
            (Invoke-TestFind @('d', '-name', 'a.txt', '-ok', 'echo', '{}', ';')).Output | Should -BeNullOrEmpty -Because 'standard input is empty, which means no'
            Mock -ModuleName PSGnuUtils Read-GnuFindAnswer { $true }
            (Invoke-TestFind @('d', '-name', 'a.txt', '-ok', 'echo', '{}', ';')).Output | Should -Be @('d/a.txt')
            (Invoke-TestFind @('d', '-name', 'a.txt', '-okdir', 'echo', '{}', ';')).Output | Should -Be @('./a.txt')
            Should -Invoke -CommandName Read-GnuFindAnswer -ModuleName PSGnuUtils -ParameterFilter { $Question -eq '< echo ... ./a.txt > ? ' }
        }

        It 'reads the -ok answer from standard input' {
            InModuleScope PSGnuUtils {
                $saved = [System.Console]::In
                try {
                    [System.Console]::SetIn((New-Object System.IO.StringReader -ArgumentList "y`n"))
                    Read-GnuFindAnswer -Question ' ' 2>$null | Should -BeTrue
                    [System.Console]::SetIn((New-Object System.IO.StringReader -ArgumentList "n`n"))
                    Read-GnuFindAnswer -Question ' ' 2>$null | Should -BeFalse
                }
                finally { [System.Console]::SetIn($saved) }
            }
        }

        It 'deletes with -delete, contents first' {
            $r = Invoke-TestFind @('d', '-name', '*.txt', '-delete', '-print') -Unsorted
            $r.Output | Should -Be @('d/a.txt', 'd/old.txt', 'd/sub/c.txt')
            Test-Path -LiteralPath (Join-Path $dir 'd/a.txt') | Should -BeFalse
            $null = Invoke-TestFind @('d', '-type', 'd', '-name', 'empty', '-delete')
            Test-Path -LiteralPath (Join-Path $dir 'd/empty') | Should -BeFalse
            $r = Invoke-TestFind @('d', '-name', 'sub', '-delete')
            $r.ErrorText | Should -Be "find: cannot delete 'd/sub': Directory not empty"
            $r.ExitCode | Should -Be 1
            $null = Invoke-TestFind @('d', '-depth', '-delete', '-prune')
            Test-Path -LiteralPath (Join-Path $dir 'd') | Should -BeFalse
        }

        It 'leaves . alone with -delete and removes read-only files' {
            $null = New-Item -ItemType Directory -Path (Join-Path $dir 'only') -Force
            $file = New-TestFile -Path (Join-Path $dir 'only/ro.txt') -Content 'x'
            if (Test-IsWindowsPlatform) { [System.IO.File]::SetAttributes($file, 'ReadOnly') }
            $r = Invoke-TestGnu find '.', '-delete' -WorkingDirectory (Join-Path $dir 'only')
            $r.ExitCode | Should -Be 0
            Test-Path -LiteralPath (Join-Path $dir 'only') | Should -BeTrue
            Test-Path -LiteralPath $file | Should -BeFalse
        }

        It 'reports files it cannot delete' {
            $null = New-Item -ItemType Directory -Path (Join-Path $dir 'guarded') -Force
            $file = New-TestFile -Path (Join-Path $dir 'guarded/x') -Content 'x'
            $guard = Block-TestFileRemoval -Path $file
            try { $r = Invoke-TestFind @('guarded', '-type', 'f', '-delete') }
            finally { $guard.Dispose() }
            $r.ErrorText | Should -Match "^find: cannot delete 'guarded/x': "
            $r.ExitCode | Should -Be 1
        }

        It 'reports directories it cannot read and goes on' {
            Mock -ModuleName PSGnuUtils Get-GnuFindEntryName { $names = [string[]]@([System.IO.Directory]::GetFileSystemEntries($Path) | ForEach-Object { [System.IO.Path]::GetFileName($_) }); [Array]::Sort($names, [System.StringComparer]::Ordinal); $names }
            Mock -ModuleName PSGnuUtils Get-GnuFindEntryName { throw [System.UnauthorizedAccessException]::new('denied') } -ParameterFilter { $Path -like '*sub' }
            $r = Invoke-TestFind @('d', '-name', '*.txt')
            $r.ErrorText | Should -Be "find: 'd/sub': Permission denied"
            $r.Output | Should -Be @('d/a.txt', 'd/old.txt')
            $r.ExitCode | Should -Be 1
            (Invoke-TestFind @('d', '-name', 'sub', '-empty')).Output | Should -BeNullOrEmpty -Because 'a directory that cannot be read is not empty'
        }

        It 'runs -execdir for a root directory in the root itself' {
            InModuleScope PSGnuUtils {
                $root = [System.IO.Path]::GetPathRoot((Get-Location -PSProvider FileSystem).ProviderPath)
                Mock Invoke-GnuFindCommand { $script:seenDirectory = $Directory; $true }
                $node = @{ Name = '-execdir'; Batch = $false; Words = @('echo', '{}') }
                Invoke-GnuFindExec -State @{} -Node $node -Entry @{ Path = $root; Full = $root; Depth = 1 } | Should -BeTrue
                $script:seenDirectory | Should -Be $root
            }
        }

        It 'needs a command before \;' {
            (Invoke-TestFind @('d', '-exec', '\;')).ErrorText | Should -Be "find: missing argument to ``-exec'"
        }
    }
}
