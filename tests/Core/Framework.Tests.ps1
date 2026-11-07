BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'Registry' {
    It 'rejects specs without required keys' {
        { InModuleScope PSGnuUtils { Register-GnuUtil @{ Name = 'broken' } } } | Should -Throw "*missing 'Category'*"
    }

    It 'normalizes specs with defaults and a function name' {
        InModuleScope PSGnuUtils {
            $spec = Get-GnuUtilSpec -Name 'head'
            $spec.FunctionName | Should -Be 'Invoke-GnuHead'
            $spec.UsageExitCode | Should -Be 1
            $spec.RawArguments | Should -BeFalse
        }
    }

    It 'builds PowerShell function names' {
        InModuleScope PSGnuUtils { Get-GnuFunctionName -Name 'sha256sum' } | Should -Be 'Invoke-GnuSha256sum'
    }

    It 'resolves wildcards and exclusions' {
        $names = InModuleScope PSGnuUtils { @(Resolve-GnuUtilName -Name 'sha*sum' -Exclude 'sha1sum') }
        $names | Should -Contain 'sha256sum'
        $names | Should -Not -Contain 'sha1sum'
        $names | Should -Not -Contain 'md5sum'
    }

    It 'reports unknown literal names' {
        $errors = InModuleScope PSGnuUtils { Resolve-GnuUtilName -Name 'no-such-util' 2>&1 }
        "$errors" | Should -Match "there is no util named 'no-such-util'"
    }
}

Describe 'Help and version output' {
    It 'prints GNU style usage and option lines' {
        $r = Invoke-TestGnu head '--help'
        $r.ExitCode | Should -Be 0
        $r.Output[0] | Should -BeExactly 'Usage: head [OPTION]... [FILE]...'
        $r.Text | Should -Match '  -n, --lines=\[-\]NUM'
        $r.Text | Should -Match '      --help'
        $r.Text | Should -Match 'Get-Help Invoke-GnuHead -Full'
    }

    It 'prints alternative usage lines with "or:"' {
        (Invoke-TestGnu basename '--help').Output[1] | Should -BeExactly '  or:  basename OPTION... NAME...'
    }

    It 'prints the version' {
        $r = Invoke-TestGnu head '--version'
        $r.Output[0] | Should -Match '^head \(PSGnuUtils\) \d+\.\d+\.\d+'
        $r.ExitCode | Should -Be 0
    }

    It 'wraps long option names onto their own line' {
        $line = InModuleScope PSGnuUtils { @(Format-GnuOptionHelp -Option (ConvertTo-GnuOptionDefinition @{ Long = 'a-very-long-option-name'; Arg = 'VALUE'; Help = 'text' })) }
        $line.Count | Should -Be 2
        $line[1].Trim() | Should -Be 'text'
    }
}

Describe 'Usage errors' {
    It 'writes the getopt message plus a hint and exits with 1' {
        $r = Invoke-TestGnu head '-x'
        $r.ExitCode | Should -Be 1
        $r.ErrorText | Should -Match "head: invalid option -- 'x'"
        $r.ErrorText | Should -Match "Try 'head --help' for more information."
        $r.Output.Count | Should -Be 0
    }

    It 'can be suppressed with 2>$null' {
        { Invoke-GnuHead -x 2>$null } | Should -Not -Throw
    }
}

Describe 'Output helpers' {
    It 'splits text into lines without a trailing empty line' {
        InModuleScope PSGnuUtils {
            @(ConvertTo-GnuOutputLine -Text "a`nb`n") | Should -Be @('a', 'b')
            @(ConvertTo-GnuOutputLine -Text "a`r`nb") | Should -Be @('a', 'b')
            @(ConvertTo-GnuOutputLine -Text "`n").Count | Should -Be 1
            @(ConvertTo-GnuOutputLine -Text '').Count | Should -Be 0
        }
    }

    It 'emits NUL-terminated records as one string' {
        InModuleScope PSGnuUtils {
            ConvertTo-GnuRecordOutput -Record @('a', 'b') -Zero | Should -BeExactly "a`0b`0"
            @(ConvertTo-GnuRecordOutput -Record @('a', 'b')) | Should -Be @('a', 'b')
            @(ConvertTo-GnuRecordOutput -Record @() -Zero).Count | Should -Be 0
        }
    }

    It 'splits records on a separator' {
        InModuleScope PSGnuUtils {
            @(Split-GnuRecord -Text "a`0b`0" -Separator "`0") | Should -Be @('a', 'b')
            @(Split-GnuRecord -Text "a`0b" -Separator "`0") | Should -Be @('a', 'b')
            @(Split-GnuRecord -Text '').Count | Should -Be 0
        }
    }
}

Describe 'Pipeline input' {
    It 'splits multi-line strings and converts values with invariant culture' {
        $r = Invoke-TestGnu cat -InputObject "a`nb", 1.5, $true
        $r.Output | Should -Be @('a', 'b', '1.5', 'True')
    }

    It 'passes empty strings through as empty lines' {
        (Invoke-TestGnu cat -InputObject 'a', '', 'b').Output | Should -Be @('a', '', 'b')
    }

    It 'uses the full path of file system objects' {
        $file = New-TestFile -Path (Join-Path $TestDrive 'item.txt') -Content 'x'
        (Invoke-TestGnu cat -InputObject (Get-Item -LiteralPath $file)).Output | Should -Be @((Get-Item -LiteralPath $file).FullName)
    }

    It 'renders other objects like the console, with one table header' {
        $objects = @([pscustomobject]@{ Name = 'alpha'; Size = 1 }, [pscustomobject]@{ Name = 'beta'; Size = 2 })
        $r = Invoke-TestGnu cat -InputObject $objects
        $r.Output[0] | Should -Match '^Name\s+Size$'
        @($r.Output | Where-Object { $_ -match '^Name' }).Count | Should -Be 1
        $r.Text | Should -Match 'alpha'
        $r.Text | Should -Match 'beta'
        $r.Output[-1] | Should -Not -BeNullOrEmpty
    }
}

Describe 'File input' {
    It 'reads UTF-8 and UTF-16 (BOM) files' {
        $utf8 = New-TestFile -Path (Join-Path $TestDrive 'utf8.txt') -Content ("caf" + [char]0xE9 + "`n")
        $utf16 = Join-Path $TestDrive 'utf16.txt'
        [System.IO.File]::WriteAllText($utf16, "wide`n", [System.Text.Encoding]::Unicode)
        (Invoke-TestGnu cat $utf8).Output | Should -Be @("caf" + [char]0xE9)
        (Invoke-TestGnu cat $utf16).Output | Should -Be @('wide')
    }

    It 'resolves relative paths against the PowerShell location' {
        $null = New-TestFile -Path (Join-Path $TestDrive 'rel/inner.txt') -Content "inside`n"
        (Invoke-TestGnu cat 'inner.txt' -WorkingDirectory (Join-Path $TestDrive 'rel')).Output | Should -Be @('inside')
    }

    It 'reports directories and missing files' {
        $r = Invoke-TestGnu cat $TestDrive
        $r.ErrorText | Should -Match 'Is a directory'
        $r.ExitCode | Should -Be 1
        (Invoke-TestGnu cat '').ErrorText | Should -Match 'No such file or directory'
    }

    It 'reads standard input only once' {
        (Invoke-TestGnu cat '-', '-' -InputObject 'once').Output | Should -Be @('once')
    }
}

Describe 'Wildcard expansion' {
    BeforeAll {
        $script:globDir = Join-Path $TestDrive 'glob'
        $null = New-TestFile -Path (Join-Path $globDir 'b.txt') -Content "B`n"
        $null = New-TestFile -Path (Join-Path $globDir 'a.txt') -Content "A`n"
        $null = New-TestFile -Path (Join-Path $globDir 'c.log') -Content "C`n"
        $null = New-TestFile -Path (Join-Path $globDir '.hidden.txt') -Content "H`n"
        $null = New-TestFile -Path (Join-Path $globDir 'lit[1].txt') -Content "L`n"
    }

    It 'expands patterns in sorted order and skips hidden files' {
        (Invoke-TestGnu cat '*.txt' -WorkingDirectory $globDir).Output | Should -Be @('A', 'B', 'L')
    }

    It 'matches hidden files when the pattern starts with a dot' {
        (Invoke-TestGnu cat '.*.txt' -WorkingDirectory $globDir).Output | Should -Be @('H')
    }

    It 'keeps the directory part as typed' {
        $r = Invoke-TestGnu head '-n', '1', 'glob/*.log' -WorkingDirectory $TestDrive
        $r.Output | Should -Be @('C')
        (Invoke-TestGnu head '-n', '1', 'glob/a*', 'glob/b*' -WorkingDirectory $TestDrive).Output[0] | Should -BeExactly '==> glob/a.txt <=='
    }

    It 'uses existing literal names with wildcard characters as is' {
        (Invoke-TestGnu cat 'lit[1].txt' -WorkingDirectory $globDir).Output | Should -Be @('L')
    }

    It 'keeps patterns without matches (like bash)' {
        (Invoke-TestGnu cat '*.none' -WorkingDirectory $globDir).ErrorText | Should -Match "\*\.none: No such file or directory"
    }

    It 'expands wildcards in directory components' {
        (Invoke-TestGnu cat 'gl*/c.log' -WorkingDirectory $TestDrive).Output | Should -Be @('C')
    }
}

Describe 'Path helpers' {
    It 'computes basenames' {
        InModuleScope PSGnuUtils {
            Get-GnuBaseName -Path '/usr/bin/sort' | Should -Be 'sort'
            Get-GnuBaseName -Path 'dir/' | Should -Be 'dir'
            Get-GnuBaseName -Path '/' | Should -Be '/'
            Get-GnuBaseName -Path '' | Should -Be ''
            Get-GnuBaseName -Path 'file.txt' -Suffix '.txt' | Should -Be 'file'
            Get-GnuBaseName -Path '.txt' -Suffix '.txt' | Should -Be '.txt'
        }
    }

    It 'computes dirnames' {
        InModuleScope PSGnuUtils {
            Get-GnuDirName -Path '/usr/bin/' | Should -Be '/usr'
            Get-GnuDirName -Path 'stdio.h' | Should -Be '.'
            Get-GnuDirName -Path '/usr' | Should -Be '/'
            Get-GnuDirName -Path '//' | Should -Be '/'
            Get-GnuDirName -Path 'a//b//' | Should -Be 'a'
            Get-GnuDirName -Path '' | Should -Be '.'
        }
    }

    It 'returns path prefixes' {
        InModuleScope PSGnuUtils {
            @(Get-GnuPathPrefix -Path 'a/b/c/') | Should -Be @('a', 'a/b', 'a/b/c')
            @(Get-GnuPathPrefix -Path '/x/y') | Should -Be @('/x', '/x/y')
            @(Get-GnuPathPrefix -Path '/') | Should -Be @('/')
        }
    }

    It 'resolves physical paths through symbolic links' {
        $real = Join-Path $TestDrive 'real'
        $null = New-Item -ItemType Directory -Path (Join-Path $real 'child') -Force
        $link = Join-Path $TestDrive 'link'
        if (-not (New-TestDirectoryLink -Path $link -Target $real)) { Set-ItResult -Skipped -Because 'directory links cannot be created here' }
        $resolved = InModuleScope PSGnuUtils -Parameters @{ P = (Join-Path $link 'child') } { param($P) Resolve-GnuPhysicalPath -Path $P }
        $resolved | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $real 'child')))
    }

    It 'falls back to combining with the current location for unparsable PowerShell paths' {
        $result = InModuleScope PSGnuUtils { Resolve-GnuPath -Path 'zz-no-drive:file' }
        [System.IO.Path]::IsPathRooted($result) | Should -BeTrue
    }
}

Describe 'Platform helpers' {
    It 'detects the platform' {
        $platform = InModuleScope PSGnuUtils { Get-GnuPlatform }
        $platform | Should -BeIn @('Windows', 'Linux', 'MacOS', 'Unix')
        (InModuleScope PSGnuUtils { Test-GnuWindows }) | Should -Be (Test-IsWindowsPlatform)
    }

    It 'reports a machine name and OS info' {
        InModuleScope PSGnuUtils {
            Get-GnuMachineName | Should -Not -BeNullOrEmpty
            $info = Get-GnuOsInfo
            $info.KernelName | Should -Not -BeNullOrEmpty
            $info.NodeName | Should -Be ([System.Net.Dns]::GetHostName())
        }
    }

    It 'does not apply Unix modes on Windows' {
        if (-not (Test-IsWindowsPlatform)) { Set-ItResult -Skipped -Because 'Windows only' }
        InModuleScope PSGnuUtils { Set-GnuUnixMode -Path 'C:\nothing' -Mode 448 } | Should -BeFalse
    }

    It 'maps .NET exceptions to GNU reasons' {
        InModuleScope PSGnuUtils {
            Get-GnuErrorReason -Exception (New-Object System.IO.FileNotFoundException 'x') | Should -Be 'No such file or directory'
            Get-GnuErrorReason -Exception (New-Object System.UnauthorizedAccessException 'x') | Should -Be 'Permission denied'
            Get-GnuErrorReason -Exception (New-Object System.Exception 'other') | Should -Be 'other'
        }
    }
}
