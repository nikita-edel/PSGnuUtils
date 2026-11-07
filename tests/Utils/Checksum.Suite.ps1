# Shared Pester suite for md5sum, sha1sum, sha256sum, sha384sum and sha512sum.
# Each <util>.Tests.ps1 dot-sources this file and calls Invoke-ChecksumSuite at discovery time.
# The meta tests (tests/Module.Tests.ps1) count the options covered here for every *sum util.
#
# Options covered: -b --binary -c --check --tag -t --text -z --zero --ignore-missing --quiet
#                  --status --strict -w --warn

function Invoke-ChecksumSuite {
    param(
        [Parameter(Mandatory)][string]$Util,
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$AbcHash,
        [Parameter(Mandatory)][string]$EmptyHash,
        [Parameter(Mandatory)][scriptblock]$Factory
    )

    Describe $Util -ForEach @(@{ Util = $Util; Tag = $Tag; AbcHash = $AbcHash; EmptyHash = $EmptyHash; Factory = $Factory }) {
        BeforeAll {
            $script:dir = Join-Path $TestDrive 'sums'
            $null = New-Item -ItemType Directory -Path $dir -Force
            $null = New-TestFile -Path (Join-Path $dir 'abc.txt') -Content 'abc'
            $null = New-TestFile -Path (Join-Path $dir 'empty.txt') -Content ''
            $hasher = & $Factory
            $script:helloHash = [System.BitConverter]::ToString($hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("hello`n"))).Replace('-', '').ToLowerInvariant()
            $hasher.Dispose()
        }

        It 'prints "DIGEST  NAME" for every file' {
            $r = Invoke-TestGnu $Util 'abc.txt', 'empty.txt' -WorkingDirectory $dir
            $r.Output | Should -Be @("$AbcHash  abc.txt", "$EmptyHash  empty.txt")
            $r.ExitCode | Should -Be 0
        }

        It 'hashes pipeline input as UTF-8 lines with LF' {
            (Invoke-TestGnu $Util -InputObject 'hello').Output | Should -Be @("$helloHash  -")
        }

        It 'marks binary mode with -b / --binary and text mode with -t / --text' {
            (Invoke-TestGnu $Util '-b', 'abc.txt' -WorkingDirectory $dir).Output | Should -Be @("$AbcHash *abc.txt")
            (Invoke-TestGnu $Util '--binary', 'abc.txt' -WorkingDirectory $dir).Output | Should -Be @("$AbcHash *abc.txt")
            (Invoke-TestGnu $Util '-b', '-t', 'abc.txt' -WorkingDirectory $dir).Output | Should -Be @("$AbcHash  abc.txt")
            (Invoke-TestGnu $Util '--text', 'abc.txt' -WorkingDirectory $dir).Output | Should -Be @("$AbcHash  abc.txt")
        }

        It 'prints the BSD format with --tag' {
            (Invoke-TestGnu $Util '--tag', 'abc.txt' -WorkingDirectory $dir).Output | Should -Be @("$Tag (abc.txt) = $AbcHash")
        }

        It 'ends lines with NUL with -z / --zero' {
            (Invoke-TestGnu $Util '-z', 'abc.txt', 'empty.txt' -WorkingDirectory $dir).Output | Should -Be @("$AbcHash  abc.txt`0$EmptyHash  empty.txt`0")
            (Invoke-TestGnu $Util '--zero', 'abc.txt' -WorkingDirectory $dir).Output | Should -Be @("$AbcHash  abc.txt`0")
        }

        It 'expands wildcards' {
            (Invoke-TestGnu $Util '*.txt' -WorkingDirectory $dir).Output | Should -Be @("$AbcHash  abc.txt", "$EmptyHash  empty.txt")
        }

        It 'escapes names that contain a backslash' {
            if (Test-IsWindowsPlatform) {
                $null = New-TestFile -Path (Join-Path $dir 'sub/abc.txt') -Content 'abc'
            }
            else {
                $null = New-TestFile -Path (Join-Path $dir 'sub\abc.txt') -Content 'abc'
            }
            (Invoke-TestGnu $Util 'sub\abc.txt' -WorkingDirectory $dir).Output | Should -Be @("\$AbcHash  sub\\abc.txt")
        }

        Context 'checking with -c / --check' {
            BeforeAll {
                $null = New-TestFile -Path (Join-Path $dir 'good.sums') -Content "$AbcHash  abc.txt`n$EmptyHash *empty.txt`n"
                $null = New-TestFile -Path (Join-Path $dir 'tag.sums') -Content "$Tag (abc.txt) = $AbcHash`n"
                $bad = $AbcHash.Substring(0, $AbcHash.Length - 1) + '0'
                if ($bad -eq $AbcHash) { $bad = $AbcHash.Substring(0, $AbcHash.Length - 1) + '1' }
                $null = New-TestFile -Path (Join-Path $dir 'bad.sums') -Content "$bad  abc.txt`n$EmptyHash  empty.txt`n"
                $null = New-TestFile -Path (Join-Path $dir 'missing.sums') -Content "$AbcHash  gone.txt`n$EmptyHash  empty.txt`n"
                $null = New-TestFile -Path (Join-Path $dir 'onlymissing.sums') -Content "$AbcHash  gone.txt`n"
                $null = New-TestFile -Path (Join-Path $dir 'messy.sums') -Content "$AbcHash  abc.txt`nnot a checksum line`n"
                $null = New-TestFile -Path (Join-Path $dir 'garbage.sums') -Content "nothing useful`n"
            }

            It 'reports OK for matching files' {
                $r = Invoke-TestGnu $Util '-c', 'good.sums' -WorkingDirectory $dir
                $r.Output | Should -Be @('abc.txt: OK', 'empty.txt: OK')
                $r.ExitCode | Should -Be 0
                (Invoke-TestGnu $Util '--check', 'tag.sums' -WorkingDirectory $dir).Output | Should -Be @('abc.txt: OK')
            }

            It 'reads the checksum list from pipeline input' {
                (Invoke-TestGnu $Util '-c' -InputObject "$AbcHash  abc.txt" -WorkingDirectory $dir).Output | Should -Be @('abc.txt: OK')
            }

            It 'reports mismatches with a warning and exit code 1' {
                $r = Invoke-TestGnu $Util '-c', 'bad.sums' -WorkingDirectory $dir
                $r.Output | Should -Be @('abc.txt: FAILED', 'empty.txt: OK')
                $r.WarningText | Should -Match '1 computed checksum did NOT match'
                $r.ExitCode | Should -Be 1
            }

            It 'hides OK lines with --quiet' {
                (Invoke-TestGnu $Util '-c', '--quiet', 'good.sums' -WorkingDirectory $dir).Output.Count | Should -Be 0
                (Invoke-TestGnu $Util '-c', '--quiet', 'bad.sums' -WorkingDirectory $dir).Output | Should -Be @('abc.txt: FAILED')
            }

            It 'prints nothing with --status and reports through the exit code' {
                $r = Invoke-TestGnu $Util '-c', '--status', 'bad.sums' -WorkingDirectory $dir
                $r.Output.Count | Should -Be 0
                $r.Warnings.Count | Should -Be 0
                $r.ExitCode | Should -Be 1
                (Invoke-TestGnu $Util '-c', '--status', 'good.sums' -WorkingDirectory $dir).ExitCode | Should -Be 0
            }

            It 'reports unreadable files' {
                $r = Invoke-TestGnu $Util '-c', 'missing.sums' -WorkingDirectory $dir
                $r.Output | Should -Be @('gone.txt: FAILED open or read', 'empty.txt: OK')
                $r.ErrorText | Should -Match 'gone.txt: No such file or directory'
                $r.WarningText | Should -Match '1 listed file could not be read'
                $r.ExitCode | Should -Be 1
            }

            It 'skips missing files with --ignore-missing' {
                $r = Invoke-TestGnu $Util '-c', '--ignore-missing', 'missing.sums' -WorkingDirectory $dir
                $r.Output | Should -Be @('empty.txt: OK')
                $r.ExitCode | Should -Be 0
                $r = Invoke-TestGnu $Util '-c', '--ignore-missing', 'onlymissing.sums' -WorkingDirectory $dir
                $r.ErrorText | Should -Match 'onlymissing.sums: no file was verified'
                $r.ExitCode | Should -Be 1
            }

            It 'counts improperly formatted lines, warns per line with -w / --warn' {
                $r = Invoke-TestGnu $Util '-c', 'messy.sums' -WorkingDirectory $dir
                $r.Output | Should -Be @('abc.txt: OK')
                $r.WarningText | Should -Match '1 line is improperly formatted'
                $r.ExitCode | Should -Be 0
                (Invoke-TestGnu $Util '-c', '-w', 'messy.sums' -WorkingDirectory $dir).WarningText | Should -Match "messy.sums: 2: improperly formatted $Tag checksum line"
                (Invoke-TestGnu $Util '-c', '--warn', 'messy.sums' -WorkingDirectory $dir).WarningText | Should -Match 'improperly formatted'
            }

            It 'fails on improperly formatted lines with --strict' {
                (Invoke-TestGnu $Util '-c', '--strict', 'messy.sums' -WorkingDirectory $dir).ExitCode | Should -Be 1
            }

            It 'fails when no line is properly formatted' {
                $r = Invoke-TestGnu $Util '-c', 'garbage.sums' -WorkingDirectory $dir
                $r.ErrorText | Should -Match 'garbage.sums: no properly formatted checksum lines found'
                $r.ExitCode | Should -Be 1
            }

            It 'reports a missing checksum list' {
                (Invoke-TestGnu $Util '-c', 'no-such.sums' -WorkingDirectory $dir).ErrorText | Should -Match 'no-such.sums: No such file or directory'
            }
        }

        It 'rejects check-only options without --check and --tag with --check' {
            foreach ($option in @('--quiet', '--status', '--strict', '--warn', '--ignore-missing')) {
                $r = Invoke-TestGnu $Util $option, 'abc.txt' -WorkingDirectory $dir
                $r.ExitCode | Should -Be 1
                $r.ErrorText | Should -Match 'meaningful only when verifying checksums'
            }
            (Invoke-TestGnu $Util '-c', '--tag', 'x' -WorkingDirectory $dir).ErrorText | Should -Match 'meaningless when verifying checksums'
        }

        It 'reports missing files and continues' {
            $r = Invoke-TestGnu $Util 'missing.txt', 'abc.txt' -WorkingDirectory $dir
            $r.Output | Should -Be @("$AbcHash  abc.txt")
            $r.ErrorText | Should -BeExactly "$($Util): missing.txt: No such file or directory"
            $r.ExitCode | Should -Be 1
        }
    }
}
