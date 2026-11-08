BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')

    function Invoke-TestXargs {
        # xargs with the input lines, the statistics of -t captured from the information stream.
        param([object[]]$Arguments, [string[]]$InputObject = @(), [switch]$NoInput)
        Push-Location -LiteralPath $dir
        try {
            $global:LASTEXITCODE = -1
            if ($NoInput) { $records = @(Invoke-GnuXargs @Arguments 6>&1 2>&1 3>&1) }
            else { $records = @($InputObject | Invoke-GnuXargs @Arguments 6>&1 2>&1 3>&1) }
            $code = $global:LASTEXITCODE
        }
        finally { Pop-Location }
        [pscustomobject]@{
            Output   = @($records | Where-Object { $_ -is [string] })
            Info     = @($records | Where-Object { $_ -is [System.Management.Automation.InformationRecord] } | ForEach-Object { [string]$_.MessageData })
            Errors   = @($records | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { $_.Exception.Message })
            Warnings = @($records | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $_.Message })
            ExitCode = $code
        }
    }
}

# Expected results were compared with GNU findutils xargs 4.10 and 4.11 (see docs/DEVLOG.md).
Describe 'xargs' {
    BeforeEach {
        $script:dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $null = New-Item -ItemType Directory -Path $dir
        $null = New-TestFile -Path (Join-Path $dir 'af') -Content "p`nq`n"
        $null = New-TestFile -Path (Join-Path $dir 'zero') -Bytes ([byte[]](97, 0, 98, 32, 99, 0))
    }

    It 'runs echo with all items by default' {
        $r = Invoke-TestXargs @() -InputObject 'a b', 'c'
        $r.Output | Should -Be @('a b c')
        $r.ExitCode | Should -Be 0
        (Invoke-TestXargs @('echo', 'X') -InputObject 'a').Output | Should -Be @('X a')
    }

    It 'groups with -n / --max-args' {
        (Invoke-TestXargs @('-n', '2', 'echo') -InputObject 'a b c d e').Output | Should -Be @('a b', 'c d', 'e')
        (Invoke-TestXargs @('--max-args=3', 'echo') -InputObject 'a b c d e').Output | Should -Be @('a b c', 'd e')
    }

    It 'groups lines with -L, -l and --max-lines' {
        $lines = @('one', 'two', 'three')
        (Invoke-TestXargs @('-L', '2', 'echo') -InputObject $lines).Output | Should -Be @('one two', 'three')
        (Invoke-TestXargs @('-l', 'echo') -InputObject $lines).Output | Should -Be @('one', 'two', 'three')
        (Invoke-TestXargs @('--max-lines', 'echo') -InputObject $lines).Output | Should -Be @('one', 'two', 'three')
        (Invoke-TestXargs @('--max-lines=3', 'echo') -InputObject $lines).Output | Should -Be @('one two three')
        (Invoke-TestXargs @('-L', '1', 'echo') -InputObject 'a b ', 'c', 'd e').Output | Should -Be @('a b c', 'd e') -Because 'a line ending in a blank continues'
    }

    It 'warns when -n and -L are both given and keeps the last' {
        $r = Invoke-TestXargs @('-L', '1', '-n', '2', 'echo') -InputObject 'a b c', 'd'
        $r.Warnings | Should -Be @('xargs: warning: options --max-lines and --max-args/-n are mutually exclusive, ignoring previous --max-lines value')
        $r.Output | Should -Be @('a b', 'c d')
        $r = Invoke-TestXargs @('-n', '2', '-L', '1', 'echo') -InputObject 'a b c', 'd'
        $r.Warnings | Should -Be @('xargs: warning: options --max-args and -L are mutually exclusive, ignoring previous --max-args value')
        $r.Output | Should -Be @('a b c', 'd')
    }

    It 'lets the last of -n, -L, -l and -I win' -ForEach @(
        @{ Options = @('-I', 'X', '-n', '2'); Warning = 'options --replace and --max-args/-n are mutually exclusive, ignoring previous --replace value' }
        @{ Options = @('-n', '2', '-I', 'X'); Warning = 'options --max-args and --replace/-I/-i are mutually exclusive, ignoring previous --max-args value' }
        @{ Options = @('-L', '1', '-I', 'X'); Warning = 'options --max-lines and --replace/-I/-i are mutually exclusive, ignoring previous --max-lines value' }
        @{ Options = @('-I', 'X', '-L', '1'); Warning = 'options --replace and -L are mutually exclusive, ignoring previous --replace value' }
        @{ Options = @('-I', 'X', '-l'); Warning = 'options --replace and --max-lines/-l are mutually exclusive, ignoring previous --replace value' }
        @{ Options = @('-n', '2', '-l'); Warning = 'options --max-args and --max-lines/-l are mutually exclusive, ignoring previous --max-args value' }
    ) {
        (Invoke-TestXargs (@($Options) + 'echo') -InputObject 'a').Warnings | Should -Be @("xargs: warning: $Warning")
    }

    It 'keeps -I when -n 1 follows it' {
        $r = Invoke-TestXargs @('-I', 'X', '-n', '1', 'echo', '[X]') -InputObject 'a b', 'c'
        $r.Warnings | Should -BeNullOrEmpty
        $r.Output | Should -Be @('[a b]', '[c]')
    }

    It 'replaces with -I, -i and --replace' {
        (Invoke-TestXargs @('-I', '{}', 'echo', '[{}]') -InputObject ' lead  mid', 'x  y ').Output | Should -Be @('[lead  mid]', '[x  y ]')
        (Invoke-TestXargs @('-I', 'X', 'echo', 'X', 'aXb') -InputObject 'one').Output | Should -Be @('one aoneb')
        (Invoke-TestXargs @('-i', 'echo', '<{}>') -InputObject 'one').Output | Should -Be @('<one>')
        (Invoke-TestXargs @('--replace', 'echo', '<{}>') -InputObject 'one').Output | Should -Be @('<one>')
        (Invoke-TestXargs @('--replace=R', 'echo', '<R>') -InputObject 'one').Output | Should -Be @('<one>')
        (Invoke-TestXargs @('-I', {}, 'echo', {}) -InputObject 'one').Output | Should -Be @('one') -Because 'an unquoted {} works'
        (Invoke-TestXargs @('-I', 'X', 'echo', 'X') -InputObject @()).Output | Should -BeNullOrEmpty
        $r = Invoke-TestXargs @('-I', '', 'echo', 'X') -InputObject 'a'
        $r.Errors | Should -Be @('xargs: command too long')
        $r.ExitCode | Should -Be 1
    }

    It 'handles quotes and backslashes like GNU' {
        (Invoke-TestXargs @('-n', '1', 'echo') -InputObject "'a b' `"c d`" e\ f g").Output | Should -Be @('a b', 'c d', 'e f', 'g')
        (Invoke-TestXargs @('-n', '1', 'echo') -InputObject "'' x").Output | Should -Be @('', 'x')
        $r = Invoke-TestXargs @('echo') -InputObject "it's"
        $r.Errors | Should -Be @('xargs: unmatched single quote; by default quotes are special to xargs unless you use the -0 option')
        $r.ExitCode | Should -Be 1
        (Invoke-TestXargs @('echo') -InputObject 'a"b').Errors | Should -Be @('xargs: unmatched double quote; by default quotes are special to xargs unless you use the -0 option')
    }

    It 'stops at the end-of-file string with -E, -e and --eof' {
        (Invoke-TestXargs @('-E', 'END', 'echo') -InputObject 'a b END c', 'd').Output | Should -Be @('a b')
        (Invoke-TestXargs @('-eEND', 'echo') -InputObject 'a END c').Output | Should -Be @('a')
        (Invoke-TestXargs @('--eof=END', 'echo') -InputObject 'a END c').Output | Should -Be @('a')
        (Invoke-TestXargs @('-e', 'echo') -InputObject 'a END c').Output | Should -Be @('a END c') -Because 'without a value there is no end-of-file string'
        (Invoke-TestXargs @('--eof', 'echo') -InputObject 'a END c').Output | Should -Be @('a END c')
        (Invoke-TestXargs @('-E', 'END', 'echo') -InputObject 'a END', 'b').Output | Should -Be @('a') -Because 'the string can end a line'
    }

    It 'splits on NUL with -0 / --null and on a character with -d / --delimiter' {
        (Invoke-TestXargs @('-0', '-n', '1', '-a', 'zero', 'echo') -NoInput).Output | Should -Be @('a', 'b c')
        (Invoke-TestXargs @('--null', '-a', 'zero', 'echo') -NoInput).Output | Should -Be @('a b c')
        (Invoke-TestXargs @('-d', ':', '-n', '1', 'echo') -InputObject 'a:b c:d').Output | Should -Be @('a', 'b c', 'd')
        (Invoke-TestXargs @('--delimiter=\x3a', '-n', '1', 'echo') -InputObject 'a:b').Output | Should -Be @('a', 'b')
        (Invoke-TestXargs @('-d', '\072', '-n', '1', 'echo') -InputObject 'a:b').Output | Should -Be @('a', 'b')
        (Invoke-TestXargs @('-d', '\n', 'echo') -InputObject "it's", 'b c').Output | Should -Be @("it's b c")
        (Invoke-TestXargs @('-d', '\t', '-n', '1', 'echo') -InputObject "a`tb").Output | Should -Be @('a', 'b')
        (Invoke-TestXargs @('-d', '\\', '-n', '1', 'echo') -InputObject 'a\b').Output | Should -Be @('a', 'b')
        $r = Invoke-TestXargs @('-0', '-E', 'z', 'echo') -InputObject 'a'
        $r.Warnings | Should -Be @("xargs: warning: the -E option has no effect if -0 or -d is used.`n")
        (Invoke-TestXargs @('-d', ':', '-0', '-n', '1', '-a', 'zero', 'echo') -NoInput).Output | Should -Be @('a', 'b c') -Because 'the last of -0 and -d wins'
        (Invoke-TestXargs @('-0', '-d', ':', '-n', '1', 'echo') -InputObject 'a:b').Output | Should -Be @('a', 'b')
        (Invoke-TestXargs @('-d', ':', '-n', '1', '-a', 'zero', 'echo') -NoInput).Output | Should -Be @('a') -Because 'an argument ends at a NUL'
        $r = Invoke-TestXargs @('-n', '1', '-a', 'zero', 'echo') -NoInput
        $r.Output | Should -Be @('a', 'c')
        $r.Warnings | Should -Be @('xargs: WARNING: a NUL character occurred in the input.  It cannot be passed through in the argument list.  Did you mean to use the --null option?')
    }

    It 'rejects bad delimiters' -ForEach @(@{ Text = 'ab' }, @{ Text = '' }) {
        (Invoke-TestXargs @('-d', $Text, 'echo') -InputObject 'a').Errors | Should -Be @("xargs: Invalid input delimiter specification $($Text): the delimiter must be either a single character or an escape sequence starting with \.")
    }

    It 'rejects bad delimiter escapes' -ForEach @(
        @{ Text = '\q'; Reason = '.' }
        @{ Text = '\N'; Reason = '.' }
        @{ Text = '\x41z'; Reason = '; trailing characters z not recognised.' }
        @{ Text = '\18'; Reason = '; trailing characters 8 not recognised.' }
        @{ Text = '\x100'; Reason = '; character values must not exceed ff.' }
        @{ Text = '\400'; Reason = '; character values must not exceed 377.' }
    ) {
        $r = Invoke-TestXargs @('-d', $Text, 'echo') -InputObject 'a'
        $r.Errors | Should -Be @("xargs: Invalid escape sequence $Text in input delimiter specification$Reason")
        $r.ExitCode | Should -Be 1
    }

    It 'reads items from a file with -a / --arg-file' {
        (Invoke-TestXargs @('-a', 'af', 'echo') -NoInput).Output | Should -Be @('p q')
        (Invoke-TestXargs @('--arg-file=af') -NoInput).Output | Should -Be @('p q')
        $null = New-TestFile -Path (Join-Path $dir 'open') -Content 'a b'
        (Invoke-TestXargs @('-a', 'open', 'echo') -NoInput).Output | Should -Be @('a b') -Because 'the last item needs no newline'
        $null = New-TestFile -Path (Join-Path $dir 'quote') -Content "x 'y"
        (Invoke-TestXargs @('-a', 'quote', 'echo') -NoInput).ExitCode | Should -Be 1
        $r = Invoke-TestXargs @('-a', 'nofile', 'echo') -NoInput
        $r.Errors | Should -Be @("xargs: Cannot open input file 'nofile': No such file or directory")
        $r.ExitCode | Should -Be 1
    }

    It 'runs once without input unless -r / --no-run-if-empty' {
        (Invoke-TestXargs @('echo', 'X') -InputObject @()).Output | Should -Be @('X')
        (Invoke-TestXargs @('-r', 'echo', 'X') -InputObject @()).Output | Should -BeNullOrEmpty
        (Invoke-TestXargs @('--no-run-if-empty', 'echo', 'X') -InputObject '', '').Output | Should -BeNullOrEmpty
    }

    It 'prints commands with -t / --verbose' {
        $r = Invoke-TestXargs @('-t', 'echo', 'X') -InputObject 'p'
        $r.Info | Should -Be @('echo X p')
        $r.Output | Should -Be @('X p')
        (Invoke-TestXargs @('--verbose', '-n1', 'echo') -InputObject 'p q').Info | Should -Be @('echo p', 'echo q')
    }

    It 'asks with -p / --interactive' {
        (Invoke-TestXargs @('-p', 'echo') -InputObject 'p').Output | Should -BeNullOrEmpty -Because 'standard input is empty, which means no'
        Mock -ModuleName PSGnuUtils Read-GnuConfirmation { $true }
        $r = Invoke-TestXargs @('--interactive', 'echo') -InputObject 'p'
        $r.Output | Should -Be @('p')
        $r.Info | Should -BeNullOrEmpty -Because 'the prompt already shows the command'
        Should -Invoke -CommandName Read-GnuConfirmation -ModuleName PSGnuUtils -ParameterFilter { $Question -eq 'echo p ?...' -and $Bare }
    }

    It 'limits the command line with -s / --max-chars and -x / --exit' {
        (Invoke-TestXargs @('-s', '20', 'echo') -InputObject 'aaaa bbbb cccc dddd').Output | Should -Be @('aaaa bbbb cccc', 'dddd')
        (Invoke-TestXargs @('--max-chars=15', 'echo') -InputObject 'aaaa bbbb cccc').Output | Should -Be @('aaaa bbbb', 'cccc')
        (Invoke-TestXargs @('-s', '1', 'echo') -InputObject 'a').Errors | Should -Be @('xargs: cannot fit single argument within argument list size limit')
        $r = Invoke-TestXargs @('-s', '0', 'echo') -InputObject 'a'
        $r.Warnings | Should -Be @('xargs: value 0 for -s option should be >= 1') -Because 'for -s this is not a usage error'
        $r.Errors | Should -Be @('xargs: cannot fit single argument within argument list size limit')
        (Invoke-TestXargs @('-s', '9', 'echo') -InputObject 'aaaa').Errors | Should -Be @('xargs: argument line too long')
        $r = Invoke-TestXargs @('-n', '2', '-s', '10', '-x', 'echo') -InputObject 'aaaa bbbb cccc'
        $r.Errors | Should -Be @('xargs: argument list too long')
        $r.ExitCode | Should -Be 1
        (Invoke-TestXargs @('-n', '2', '-s', '10', '--exit', 'echo') -InputObject 'aaaa bbbb cccc').ExitCode | Should -Be 1
    }

    It 'caps -s at the limit of Windows' {
        Mock -ModuleName PSGnuUtils Test-GnuWindows { $true }
        $r = Invoke-TestXargs @('-s', '40000', 'echo') -InputObject 'a'
        $r.Warnings | Should -Be @('xargs: warning: value 40000 for -s option is too large, using 32000 instead')
        $r.Output | Should -Be @('a')
    }

    It 'rejects bad numbers' -ForEach @(
        @{ Option = '-n'; Value = 'x'; Message = 'invalid number "x" for -n option' }
        @{ Option = '-n'; Value = '0'; Message = 'value 0 for -n option should be >= 1' }
        @{ Option = '-s'; Value = 'x'; Message = 'invalid number "x" for -s option' }
        @{ Option = '-L'; Value = 'x'; Message = 'invalid number "x" for -L option' }
        @{ Option = '-L'; Value = '0'; Message = 'value 0 for -L option should be >= 1' }
        @{ Option = '-P'; Value = 'x'; Message = 'invalid number "x" for -P option' }
        @{ Option = '-P'; Value = '-1'; Message = 'value -1 for -P option should be >= 0' }
        @{ Option = '-P'; Value = '-99999999999999999999'; Message = 'value -99999999999999999999 for -P option should be >= 0' }
        @{ Option = '-P'; Value = '2147483648'; Message = 'value 2147483648 for -P option should be <= 2147483647' }
        @{ Option = '-l0'; Value = $null; Message = 'value 0 for -l option should be >= 1' }
    ) {
        $r = Invoke-TestXargs (@($Option, $Value, 'echo') | Where-Object { $null -ne $_ }) -InputObject 'a'
        $r.Errors | Should -Be @("xargs: $Message`nTry 'xargs --help' for more information.")
        $r.ExitCode | Should -Be 1
    }

    It 'reports exit codes like GNU' {
        $r = Invoke-TestXargs @('nosuchcmd-psgnu') -InputObject 'a'
        $text = 'nosuchcmd-psgnu: No such file or directory'
        if (Test-IsWindowsPlatform) { $text = "failed to run command 'nosuchcmd-psgnu': No such file or directory" }
        $r.Errors | Should -Be @("xargs: $text")
        $r.ExitCode | Should -Be 127
        (Invoke-TestXargs @('false') -InputObject 'a').ExitCode | Should -Be 123
        (Invoke-TestXargs @('-n', '1', 'false') -InputObject 'a b').ExitCode | Should -Be 123
        $r = Invoke-TestXargs @('-n', '1', 'nosuchcmd-psgnu') -InputObject 'a b'
        $r.Errors.Count | Should -Be 1 -Because 'xargs stops at a command it cannot find'
        (Invoke-TestXargs @('-n', '99999999999999999999', 'echo') -InputObject 'a b').Output | Should -Be @('a b') -Because 'a huge count saturates'
    }

    It 'gives 126 for a command that cannot be started' {
        # Plain text: not a valid program on Windows, and without the execute permission on Unix.
        $null = New-TestFile -Path (Join-Path $dir 'bad.exe') -Content "text`n"
        $r = Invoke-TestXargs @('-n', '1', './bad.exe') -InputObject 'a b'
        $r.ExitCode | Should -Be 126
        $r.Errors.Count | Should -Be 1 -Because 'xargs stops after the first failure'
        $r.Errors[0] | Should -Match '^xargs: \./bad\.exe: '
        $r.Errors[0] | Should -Not -Match 'An error occurred|failed to run'
        if (-not (Test-IsWindowsPlatform)) { $r.Errors[0] | Should -Be 'xargs: ./bad.exe: Permission denied' }
    }

    It 'shortens the reason a program could not be started' {
        $file = Join-Path $dir 'af'
        InModuleScope PSGnuUtils -Parameters @{ File = $file } {
            param($File)
            Mock Test-GnuWindows { $false }
            $missing = New-Object System.Exception -ArgumentList 'No such file or directory'
            Get-GnuLaunchFailureReason -Exception $missing -Path $File | Should -Be 'Permission denied' -Because '.NET calls a file without the execute permission missing'
            Get-GnuLaunchFailureReason -Exception $missing -Path 'no-such-file-psgnu' | Should -Be 'No such file or directory'
            $wrapped = New-Object System.Exception -ArgumentList "An error occurred trying to start process '/a b' with working directory '/c'. Exec format error"
            Get-GnuLaunchFailureReason -Exception $wrapped -Path $File | Should -Be 'Exec format error'
        }
    }

    It 'gives 126 for a parallel program that cannot be started' {
        InModuleScope PSGnuUtils {
            Mock New-GnuProcessStartInfo { $info = New-Object System.Diagnostics.ProcessStartInfo; $info.FileName = 'no-such-program-psgnu'; $info.UseShellExecute = $false; $info }
            $state = @{ Context = @{ Name = 'xargs'; ExitCode = 0; ErrorCount = 0; Spec = @{} }; Stop = $false; MaxProcs = 2; SlotVar = ''; Running = New-Object 'System.Collections.Generic.List[hashtable]' }
            Start-GnuXargsProcess -State $state -Path 'no-such-program-psgnu' -Arguments @() -ErrorVariable problems -ErrorAction SilentlyContinue
            $state.Context.ExitCode | Should -Be 126
            $state.Stop | Should -BeTrue
            [string]$problems[-1] | Should -Match '^xargs: no-such-program-psgnu: '
        }
    }

    It 'maps 255, 126, 127 and signals' {
        InModuleScope PSGnuUtils {
            foreach ($row in @(@(255, 124, $true), @(126, 123, $false), @(127, 123, $false), @(1, 123, $false))) {
                $state = @{ Context = @{ Name = 'xargs'; ExitCode = 0; ErrorCount = 0; Spec = @{} }; Stop = $false }
                Set-GnuXargsResult -State $state -Name 'cmd' -Code $row[0] 2>$null
                $state.Context.ExitCode | Should -Be $row[1]
                $state.Stop | Should -Be $row[2]
            }
            Mock Test-GnuWindows { $false }
            $state = @{ Context = @{ Name = 'xargs'; ExitCode = 0; ErrorCount = 0; Spec = @{} }; Stop = $false }
            Set-GnuXargsResult -State $state -Name 'cmd' -Code 137 -ErrorVariable problems -ErrorAction SilentlyContinue
            $state.Context.ExitCode | Should -Be 125
            [string]$problems[0] | Should -Be 'xargs: cmd: terminated by signal 9'
            $state = @{ Context = @{ Name = 'xargs'; ExitCode = 0; ErrorCount = 0; Spec = @{} }; Stop = $false }
            Set-GnuXargsResult -State $state -Name 'cmd' -Code 200
            $state.Context.ExitCode | Should -Be 123 -Because 'no signal has that number'
        }
    }

    It 'runs PowerShell commands and utils of this module' {
        (Invoke-TestXargs @('Write-Output') -InputObject 'a b').Output | Should -Be @('a', 'b')
        (Invoke-TestXargs @('sed', '-s', '-n', '1p', 'af') -InputObject 'af').Output | Should -Be @('p', 'p')
        (Invoke-TestXargs @('echo', '-n', 'x') -InputObject 'a').Output | Should -Be @('x a') -Because 'echo is the util, not Write-Output'
    }

    It 'runs programs in parallel with -P / --max-procs and sets --process-slot-var' {
        # Small programs on purpose: starting several pwsh processes at once crashed one of them in a full Linux run.
        $echo = @('sh', '-c', 'echo "$0"')
        $slot = @('sh', '-c', 'echo "$SLOT"')
        $fail = @('sh', '-c', 'exit 3')
        if (Test-IsWindowsPlatform) {
            $echo = @('cmd.exe', '/c', 'echo')
            $slot = @('cmd.exe', '/c', 'echo', '%SLOT%')
            $fail = @('cmd.exe', '/c', 'exit', '3')
        }
        $r = Invoke-TestXargs (@('-P', '2', '-n', '1') + $echo) -InputObject 'a b c'
        @($r.Output | Sort-Object) | Should -Be @('a', 'b', 'c')
        $r.ExitCode | Should -Be 0
        $r = Invoke-TestXargs (@('--max-procs=0', '--process-slot-var=SLOT', '-n', '1') + $slot) -InputObject 'a b'
        @($r.Output | ForEach-Object { ($_ -split ' ')[0] } | Sort-Object) | Should -Be @('0', '1')
        $r = Invoke-TestXargs (@('-P', '2') + $fail) -InputObject 'a'
        $r.ExitCode | Should -Be 123
        (Invoke-TestXargs @('--process-slot-var=SLOT', 'Write-Output') -InputObject 'a').Output | Should -Be @('a')
    }

    It 'forwards the standard error of parallel programs' {
        InModuleScope PSGnuUtils {
            $finished = [pscustomobject]@{ HasExited = $true; ExitCode = 0 }
            Add-Member -InputObject $finished -MemberType ScriptMethod -Name WaitForExit -Value { }
            Add-Member -InputObject $finished -MemberType ScriptMethod -Name Dispose -Value { }
            $running = New-Object 'System.Collections.Generic.List[hashtable]'
            $running.Add(@{ Process = $finished; Name = 'p'; Slot = 0; Out = [System.Threading.Tasks.Task]::FromResult("out`n"); Err = [System.Threading.Tasks.Task]::FromResult("problem`n") })
            $state = @{ Context = @{ ExitCode = 0 }; Running = $running; Stop = $false }
            $saved = [System.Console]::Error
            $writer = New-Object System.IO.StringWriter
            [System.Console]::SetError($writer)
            try { $output = @(Wait-GnuXargsProcess -State $state -Below 1) }
            finally { [System.Console]::SetError($saved) }
            $output | Should -Be @('out')
            $writer.ToString() | Should -Be "problem`n"
            $state.Running.Count | Should -Be 0
        }
    }

    It 'understands every delimiter escape' {
        InModuleScope PSGnuUtils {
            foreach ($row in @(@('\a', 7), @('\b', 8), @('\f', 12), @('\n', 10), @('\r', 13), @('\t', 9), @('\v', 11), @('\x41', 65), @('\101', 65), @('\0', 0), @('\nX', 10), @('\x', 0), @(':', 58))) {
                [int](ConvertFrom-GnuXargsDelimiter -Text $row[0]).Char | Should -Be $row[1]
            }
        }
    }

    It 'takes options only before the command' {
        (Invoke-TestXargs @('echo', '-n', 'a') -InputObject 'b').Output | Should -Be @('a b')
        (Invoke-TestXargs @('--', 'echo', 'x') -InputObject 'b').Output | Should -Be @('x b')
    }
}
