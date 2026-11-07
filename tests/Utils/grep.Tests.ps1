BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')

    function New-GrepSandbox {
        $dir = Join-Path $TestDrive ('grep-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $null = New-TestFile -Path (Join-Path $dir 'a.txt') -Content "alpha`nbeta`ngamma`nalphabet`n"
        $null = New-TestFile -Path (Join-Path $dir 'b.txt') -Content "one`ntwo alpha`nthree`n"
        $null = New-TestFile -Path (Join-Path $dir 'src/code.ps1') -Content "# TODO fix`nWrite-Host 'hi'`n"
        $null = New-TestFile -Path (Join-Path $dir 'src/notes.md') -Content "TODO write docs`n"
        $null = New-TestFile -Path (Join-Path $dir 'src/skip/hidden.ps1') -Content "TODO hidden`n"
        $dir
    }
    $script:esc = [string][char]27
    $script:lines = 'one', 'two', 'three', 'four', 'five', 'six', 'seven'
}

Describe 'grep' {
    It 'prints matching lines, exit 0 on a match and 1 without' {
        $r = Invoke-TestGnu grep 'alpha' -InputObject 'alpha', 'beta', 'alphabet'
        $r.Output | Should -Be @('alpha', 'alphabet')
        $r.ExitCode | Should -Be 0
        (Invoke-TestGnu grep 'zzz' -InputObject 'alpha').ExitCode | Should -Be 1
    }

    It 'uses basic regular expressions by default and with -G / --basic-regexp' {
        (Invoke-TestGnu grep 'a\(b\)\{2\}' -InputObject 'abb', 'ab').Output | Should -Be @('abb')
        (Invoke-TestGnu grep '-G', 'a+b' -InputObject 'a+b', 'aab').Output | Should -Be @('a+b')
        (Invoke-TestGnu grep '--basic-regexp', 'x\|y' -InputObject 'x', 'z').Output | Should -Be @('x')
    }

    It 'uses extended regular expressions with -E / --extended-regexp' {
        (Invoke-TestGnu grep '-E', '(ab){2}|^z' -InputObject 'abab', 'ab', 'zed').Output | Should -Be @('abab', 'zed')
        (Invoke-TestGnu grep '--extended-regexp', 'a+b' -InputObject 'aab', 'a+b').Output | Should -Be @('aab')
    }

    It 'matches fixed strings with -F / --fixed-strings and .NET syntax with -P / --perl-regexp' {
        (Invoke-TestGnu grep '-F', 'a.b' -InputObject 'a.b', 'axb').Output | Should -Be @('a.b')
        (Invoke-TestGnu grep '--fixed-strings', '[x]' -InputObject '[x]', 'x').Output | Should -Be @('[x]')
        (Invoke-TestGnu grep '-P', '\d{3}(?=px)' -InputObject '100px', '100em').Output | Should -Be @('100px')
        (Invoke-TestGnu grep '--perl-regexp', '^\s*$' -InputObject '', 'x').Output | Should -Be @('')
    }

    It 'takes patterns from -e / --regexp and -f / --file' {
        (Invoke-TestGnu grep '-e', 'one', '-e', 'six' -InputObject $lines).Output | Should -Be @('one', 'six')
        (Invoke-TestGnu grep '--regexp=-x' -InputObject '-x', 'y').Output | Should -Be @('-x')
        (Invoke-TestGnu grep "two`nfour" -InputObject $lines).Output | Should -Be @('two', 'four')
        $file = New-TestFile -Path (Join-Path $TestDrive 'patterns.txt') -Content "three`r`nseven`n"
        (Invoke-TestGnu grep '-f', $file -InputObject $lines).Output | Should -Be @('three', 'seven')
        $empty = New-TestFile -Path (Join-Path $TestDrive 'empty-patterns.txt') -Content ''
        (Invoke-TestGnu grep "--file=$empty" -InputObject $lines).ExitCode | Should -Be 1
        (Invoke-TestGnu grep '-v', '-f', $empty -InputObject 'x').Output | Should -Be @('x')
        (Invoke-TestGnu grep '-f', (Join-Path $TestDrive 'nope') -InputObject 'x').ExitCode | Should -Be 2
        (Invoke-TestGnu grep '' -InputObject 'a', '').Output | Should -Be @('a', '')
    }

    It 'ignores case with -i / --ignore-case, --no-ignore-case undoes it' {
        (Invoke-TestGnu grep '-i', 'ALPHA' -InputObject 'Alpha', 'beta').Output | Should -Be @('Alpha')
        (Invoke-TestGnu grep '--ignore-case', 'a' -InputObject 'A').Output | Should -Be @('A')
        (Invoke-TestGnu grep '-i', '--no-ignore-case', 'a' -InputObject 'A').ExitCode | Should -Be 1
    }

    It 'matches whole words with -w and whole lines with -x' {
        (Invoke-TestGnu grep '-w', 'alpha' -InputObject 'alpha', 'alphabet', 'an alpha.').Output | Should -Be @('alpha', 'an alpha.')
        (Invoke-TestGnu grep '--word-regexp', 'a' -InputObject 'a b', 'ab').Output | Should -Be @('a b')
        (Invoke-TestGnu grep '-x', 'alpha' -InputObject 'alpha', 'alphabet').Output | Should -Be @('alpha')
        (Invoke-TestGnu grep '--line-regexp', 'a\|b' -InputObject 'a', 'ab').Output | Should -Be @('a')
    }

    It 'selects non-matching lines with -v / --invert-match' {
        (Invoke-TestGnu grep '-v', 'e' -InputObject $lines).Output | Should -Be @('two', 'four', 'six')
        (Invoke-TestGnu grep '--invert-match', '.' -InputObject 'x').ExitCode | Should -Be 1
    }

    It 'counts with -c / --count and stops with -m / --max-count' {
        (Invoke-TestGnu grep '-c', 'e' -InputObject $lines).Output | Should -Be @('4')
        (Invoke-TestGnu grep '--count', '-v', 'e' -InputObject $lines).Output | Should -Be @('3')
        (Invoke-TestGnu grep '-m', '2', 'e' -InputObject $lines).Output | Should -Be @('one', 'three')
        (Invoke-TestGnu grep '--max-count=1', '-c', 'e' -InputObject $lines).Output | Should -Be @('1')
        (Invoke-TestGnu grep '-m', '1', '-A', '1', 'o' -InputObject 'one', 'x', 'two', 'y').Output | Should -Be @('one', 'x')
        (Invoke-TestGnu grep '-m', '1', '-A', '3', 'o' -InputObject 'one', 'x', 'two', 'y').Output | Should -Be @('one', 'x')
        (Invoke-TestGnu grep '-m', 'x', 'e' -InputObject 'a').ErrorText | Should -Match "invalid max count: 'x'"
    }

    It 'prints line numbers with -n / --line-number and byte offsets with -b / --byte-offset' {
        (Invoke-TestGnu grep '-n', 'e' -InputObject 'one', 'two', 'three').Output | Should -Be @('1:one', '3:three')
        (Invoke-TestGnu grep '--line-number', 'two' -InputObject 'one', 'two').Output | Should -Be @('2:two')
        (Invoke-TestGnu grep '-b', 'two' -InputObject 'one', 'two').Output | Should -Be @('4:two')
        (Invoke-TestGnu grep '--byte-offset', '-o', 'b' -InputObject 'abcb').Output | Should -Be @('1:b', '3:b')
    }

    It 'prints only the matches with -o / --only-matching' {
        (Invoke-TestGnu grep '-o', '[0-9]\+' -InputObject 'a1b22', 'none').Output | Should -Be @('1', '22')
        (Invoke-TestGnu grep '--only-matching', '-n', 'x' -InputObject 'axbx').Output | Should -Be @('1:x', '1:x')
        (Invoke-TestGnu grep '-o', '-v', 'x' -InputObject 'y').Output.Count | Should -Be 0
        (Invoke-TestGnu grep '-o', 'x*' -InputObject 'abc').Output.Count | Should -Be 0
    }

    It 'is silent with -q / --quiet / --silent' {
        $r = Invoke-TestGnu grep '-q', 'e' -InputObject $lines
        $r.Output.Count | Should -Be 0
        $r.ExitCode | Should -Be 0
        (Invoke-TestGnu grep '--quiet', 'zzz' -InputObject $lines).ExitCode | Should -Be 1
        (Invoke-TestGnu grep '--silent', 'one' -InputObject $lines).ExitCode | Should -Be 0
    }

    It 'prints context with -A, -B, -C, -NUM and separates groups with --' {
        (Invoke-TestGnu grep '-A', '1', 'two' -InputObject $lines).Output | Should -Be @('two', 'three')
        (Invoke-TestGnu grep '--after-context=1', 'two\|six' -InputObject $lines).Output | Should -Be @('two', 'three', '--', 'six', 'seven')
        (Invoke-TestGnu grep '-B', '1', 'three' -InputObject $lines).Output | Should -Be @('two', 'three')
        (Invoke-TestGnu grep '--before-context=2', 'seven' -InputObject $lines).Output | Should -Be @('five', 'six', 'seven')
        (Invoke-TestGnu grep '-C', '1', 'four' -InputObject $lines).Output | Should -Be @('three', 'four', 'five')
        (Invoke-TestGnu grep '--context=1', 'one\|seven' -InputObject $lines).Output | Should -Be @('one', 'two', '--', 'six', 'seven')
        (Invoke-TestGnu grep '-1', '-n', 'four' -InputObject $lines).Output | Should -Be @('3-three', '4:four', '5-five')
        (Invoke-TestGnu grep '-C', '1', 'two\|three' -InputObject $lines).Output | Should -Be @('one', 'two', 'three', 'four')
        (Invoke-TestGnu grep '-A', 'x', 'a' -InputObject 'a').ErrorText | Should -Match "invalid context length argument: 'x'"
    }

    It 'searches files, shows names for several files, -H / --with-filename and -h / --no-filename' {
        $dir = New-GrepSandbox
        (Invoke-TestGnu grep 'alpha', 'a.txt' -WorkingDirectory $dir).Output | Should -Be @('alpha', 'alphabet')
        (Invoke-TestGnu grep 'alpha', 'a.txt', 'b.txt' -WorkingDirectory $dir).Output | Should -Be @('a.txt:alpha', 'a.txt:alphabet', 'b.txt:two alpha')
        (Invoke-TestGnu grep '-H', 'beta', 'a.txt' -WorkingDirectory $dir).Output | Should -Be @('a.txt:beta')
        (Invoke-TestGnu grep '--with-filename', '-n', 'beta', 'a.txt' -WorkingDirectory $dir).Output | Should -Be @('a.txt:2:beta')
        (Invoke-TestGnu grep '-h', 'alpha', 'a.txt', 'b.txt' -WorkingDirectory $dir).Output | Should -Be @('alpha', 'alphabet', 'two alpha')
        (Invoke-TestGnu grep '--no-filename', 'one', 'a.txt', 'b.txt' -WorkingDirectory $dir).Output | Should -Be @('one')
        (Invoke-TestGnu grep '-c', 'alpha', 'a.txt', 'b.txt' -WorkingDirectory $dir).Output | Should -Be @('a.txt:2', 'b.txt:1')
        (Invoke-TestGnu grep '-H', 'x', '-', '--label=input' -InputObject 'x').Output | Should -Be @('input:x')
        (Invoke-TestGnu grep '-H', 'x' -InputObject 'x').Output | Should -Be @('(standard input):x')
        (Invoke-TestGnu grep '-H', 'x', '-', 'a.txt' -InputObject 'x' -WorkingDirectory $dir).Output | Should -Be @('(standard input):x')
    }

    It 'lists file names with -l / --files-with-matches and -L / --files-without-match' {
        $dir = New-GrepSandbox
        (Invoke-TestGnu grep '-l', 'alpha', 'a.txt', 'b.txt', 'src/notes.md' -WorkingDirectory $dir).Output | Should -Be @('a.txt', 'b.txt')
        (Invoke-TestGnu grep '--files-with-matches', 'gamma', 'a.txt', 'b.txt' -WorkingDirectory $dir).Output | Should -Be @('a.txt')
        (Invoke-TestGnu grep '-L', 'gamma', 'a.txt', 'b.txt' -WorkingDirectory $dir).Output | Should -Be @('b.txt')
        (Invoke-TestGnu grep '--files-without-match', 'alpha', 'a.txt' -WorkingDirectory $dir).Output.Count | Should -Be 0
        (Invoke-TestGnu grep '-lZ', 'alpha', 'a.txt', 'b.txt' -WorkingDirectory $dir).Output | Should -Be @("a.txt`0", "b.txt`0")
        (Invoke-TestGnu grep '-LZ', 'gamma', 'a.txt', 'b.txt' -WorkingDirectory $dir).Output | Should -Be @("b.txt`0")
    }

    It 'separates names with NUL with -Z / --null' {
        $dir = New-GrepSandbox
        (Invoke-TestGnu grep '-Z', 'beta', 'a.txt', 'b.txt' -WorkingDirectory $dir).Output | Should -Be @("a.txt`0beta")
        (Invoke-TestGnu grep '--null', '-c', 'beta', 'a.txt', 'b.txt' -WorkingDirectory $dir).Output | Should -Be @("a.txt`01", "b.txt`00")
    }

    It 'searches directories with -r / --recursive and -R / --dereference-recursive' {
        $dir = New-GrepSandbox
        (Invoke-TestGnu grep '-r', 'TODO', 'src' -WorkingDirectory $dir).Output | Should -Be @('src/code.ps1:# TODO fix', 'src/notes.md:TODO write docs', 'src/skip/hidden.ps1:TODO hidden')
        (Invoke-TestGnu grep '--recursive', '-l', 'TODO' -WorkingDirectory (Join-Path $dir 'src')).Output | Should -Be @('./code.ps1', './notes.md', './skip/hidden.ps1')
        (Invoke-TestGnu grep '-R', '-c', 'hidden', 'src/skip' -WorkingDirectory $dir).Output | Should -Be @('src/skip/hidden.ps1:1')
        (Invoke-TestGnu grep '--dereference-recursive', '-h', 'fix', 'src' -WorkingDirectory $dir).Output | Should -Be @('# TODO fix')
        $r = Invoke-TestGnu grep 'x', 'src' -WorkingDirectory $dir
        $r.ErrorText | Should -Match 'src: Is a directory'
        $r.ExitCode | Should -Be 2
    }

    It 'filters files with --include, --exclude and --exclude-dir' {
        $dir = New-GrepSandbox
        (Invoke-TestGnu grep '-rl', '--include=*.ps1', 'TODO', 'src' -WorkingDirectory $dir).Output | Should -Be @('src/code.ps1', 'src/skip/hidden.ps1')
        (Invoke-TestGnu grep '-rl', '--exclude=*.ps1', 'TODO', 'src' -WorkingDirectory $dir).Output | Should -Be @('src/notes.md')
        (Invoke-TestGnu grep '-rl', '--exclude-dir=skip', 'TODO', 'src' -WorkingDirectory $dir).Output | Should -Be @('src/code.ps1', 'src/notes.md')
        (Invoke-TestGnu grep '--exclude=a.txt', 'alpha', 'a.txt', 'b.txt' -WorkingDirectory $dir).Output | Should -Be @('b.txt:two alpha')
    }

    It 'handles binary files with --binary-files, -a / --text and -I' {
        $dir = New-GrepSandbox
        $null = New-TestFile -Path (Join-Path $dir 'bin.dat') -Bytes ([byte[]](0x61, 0x6C, 0x70, 0x68, 0x61, 0x00, 0x0A))
        (Invoke-TestGnu grep 'alpha', 'bin.dat' -WorkingDirectory $dir).Output | Should -Be @('grep: bin.dat: binary file matches')
        (Invoke-TestGnu grep '-a', 'alpha', 'bin.dat' -WorkingDirectory $dir).Output | Should -Be @("alpha`0")
        (Invoke-TestGnu grep '--text', '-c', 'alpha', 'bin.dat' -WorkingDirectory $dir).Output | Should -Be @('1')
        $r = Invoke-TestGnu grep '-I', 'alpha', 'bin.dat' -WorkingDirectory $dir
        $r.Output.Count | Should -Be 0
        $r.ExitCode | Should -Be 1
        (Invoke-TestGnu grep '--binary-files=without-match', 'alpha', 'bin.dat', 'a.txt' -WorkingDirectory $dir).Output | Should -Be @('a.txt:alpha', 'a.txt:alphabet')
        (Invoke-TestGnu grep '--binary-files=text', 'alpha', 'bin.dat' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu grep '--binary-files=maybe', 'a' -InputObject 'a').ErrorText | Should -Match "invalid argument 'maybe' for '--binary-files'"
    }

    It 'splits data on NUL with -z / --null-data' {
        $dir = New-GrepSandbox
        $null = New-TestFile -Path (Join-Path $dir 'z.dat') -Content "one`0two`0three`0"
        (Invoke-TestGnu grep '-z', 't', 'z.dat' -WorkingDirectory $dir).Output | Should -Be @("two`0", "three`0")
        (Invoke-TestGnu grep '--null-data', 'two' -InputObject "one`0two").Output | Should -Be @("two`0")
    }

    It 'highlights matches with --color / --colour' {
        $r = Invoke-TestGnu grep '--color=always', 'lp' -InputObject 'alpha'
        $r.Output | Should -Be @("a$esc[01;31m$esc[Klp$esc[m$esc[Kha")
        (Invoke-TestGnu grep '--colour=always', '-n', 'a' -InputObject 'a').Output | Should -Be @("$esc[32m$esc[K1$esc[m$esc[K$esc[36m$esc[K:$esc[m$esc[K$esc[01;31m$esc[Ka$esc[m$esc[K")
        (Invoke-TestGnu grep '--color=always', '-o', 'b' -InputObject 'abc').Output | Should -Be @("$esc[01;31m$esc[Kb$esc[m$esc[K")
        (Invoke-TestGnu grep '--color=always', '-A', '1', 'x' -InputObject 'x', 'y', 'z', 'x').Output[2] | Should -Be "$esc[36m$esc[K--$esc[m$esc[K"
        (Invoke-TestGnu grep '--color=never', 'lp' -InputObject 'alpha').Output | Should -Be @('alpha')
        (Invoke-TestGnu grep '--color', 'lp' -InputObject 'alpha').Output[0] | Should -Match ([regex]::Escape("$esc[01;31m"))
        InModuleScope PSGnuUtils { Mock Test-GnuConsoleOutput { $false }; 'alpha' | Invoke-GnuGrep --color=auto lp } | Should -Be 'alpha'
        (Invoke-TestGnu grep '--color=sometimes', 'a' -InputObject 'a').ErrorText | Should -Match "invalid argument 'sometimes' for '--color'"
        $dir = New-GrepSandbox
        (Invoke-TestGnu grep '--color=always', '-l', 'beta', 'a.txt' -WorkingDirectory $dir).Output | Should -Be @("$esc[35m$esc[Ka.txt$esc[m$esc[K")
    }

    It 'renders pipeline objects like the console shows them' {
        $objects = @([pscustomobject]@{ Name = 'pwsh'; Id = 1 }, [pscustomobject]@{ Name = 'notepad'; Id = 2 })
        $r = Invoke-TestGnu grep 'pwsh' -InputObject $objects
        $r.Output.Count | Should -Be 1
        $r.Output[0] | Should -Match '^pwsh\s+1$'
    }

    It 'reports errors, suppressed with -s / --no-messages' {
        $dir = New-GrepSandbox
        $r = Invoke-TestGnu grep 'alpha', 'missing.txt', 'a.txt' -WorkingDirectory $dir
        $r.ErrorText | Should -BeExactly 'grep: missing.txt: No such file or directory'
        $r.Output | Should -Be @('a.txt:alpha', 'a.txt:alphabet')
        $r.ExitCode | Should -Be 2
        $s = Invoke-TestGnu grep '-s', 'alpha', 'missing.txt' -WorkingDirectory $dir
        $s.Errors.Count | Should -Be 0
        $s.ExitCode | Should -Be 2
        (Invoke-TestGnu grep '--no-messages', 'x', 'src' -WorkingDirectory $dir).Errors.Count | Should -Be 0
        (Invoke-TestGnu grep '-q', 'alpha', 'missing.txt', 'a.txt' -WorkingDirectory $dir).ExitCode | Should -Be 0
        (Invoke-TestGnu grep).ExitCode | Should -Be 2
        (Invoke-TestGnu grep 'a\(' -InputObject 'a').ErrorText | Should -Match 'Unmatched \( or \\\('
        (Invoke-TestGnu grep '-E', 'a)' -InputObject 'a').ErrorText | Should -Match 'Unmatched \) or \\\)'
        (Invoke-TestGnu grep '-P', 'a{2,1}' -InputObject 'a').ErrorText | Should -Match 'Invalid regular expression'
        (Invoke-TestGnu grep '[[:nope:]]' -InputObject 'a').ErrorText | Should -Match 'Invalid character class name'
        $lock = Lock-TestFile -Path (Join-Path $dir 'b.txt')
        if ($null -ne $lock) {
            try {
                (Invoke-TestGnu grep 'x', 'b.txt' -WorkingDirectory $dir).ExitCode | Should -Be 2
                (Invoke-TestGnu grep '-s', 'x', 'b.txt' -WorkingDirectory $dir).Errors.Count | Should -Be 0
            }
            finally { $lock.Dispose() }
        }
    }
}

Describe 'POSIX regular expression translation' {
    It 'translates <Pattern> (<Kind>) to <Expected>' -ForEach @(
        @{ Kind = 'BRE'; Pattern = 'a\(b\)*'; Expected = 'a(b)*' }
        @{ Kind = 'BRE'; Pattern = 'a(b)+?{|}'; Expected = 'a\(b\)\+\?\{\|\}' }
        @{ Kind = 'BRE'; Pattern = '*a'; Expected = '\*a' }
        @{ Kind = 'BRE'; Pattern = '^*a'; Expected = '^\*a' }
        @{ Kind = 'BRE'; Pattern = 'a^b'; Expected = 'a\^b' }
        @{ Kind = 'BRE'; Pattern = 'a$b$'; Expected = 'a\$b$' }
        @{ Kind = 'BRE'; Pattern = '\(a$\)'; Expected = '(a$)' }
        @{ Kind = 'BRE'; Pattern = 'x\{2,3\}'; Expected = 'x{2,3}' }
        @{ Kind = 'BRE'; Pattern = '\<w\>'; Expected = '\b(?=\w)w\b(?<=\w)' }
        @{ Kind = 'BRE'; Pattern = '\(a\)\1'; Expected = '(a)\1' }
        @{ Kind = 'BRE'; Pattern = '\`a\'''; Expected = '\Aa\z' }
        @{ Kind = 'BRE'; Pattern = '\.\#'; Expected = '\.\#' }
        @{ Kind = 'BRE'; Pattern = 'a b'; Expected = 'a\ b' }
        @{ Kind = 'ERE'; Pattern = '(a|b)+c?'; Expected = '(a|b)+c?' }
        @{ Kind = 'ERE'; Pattern = 'a{2}b{x'; Expected = 'a{2}b\{x' }
        @{ Kind = 'ERE'; Pattern = 'a^b$c'; Expected = 'a^b$c' }
        @{ Kind = 'ERE'; Pattern = '(*a)'; Expected = '(\*a)' }
        @{ Kind = 'ERE'; Pattern = '\w\s'; Expected = '\w\s' }
        @{ Kind = 'BRE'; Pattern = '[[:alpha:]_]'; Expected = '[\p{L}_]' }
        @{ Kind = 'BRE'; Pattern = '[^]a\[]'; Expected = '[^]a\\\[]' }
        @{ Kind = 'BRE'; Pattern = '[[=e=][.-.]x^]'; Expected = '[e\-x\^]' }
        @{ Kind = 'BRE'; Pattern = '[[:digit:][:xdigit:][:alnum:][:upper:][:lower:][:space:][:blank:][:punct:][:print:][:graph:][:cntrl:]]'; Expected = '[0-90-9A-Fa-f\p{L}\p{Nd}\p{Lu}\p{Ll}\s \t\p{P}\p{S}\P{C}\p{L}\p{M}\p{N}\p{P}\p{S}\p{Cc}]' }
    ) {
        $result = InModuleScope PSGnuUtils -Parameters @{ P = $Pattern; E = ($Kind -eq 'ERE') } { param($P, $E) ConvertTo-GnuDotNetRegex -Pattern $P -Extended:$E }
        $result.Regex | Should -BeExactly $Expected
    }

    It 'reports invalid expressions' {
        InModuleScope PSGnuUtils {
            (ConvertTo-GnuDotNetRegex -Pattern 'a[b').Error | Should -Match 'Unmatched \['
            (ConvertTo-GnuDotNetRegex -Pattern '[[:alpha:').Error | Should -Match 'Unmatched \['
            (ConvertTo-GnuDotNetRegex -Pattern 'a\').Error | Should -Be 'Trailing backslash'
            (ConvertTo-GnuDotNetRegex -Pattern '[[:bogus:]]').Error | Should -Be 'Invalid character class name'

            Get-GnuParenthesisBalance -Regex '(a[(]\(' | Should -Be 'open'
            Get-GnuParenthesisBalance -Regex 'a)' | Should -Be 'close'
            Get-GnuParenthesisBalance -Regex '[^]()](x)' | Should -Be 'ok'
        }
    }
}
