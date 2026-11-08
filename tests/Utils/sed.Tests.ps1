BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')

    function Invoke-TestSed {
        # sed with the argument list on six letters a..f from the pipeline.
        param([object[]]$Arguments)
        Invoke-TestGnu sed $Arguments -InputObject 'a', 'b', 'c', 'd', 'e', 'f'
    }
}

# Expected results were compared with GNU sed 4.9 (see docs/DEVLOG.md).
Describe 'sed addresses' {
    It 'selects <Script>' -ForEach @(
        @{ Script = '2p'; Expected = @('b') }
        @{ Script = '$p'; Expected = @('f') }
        @{ Script = '2,4p'; Expected = @('b', 'c', 'd') }
        @{ Script = '2,+1p'; Expected = @('b', 'c') }
        @{ Script = '2,~4p'; Expected = @('b', 'c', 'd') }
        @{ Script = '3,~3p'; Expected = @('c', 'd', 'e', 'f') }
        @{ Script = '3,~0p'; Expected = @('c') }
        @{ Script = '1~2p'; Expected = @('a', 'c', 'e') }
        @{ Script = '2~0p'; Expected = @('b') }
        @{ Script = '/b/,/d/p'; Expected = @('b', 'c', 'd') }
        @{ Script = '/b/,+1p'; Expected = @('b', 'c') }
        @{ Script = '/e/,$p'; Expected = @('e', 'f') }
        @{ Script = '0,/a/p'; Expected = @('a') }
        @{ Script = '1,/a/p'; Expected = @('a', 'b', 'c', 'd', 'e', 'f') }
        @{ Script = '4,2p'; Expected = @('d') }
        @{ Script = '2!p'; Expected = @('a', 'c', 'd', 'e', 'f') }
        @{ Script = '\,b,p'; Expected = @('b') }
        @{ Script = '/B/Ip'; Expected = @('b') }
        @{ Script = '2,5{/c/,/d/p}'; Expected = @('c', 'd') }
        @{ Script = '1  ,  2  p'; Expected = @('a', 'b') }
        @{ Script = '1 ! p'; Expected = @('b', 'c', 'd', 'e', 'f') }
        @{ Script = '1~2,2~2p'; Expected = @('a', 'b', 'c', 'd', 'e', 'f') }
    ) {
        (Invoke-TestSed @('-n', $Script)).Output | Should -Be $Expected
    }

    It 'stops an ended line range when lines were skipped' {
        (Invoke-TestSed @('-n', '2,3p;2{n;n;n}')).Output | Should -Be @('b')
    }

    It 'reports bad addresses with GNU''s position' -ForEach @(
        @{ Script = '0p'; Message = 'char 2: invalid usage of line address 0' }
        @{ Script = '0,5p'; Message = 'char 4: invalid usage of line address 0' }
        @{ Script = '/a/,p'; Message = 'char 5: unexpected `,''' }
        @{ Script = '1,'; Message = 'char 2: unexpected `,''' }
        @{ Script = '/a'; Message = 'char 2: unterminated address regex' }
        @{ Script = '\'; Message = 'char 1: unterminated address regex' }
        @{ Script = '1,2'; Message = 'char 3: missing command' }
        @{ Script = '1!!p'; Message = 'char 3: multiple `!''s' }
        @{ Script = '1,2q'; Message = 'char 4: command only uses one address' }
        @{ Script = '0'; Message = 'invalid usage of line address 0' }
    ) {
        $r = Invoke-TestSed @($Script)
        $r.ErrorText | Should -Match ([regex]::Escape($Message))
        $r.ExitCode | Should -Be 1
    }
}

Describe 'sed s command' {
    It 'applies <Script> to "<Line>"' -ForEach @(
        @{ Script = 's/o/0/'; Line = 'foo boo'; Expected = 'f0o boo' }
        @{ Script = 's/o/0/g'; Line = 'foo boo'; Expected = 'f00 b00' }
        @{ Script = 's/o/0/3'; Line = 'foo boo'; Expected = 'foo b0o' }
        @{ Script = 's/o/0/3g'; Line = 'foo boo'; Expected = 'foo b00' }
        @{ Script = 's/FOO/x/I'; Line = 'foo'; Expected = 'x' }
        @{ Script = 's/FOO/x/i'; Line = 'foo'; Expected = 'x' }
        @{ Script = 's/foo/&&/'; Line = 'foo'; Expected = 'foofoo' }
        @{ Script = 's/foo/\&/'; Line = 'foo'; Expected = '&' }
        @{ Script = 's/\(a\)\(b\)/\2\1/'; Line = 'ab'; Expected = 'ba' }
        @{ Script = 's/ab/[\0]/'; Line = 'ab'; Expected = '[ab]' }
        @{ Script = 's,a\,b,X,'; Line = 'a,b'; Expected = 'X' }
        @{ Script = 's|a\|b|X|'; Line = 'a|b'; Expected = 'X' }
        @{ Script = 's&a&\&&'; Line = 'a'; Expected = '&' }
        @{ Script = 's/a*/x/g'; Line = 'baaac'; Expected = 'xbxcx' }
        @{ Script = 's/x*/-/g'; Line = 'abc'; Expected = '-a-b-c-' }
        @{ Script = 's/b*/-/2'; Line = 'abc'; Expected = 'a-c' }
        @{ Script = 's/.*/\U&/'; Line = 'aB'; Expected = 'AB' }
        @{ Script = 's/.*/\L&/'; Line = 'aB'; Expected = 'ab' }
        @{ Script = 's/\w\+/\u&/g'; Line = 'ab cd'; Expected = 'Ab Cd' }
        @{ Script = 's/.*/\l&/'; Line = 'AB'; Expected = 'aB' }
        @{ Script = 's/\(a\) \(b\)/\U\1\E \2/'; Line = 'a b'; Expected = 'A b' }
        @{ Script = 's/.*/\L\u&/'; Line = 'aB'; Expected = 'aB' }
        @{ Script = 's/a/\t/'; Line = 'a'; Expected = "`t" }
        @{ Script = 's/a/\x41/'; Line = 'a'; Expected = 'A' }
        @{ Script = 's/a/\o101/'; Line = 'a'; Expected = 'A' }
        @{ Script = 's/a/\d065/'; Line = 'a'; Expected = 'A' }
        @{ Script = 's/a/\cA/'; Line = 'a'; Expected = [string][char]1 }
        @{ Script = 's/a/\a\f\v/'; Line = 'a'; Expected = [string][char]7 + [char]12 + [char]11 }
        @{ Script = 's/a/\q/'; Line = 'a'; Expected = 'q' }
        @{ Script = 's/\x61/b/'; Line = 'a'; Expected = 'b' }
        @{ Script = 's/\x2e/b/'; Line = 'a.'; Expected = 'ab' }
        @{ Script = 's/[\t]/b/'; Line = "a`t"; Expected = 'ab' }
        @{ Script = 's/[]]/b/'; Line = ']'; Expected = 'b' }
        @{ Script = 's/[^]]/b/'; Line = 'a'; Expected = 'b' }
        @{ Script = 's/[/]/x/'; Line = 'a/b'; Expected = 'axb' }
        @{ Script = 's/\\n/x/'; Line = '\n'; Expected = 'x' }
        @{ Script = 's/^a$/x/'; Line = 'a'; Expected = 'x' }
        @{ Script = 's/a\|b/x/g'; Line = 'ab'; Expected = 'xx' }
        @{ Script = 's/a/b/;s/b/c/'; Line = 'a'; Expected = 'c' }
        @{ Script = 's/a/b/ # comment'; Line = 'a'; Expected = 'b' }
    ) {
        (Invoke-TestGnu sed $Script -InputObject $Line).Output | Should -Be @($Expected)
    }

    It 'uses extended syntax with -E / --regexp-extended / -r' {
        foreach ($option in '-E', '--regexp-extended', '-r') { (Invoke-TestGnu sed $option, 's/(a)+/X/' -InputObject 'aab').Output | Should -Be @('Xb') }
    }

    It 'prints with the p flag and writes with w' {
        (Invoke-TestGnu sed '-n', 's/a/b/p' -InputObject 'a', 'c').Output | Should -Be @('b')
        $file = Join-Path $TestDrive 's-w.txt'
        (Invoke-TestGnu sed "s/a/b/w $file" -InputObject 'a', 'c').Output | Should -Be @('b', 'c')
        [System.IO.File]::ReadAllText($file) | Should -Be "b`n"
    }

    It 'handles several lines in the pattern space' {
        (Invoke-TestSed @('N;s/\n/+/')).Output | Should -Be @('a+b', 'c+d', 'e+f')
        (Invoke-TestSed @('N;s/b$/X/')).Output[0..1] | Should -Be @('a', 'X')
        (Invoke-TestSed @('N;s/^b/X/M')).Output[0..1] | Should -Be @('a', 'X')
        (Invoke-TestSed @('N;s/a$/X/M')).Output[0..1] | Should -Be @('X', 'b')
        (Invoke-TestSed @('N;s/a.b/X/')).Output[0] | Should -Be 'X'
        (Invoke-TestSed @('s/a/x\ny/')).Output[0..1] | Should -Be @('x', 'y')
        (Invoke-TestSed @('N;s/[\n]/+/')).Output[0] | Should -Be 'a+b'
        (Invoke-TestSed @('-n', 'N;/a$/Mp')).Output[0] | Should -Be 'a'
        (Invoke-TestGnu sed 's/\r/x/' -InputObject "a`rb").Output | Should -Be @('axb')
    }

    It 'reuses the last regex for an empty pattern' {
        (Invoke-TestSed @('/b/s//X/')).Output[1] | Should -Be 'X'
        $r = Invoke-TestSed @('s//X/')
        $r.ErrorText | Should -Be 'sed: -e expression #1, char 0: no previous regular expression'
        $r.ExitCode | Should -Be 1
    }

    It 'reports bad s commands with GNU''s position' -ForEach @(
        @{ Script = 's'; Message = 'char 1: unterminated `s'' command' }
        @{ Script = 's/a'; Message = 'char 3: unterminated `s'' command' }
        @{ Script = 's/a/b'; Message = 'char 5: unterminated `s'' command' }
        @{ Script = 's\a\b\'; Message = 'char 1: unterminated `s'' command' }
        @{ Script = 's/a/b/gg'; Message = 'char 8: multiple `g'' options to `s'' command' }
        @{ Script = 's/a/b/pp'; Message = 'char 8: multiple `p'' options to `s'' command' }
        @{ Script = 's/a/b/2 3'; Message = 'multiple number options to `s'' command' }
        @{ Script = 's/a/b/0'; Message = 'char 7: number option to `s'' command may not be zero' }
        @{ Script = 's/a/b/z'; Message = 'char 7: unknown option to `s''' }
        @{ Script = 's/\(a/b/'; Message = 'char 8: Unmatched ( or \(' }
        @{ Script = 's/a\)/b/'; Message = 'Unmatched ) or \)' }
        @{ Script = 's/a/\1/'; Message = 'char 7: invalid reference \1 on `s'' command''s RHS' }
        @{ Script = 's/[[:bad:]]/x/'; Message = 'Invalid character class name' }
        @{ Script = 's/\(a\)\2/x/'; Message = 'Invalid back reference' }
        @{ Script = 's/a\{2/x/'; Message = 'char 9: Unmatched \{' }
        @{ Script = 's/a*\{1\}\{2\}/x/'; Message = 'Invalid preceding regular expression' }
    ) {
        (Invoke-TestSed @($Script)).ErrorText | Should -Match ([regex]::Escape($Message))
    }
}

Describe 'sed commands' {
    It 'runs <Script>' -ForEach @(
        @{ Script = '2d'; Expected = @('a', 'c', 'd', 'e', 'f') }
        @{ Script = '2,5d;='; Expected = @('1', 'a', '6', 'f') }
        @{ Script = 'n;d'; Expected = @('a', 'c', 'e') }
        @{ Script = '$!N;P;D'; Expected = @('a', 'b', 'c', 'd', 'e', 'f') }
        @{ Script = 'N;P;D'; Expected = @('a', 'b', 'c', 'd', 'e', 'f') }
        @{ Script = '2,6d;G'; Expected = @('a', '') }
        @{ Script = '1!G;h;$!d'; Expected = @('f', 'e', 'd', 'c', 'b', 'a') }
        @{ Script = '2,6d;x;p;x'; Expected = @('', 'a') }
        @{ Script = '3,6d;H;$!b;x'; Expected = @('a', 'b') }
        @{ Script = '3q;H;g'; Expected = @('', 'a', '', 'a', 'b', 'c') }
        @{ Script = '1!d;z;s/^$/E/'; Expected = @('E') }
        @{ Script = 'y/ab/xy/;3,$d'; Expected = @('x', 'y') }
        @{ Script = '3,$d;y/a\nb/x y/'; Expected = @('x', 'y') }
        @{ Script = '3,$d;y/a\\b/x|y/'; Expected = @('x', 'y') }
        @{ Script = '3,$d;i\'; Expected = @('a', 'b') }
        @{ Script = '3,$d;2i inserted'; Expected = @('a', 'inserted', 'b') }
        @{ Script = '3,$d;2i\  kept'; Expected = @('a', '  kept', 'b') }
        @{ Script = '3,$d;1a added'; Expected = @('a', 'added', 'b') }
        @{ Script = "3,`$d;1a\`nline"; Expected = @('a', 'line', 'b') }
        @{ Script = "3,`$d;1a one\`ntwo"; Expected = @('a', 'one', 'two', 'b') }
        @{ Script = '3,$d;1a x\y'; Expected = @('a', 'xy', 'b') }
        @{ Script = '2c new'; Expected = @('a', 'new', 'c', 'd', 'e', 'f') }
        @{ Script = '2,4c new'; Expected = @('a', 'new', 'e', 'f') }
        @{ Script = '1,2!c x'; Expected = @('a', 'b', 'x', 'x', 'x', 'x') }
        @{ Script = '2q'; Expected = @('a', 'b') }
        @{ Script = '2Q'; Expected = @('a') }
        @{ Script = '$!d;n;s/f/g/'; Expected = @('f') }
        @{ Script = '$!d;N;s/f/g/'; Expected = @('f') }
        @{ Script = '/b/b;s/^/X/;3,$d'; Expected = @('Xa', 'b') }
        @{ Script = '/b/bend;s/^/X/;:end;3,$d'; Expected = @('Xa', 'b') }
        @{ Script = 's/a/A/;t;s/$/Z/;3,$d'; Expected = @('A', 'bZ') }
        @{ Script = 's/a/A/;tx;s/$/Z/;:x;3,$d'; Expected = @('A', 'bZ') }
        @{ Script = 's/a/A/;T;s/$/Z/'; Expected = @('AZ', 'b', 'c', 'd', 'e', 'f') }
        @{ Script = "1a x`n2,`$d"; Expected = @('a', 'x') }
        @{ Script = "r nofile`n2,`$d"; Expected = @('a') }
        @{ Script = '3,$d;2{s/$/!/;p}'; Expected = @('a', 'b!', 'b!') }
        @{ Script = '3,$d;1!{p;}'; Expected = @('a', 'b', 'b') }
        @{ Script = "3,`$d;2{`np`n}"; Expected = @('a', 'b', 'b') }
        @{ Script = ':a;N;$!ba;s/\n/ /g'; Expected = @('a b c d e f') }
        @{ Script = '# comment only'; Expected = @('a', 'b', 'c', 'd', 'e', 'f') }
        @{ Script = '3,$d;p;;;'; Expected = @('a', 'a', 'b', 'b') }
        @{ Script = '/a/,/b/{/b/!d}; 3,$d'; Expected = @('b') }
        @{ Script = '1F;2,$d'; Expected = @('-', 'a') }
    ) {
        (Invoke-TestSed @($Script)).Output | Should -Be $Expected
    }

    It 'sets the exit code with q and Q' {
        (Invoke-TestSed @('2q5')).ExitCode | Should -Be 5
        (Invoke-TestSed @('2Q7')).ExitCode | Should -Be 7
    }

    It 'quits before the auto-print with -n and q' {
        (Invoke-TestSed @('-n', '2{p;q}')).Output | Should -Be @('b')
    }

    It 'prints visibly with l' {
        (Invoke-TestGnu sed '-n', 'l' -InputObject ("a`tb\" + [char]1 + [char]0x00E9)).Output | Should -Be @('a\tb\\\001\303\251$')
        (Invoke-TestGnu sed '-n', 'N;l' -InputObject 'a', 'b').Output | Should -Be @('a\nb$')
        (Invoke-TestGnu sed '-n', 'l 4' -InputObject 'abcdef').Output | Should -Be @('abc\', 'def$')
        (Invoke-TestGnu sed '-n', 'l 0' -InputObject ('a' * 100)).Output | Should -Be @(('a' * 100) + '$')
        (Invoke-TestGnu sed '-n', 'l' -InputObject ([string][char]7 + [char]8 + [char]11 + [char]12 + [char]13 + 'x')).Output | Should -Be @('\a\b\v\f\rx$')
        (Invoke-TestGnu sed '-n', '-l', '4', 'l' -InputObject 'abcdef').Output | Should -Be @('abc\', 'def$')
        (Invoke-TestGnu sed '-n', '--line-length=4', 'l' -InputObject 'abcdef').Output | Should -Be @('abc\', 'def$')
        (Invoke-TestGnu sed '-n', '-l', 'x', 'l' -InputObject ('a' * 100)).Output | Should -Be @(('a' * 100) + '$') -Because 'GNU reads the value with atoi'
    }

    It 'reports script errors' -ForEach @(
        @{ Script = 'k'; Message = 'char 1: unknown command: `k''' }
        @{ Script = '}'; Message = 'char 1: unexpected `}''' }
        @{ Script = '{p'; Message = 'char 0: unmatched `{''' }
        @{ Script = ': '; Message = 'char 2: ":" lacks a label' }
        @{ Script = 'a'; Message = 'char 1: expected \ after `a'', `c'' or `i''' }
        @{ Script = 'y/ab/c/'; Message = 'char 7: strings for `y'' command are different lengths' }
        @{ Script = 'y/a/'; Message = 'char 4: unterminated `y'' command' }
        @{ Script = 'y'; Message = 'char 1: unterminated `y'' command' }
        @{ Script = 'y/ab'; Message = 'char 4: unterminated `y'' command' }
        @{ Script = 'dp'; Message = 'char 2: extra characters after command' }
        @{ Script = 'q 1 2'; Message = 'char 5: extra characters after command' }
        @{ Script = 'r'; Message = 'char 1: missing filename in r/R/w/W commands' }
        @{ Script = '1#c'; Message = 'comments don''t accept any addresses' }
        @{ Script = '1:a'; Message = ': doesn''t want any addresses' }
        @{ Script = '1}'; Message = 'char 2: unexpected `}''' }
        @{ Script = '{p;1}'; Message = '} doesn''t want any addresses' }
    ) {
        (Invoke-TestSed @($Script)).ErrorText | Should -Match ([regex]::Escape($Message))
    }

    It 'reports a missing label without a position, as a fatal error' {
        $r = Invoke-TestSed @('b nope')
        $r.ErrorText | Should -Be 'sed: can''t find label for jump to `nope'''
        $r.ExitCode | Should -Be 4
    }

    It 'numbers -e pieces in errors' {
        (Invoke-TestGnu sed '-e', 's/a/b', '-e', 'p' -InputObject 'a').ErrorText | Should -Match '-e expression #1, char 5'
        (Invoke-TestGnu sed '-e', 'p', '-e', 'k' -InputObject 'a').ErrorText | Should -Match '-e expression #2, char 1'
    }
}

Describe 'sed input and output' {
    BeforeEach {
        $script:dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $null = New-Item -ItemType Directory -Path $dir
        $null = New-TestFile -Path (Join-Path $dir 'one') -Content "a`nb`n"
        $null = New-TestFile -Path (Join-Path $dir 'two') -Content "c`nd`n"
    }

    It 'reads files and joins them into one stream' {
        (Invoke-TestGnu sed '-n', '$p' , 'one', 'two' -WorkingDirectory $dir).Output | Should -Be @('d')
        (Invoke-TestGnu sed '-n', '3p', 'o*', 't*' -WorkingDirectory $dir).Output | Should -Be @('c') -Because 'wildcards expand'
        (Invoke-TestGnu sed 'p', '-' , 'one' -WorkingDirectory $dir -InputObject 'x').Output | Should -Be @('x', 'x', 'a', 'a', 'b', 'b')
    }

    It 'treats files separately with -s / --separate' {
        (Invoke-TestGnu sed '-s', '-n', '$p', 'one', 'two' -WorkingDirectory $dir).Output | Should -Be @('b', 'd')
        (Invoke-TestGnu sed '--separate', '-n', '1p', 'one', 'two' -WorkingDirectory $dir).Output | Should -Be @('a', 'c')
        (Invoke-TestGnu sed '-s', '-n', '0,/a/p', 'one', 'two' -WorkingDirectory $dir).Output | Should -Be @('a', 'c', 'd') -Because 'ranges restart with each file'
    }

    It 'takes scripts from -e / --expression and -f / --file, in order' {
        $null = New-TestFile -Path (Join-Path $dir 's.sed') -Content "s/a/1/`n# comment`ns/b/2/`n"
        (Invoke-TestGnu sed '-f', 's.sed', 'one' -WorkingDirectory $dir).Output | Should -Be @('1', '2')
        (Invoke-TestGnu sed '--file=s.sed', 'one' -WorkingDirectory $dir).Output | Should -Be @('1', '2')
        (Invoke-TestGnu sed '-e', 's/1/X/', '-f', 's.sed', '-e', 's/2/Y/', 'one' -WorkingDirectory $dir).Output | Should -Be @('1', 'Y')
        (Invoke-TestGnu sed '--expression=s/a/1/', 'one' -WorkingDirectory $dir).Output | Should -Be @('1', 'b')
        (Invoke-TestGnu sed '-e', '1i\', '-e', 'text', 'one' -WorkingDirectory $dir).Output | Should -Be @('text', 'a', 'b')
    }

    It 'reports script files' {
        $null = New-TestFile -Path (Join-Path $dir 'bad.sed') -Content "p`ns/a/b`n"
        $r = Invoke-TestGnu sed '-f', 'bad.sed', 'one' -WorkingDirectory $dir
        $r.ErrorText | Should -Be 'sed: file bad.sed line 2: unterminated `s'' command'
        $r = Invoke-TestGnu sed '-f', 'nofile', 'one' -WorkingDirectory $dir
        $r.ErrorText | Should -Be 'sed: couldn''t open file nofile: No such file or directory'
        $r.ExitCode | Should -Be 4
    }

    It 'quiets with -n / --quiet / --silent and #n' {
        foreach ($option in '-n', '--quiet', '--silent') { (Invoke-TestGnu sed $option, '1p', 'one' -WorkingDirectory $dir).Output | Should -Be @('a') }
        (Invoke-TestGnu sed "#n`n1p", 'one' -WorkingDirectory $dir).Output | Should -Be @('a')
        (Invoke-TestGnu sed '#n', 'one' -WorkingDirectory $dir).Output | Should -BeNullOrEmpty
        (Invoke-TestGnu sed '#nope', 'one' -WorkingDirectory $dir).Output | Should -BeNullOrEmpty -Because 'GNU only looks at the first two characters'
    }

    It 'edits in place with -i / --in-place and backups' {
        $null = Invoke-TestGnu sed '-i', 's/a/X/', 'one', 'two' -WorkingDirectory $dir
        [System.IO.File]::ReadAllText((Join-Path $dir 'one')) | Should -Be "X`nb`n"
        $r = Invoke-TestGnu sed '-i.bak', 's/c/Y/', 'two' -WorkingDirectory $dir
        $r.Output | Should -BeNullOrEmpty
        [System.IO.File]::ReadAllText((Join-Path $dir 'two.bak')) | Should -Be "c`nd`n"
        [System.IO.File]::ReadAllText((Join-Path $dir 'two')) | Should -Be "Y`nd`n"
        $null = Invoke-TestGnu sed '--in-place=old_*', 's/X/Z/', 'one' -WorkingDirectory $dir
        [System.IO.File]::ReadAllText((Join-Path $dir 'old_one')) | Should -Be "X`nb`n"
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'keep')
        $null = Invoke-TestGnu sed '--in-place=keep/*', 's/Z/Q/', 'one' -WorkingDirectory $dir
        [System.IO.File]::ReadAllText((Join-Path $dir 'keep/one')) | Should -Be "Z`nb`n"
    }

    It 'keeps a missing final newline, invalid UTF-8 and a BOM with -i' {
        $null = New-TestFile -Path (Join-Path $dir 'nonl') -Content 'x'
        $null = Invoke-TestGnu sed '-i', 's/x/y/', 'nonl' -WorkingDirectory $dir
        [System.IO.File]::ReadAllText((Join-Path $dir 'nonl')) | Should -Be 'y'
        $null = Invoke-TestGnu sed '-i', 'p', 'nonl' -WorkingDirectory $dir
        [System.IO.File]::ReadAllText((Join-Path $dir 'nonl')) | Should -Be "y`ny"
        $null = New-TestFile -Path (Join-Path $dir 'raw') -Bytes ([byte[]](97, 255, 10))
        $null = Invoke-TestGnu sed '-i', 's/a/b/', 'raw' -WorkingDirectory $dir
        [System.IO.File]::ReadAllBytes((Join-Path $dir 'raw')) | Should -Be ([byte[]](98, 255, 10))
        $null = New-TestFile -Path (Join-Path $dir 'bom') -Bytes ([byte[]](239, 187, 191, 97, 10))
        $null = Invoke-TestGnu sed '-i', 's/a/b/', 'bom' -WorkingDirectory $dir
        [System.IO.File]::ReadAllBytes((Join-Path $dir 'bom')) | Should -Be ([byte[]](239, 187, 191, 98, 10))
    }

    It 'stops editing a file at q and keeps what was written' {
        $null = Invoke-TestGnu sed '-i', '1q', 'one', 'two' -WorkingDirectory $dir
        [System.IO.File]::ReadAllText((Join-Path $dir 'one')) | Should -Be "a`n"
        [System.IO.File]::ReadAllText((Join-Path $dir 'two')) | Should -Be "c`nd`n"
    }

    It 'handles CR+LF like Windows builds of sed, and keeps it with -b / --binary' {
        $null = New-TestFile -Path (Join-Path $dir 'crlf') -Content "a`r`nb`r`n"
        (Invoke-TestGnu sed '-b', 's/a$/X/', 'crlf' -WorkingDirectory $dir).Output[0] | Should -Be "a`r"
        (Invoke-TestGnu sed '--binary', 's/\r$/Y/', 'crlf' -WorkingDirectory $dir).Output[0] | Should -Be 'aY'
        if (Test-IsWindowsPlatform) {
            (Invoke-TestGnu sed 's/a$/X/', 'crlf' -WorkingDirectory $dir).Output | Should -Be @('X', 'b')
            $null = Invoke-TestGnu sed '-i', 's/a$/X/', 'crlf' -WorkingDirectory $dir
            [System.IO.File]::ReadAllText((Join-Path $dir 'crlf')) | Should -Be "X`r`nb`r`n"
        }
        else {
            (Invoke-TestGnu sed 's/a$/X/', 'crlf' -WorkingDirectory $dir).Output | Should -Be @("a`r", "b`r")
        }
    }

    It 'splits on NUL with -z / --null-data' {
        $null = New-TestFile -Path (Join-Path $dir 'z') -Bytes ([byte[]](97, 0, 98, 0))
        (Invoke-TestGnu sed '-z', 's/a/X/', 'z' -WorkingDirectory $dir).Output | Should -Be @("X`0b`0")
        $null = New-TestFile -Path (Join-Path $dir 'z2') -Bytes ([byte[]](97, 0, 98))
        (Invoke-TestGnu sed '--null-data', 's/a/X/', 'z2' -WorkingDirectory $dir).Output | Should -Be @("X`0b")
        (Invoke-TestGnu sed '-z', 'd', 'z' -WorkingDirectory $dir).Output | Should -BeNullOrEmpty
    }

    It 'reads files with r and R, and writes with w and W' {
        $file = Join-Path $dir 'w.txt'
        (Invoke-TestGnu sed '1r two', 'one' -WorkingDirectory $dir).Output | Should -Be @('a', 'c', 'd', 'b')
        (Invoke-TestGnu sed 'r nofile', 'one' -WorkingDirectory $dir).Output | Should -Be @('a', 'b')
        (Invoke-TestGnu sed 'R two', 'one' -WorkingDirectory $dir).Output | Should -Be @('a', 'c', 'b', 'd')
        (Invoke-TestGnu sed 'R nofile', 'one' -WorkingDirectory $dir).Output | Should -Be @('a', 'b')
        (Invoke-TestGnu sed '1r /dev/stdin', 'one' -WorkingDirectory $dir -InputObject 'in').Output | Should -Be @('a', 'in', 'b')
        (Invoke-TestGnu sed '-n', "w $file", 'one' -WorkingDirectory $dir).Output | Should -BeNullOrEmpty
        [System.IO.File]::ReadAllText($file) | Should -Be "a`nb`n"
        $null = Invoke-TestGnu sed '-n', "N;W $file", 'one' -WorkingDirectory $dir
        [System.IO.File]::ReadAllText($file) | Should -Be "a`n"
        (Invoke-TestGnu sed '-n', 'w /dev/stdout', 'one' -WorkingDirectory $dir).Output | Should -Be @('a', 'b')
        (Invoke-TestGnu sed '-n', 'w /dev/stderr', 'one' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu sed '-n', 'W /dev/stdout', 'one' -WorkingDirectory $dir).Output | Should -Be @('a', 'b')
        $r = Invoke-TestGnu sed 'w /no/such/dir/x', 'one' -WorkingDirectory $dir
        $r.ErrorText | Should -Match 'couldn''t open file /no/such/dir/x'
        $r.ExitCode | Should -Be 4
    }

    It 'disables r and w with --sandbox' {
        (Invoke-TestGnu sed '--sandbox', 'r two', 'one' -WorkingDirectory $dir).ErrorText | Should -Match 'e/r/w commands disabled in sandbox mode'
        (Invoke-TestGnu sed '--sandbox', 'p', 'one' -WorkingDirectory $dir).ExitCode | Should -Be 0
    }

    It 'accepts -u / --unbuffered, --posix and --follow-symlinks' {
        foreach ($option in '-u', '--unbuffered', '--posix', '--follow-symlinks') { (Invoke-TestGnu sed $option, '1d', 'one' -WorkingDirectory $dir).Output | Should -Be @('b') }
    }

    It 'reports input problems and goes on' {
        $r = Invoke-TestGnu sed 'p', 'nofile', 'one' -WorkingDirectory $dir
        $r.ErrorText | Should -Be 'sed: can''t read nofile: No such file or directory'
        $r.Output | Should -Be @('a', 'a', 'b', 'b')
        $r.ExitCode | Should -Be 2
        $null = New-Item -ItemType Directory -Path (Join-Path $dir 'sub')
        $r = Invoke-TestGnu sed 'p', 'sub', 'one' -WorkingDirectory $dir
        $r.ErrorText | Should -Be 'sed: read error on sub: Is a directory'
        $r.Output | Should -BeNullOrEmpty
        $r.ExitCode | Should -Be 4
        $r = Invoke-TestGnu sed '-i', 'p', 'sub' -WorkingDirectory $dir
        $r.ErrorText | Should -Be 'sed: couldn''t edit sub: not a regular file'
        $r.ExitCode | Should -Be 4
    }

    It 'wants a script' {
        $r = Invoke-TestGnu sed
        $r.ErrorText | Should -Match '^sed: Usage: sed'
        $r.ExitCode | Should -Be 1
    }

    It 'skips empty files when looking for the last line' {
        $null = New-TestFile -Path (Join-Path $dir 'empty') -Content ''
        (Invoke-TestGnu sed '-n', '$p', 'one', 'empty' -WorkingDirectory $dir).Output | Should -Be @('b')
    }
}

Describe 'sed internals' {
    It 'ignores a \c at the end of a pattern and unknown escapes' {
        (Invoke-TestGnu sed 's/a\c/b/' -InputObject 'ac').ExitCode | Should -Be 0
        (Invoke-TestGnu sed 's/a/\x/' -InputObject 'a').Output | Should -Be @('x')
        (Invoke-TestGnu sed 's/a/x\' -InputObject 'a').ErrorText | Should -Match 'unterminated `s'' command'
        (Invoke-TestGnu sed 's/a/\' -InputObject 'a').ErrorText | Should -Match 'unterminated'
        (Invoke-TestGnu sed 's/a\' -InputObject 'a').ErrorText | Should -Match 'unterminated'
    }

    It 'stops a bracket at a newline in the script' {
        (Invoke-TestGnu sed "s/[a`nb/c/" -InputObject 'a').ErrorText | Should -Match 'unterminated `s'' command'
    }

    It 'lets a final backslash in a text stand for itself' {
        (Invoke-TestGnu sed '$a x\' -InputObject 'a').Output | Should -Be @('a', 'x\')
    }
}
