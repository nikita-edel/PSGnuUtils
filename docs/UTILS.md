# Util status

Single source of truth for **what exists, what is planned and what is deliberately skipped**.
Update this file in the same commit that adds or changes a util (the meta tests check that every
implemented util is listed here).

**Status:** `done` (implemented and tested) · `planned` · `skip` (will not be ported; see reason)
**Scope:** `full` (all GNU options) · `subset` (only the commonly used part; see notes) · `-` for skipped utils
**Difficulty:** 1 (trivial) to 5 (very hard) to implement in PowerShell
**Batch:** implementation order, easiest first (see [PLAN.md](PLAN.md))

## File and directory operations

| Util | Status | Scope | Difficulty | Batch | Notes |
|---|---|---|---|---|---|
| `ls` | done | subset | 4 | 3 | `-a -A -l -h -R -t -S -U -r -1 -C -d -F -p -w --color`; columns only when writing to the console; no quoting; link counts 1, directory sizes 0. |
| `cp` | done | subset | 3 | 3 | `-r -R -p -a -d -f -i -n -u -v -l -s -L -P -T -t --preserve --no-preserve`; no backups or `--parents`. |
| `mv` | done | subset | 2 | 3 | `-f -i -n -u -v -T -t --strip-trailing-slashes`; no backups. |
| `rm` | done | full | 2 | 3 | Links and junctions are removed, never followed; drive roots are protected like `/`; read-only files are removed; piped `Get-ChildItem` objects are extra operands. |
| `rmdir` | done | full | 1 | 1 | |
| `mkdir` | done | full | 1 | 1 | Only octal `-m` modes; modes applied on Unix with PowerShell 7.3+, ignored on Windows; `-Z` accepted and ignored. |
| `ln` | done | full | 2 | 3 | Symbolic links need admin rights or developer mode on Windows; no backups (`-b`, `-S`). |
| `link` | done | full | 1 | 1 | |
| `unlink` | done | full | 1 | 1 | |
| `touch` | done | full | 2 | 2 | `-d` supports @SECONDS, now/today/yesterday/tomorrow, ISO dates and relative items ("2 days ago"), not all of GNU's grammar. |
| `install` | done | subset | 2 | 2 | `-c -C -d -D -m -p -t -T -v -o -g`; octal modes; modes and `-o/-g` only on Unix; no backups or `-s`. |
| `shred` | done | full | 2 | 2 | Random passes (no fixed patterns), `-n -s -u --remove -x -z -f -v --random-source`; not effective on SSDs / copy-on-write file systems. |
| `dd` | planned | subset | 3 | 3 | File copies with `bs count skip seek conv=notrunc`; no raw disk access (`\\.\PhysicalDrive`): needs admin and one bug wipes a disk. |
| `sync` | skip | - | - | - | Without FILE it must flush whole volumes, which needs administrator rights on Windows; flushing single files is rarely useful. |
| `truncate` | done | full | 1 | 1 | An IO block (`-o`) is 4096 bytes. |
| `mktemp` | done | full | 1 | 1 | |
| `dircolors` | done | full | 2 | 2 | GNU 8.32 database, output identical to GNU; PowerShell syntax when SHELL is not set. |
| `dir`, `vdir` | skip | - | - | - | Just `ls -C -b` / `ls -l -b`; aliases add no value. |
| `mkfifo` | skip | - | - | - | Windows has no file system FIFOs (named pipes live in `\\.\pipe\`). |
| `mknod` | skip | - | - | - | Windows has no device nodes or major/minor numbers. |

## Permissions and ownership

| Util | Status | Scope | Difficulty | Batch | Notes |
|---|---|---|---|---|---|
| `chmod` | skip | - | - | - | Unix permission bits do not map onto NTFS ACLs. |
| `chown`, `chgrp` | skip | - | - | - | Unix uid/gid ownership does not match the Windows SID/ACL model (use `icacls`). |
| `chcon`, `runcon` | skip | - | - | - | SELinux security contexts do not exist on Windows. |

## File info and disk usage

| Util | Status | Scope | Difficulty | Batch | Notes |
|---|---|---|---|---|---|
| `stat` | planned | subset | 3 | 3 | Default output plus `--format` fields that exist on Windows; inode/mode/uid fields only on Unix. |
| `df` | planned | subset | 2 | 3 | `-h -H -T -t -x --output`. |
| `du` | planned | subset | 2 | 3 | `-s -h -a -c -d --max-depth -x --apparent-size`. |
| `readlink` | done | full | 2 | 2 | Junctions count as links; a dangling link is canonicalized as a missing file. |
| `realpath` | done | full | 2 | 2 | `..` is always resolved before links, so `-L` = `-P`. |

## Viewing file contents

| Util | Status | Scope | Difficulty | Batch | Notes |
|---|---|---|---|---|---|
| `cat` | done | full | 1 | 1 | |
| `tac` | done | full | 1 | 1 | `-r` uses .NET regular expressions. |
| `nl` | done | full | 2 | 2 | `-b p` uses .NET regular expressions. |
| `od` | done | full | 3 | 3 | All `-t` types with sizes and `z`, traditional options, `-A -j -N -v -w --endian`; output identical to GNU 8.32; no `-S`. |
| `base64` | done | full | 1 | 1 | Decoded output is written as UTF-8 text lines. |
| `base32` | done | full | 1 | 1 | |
| `basenc` | done | full | 2 | 2 | All encodings incl. base16, base2msbf/lsbf, z85; base16 decoding accepts lower case (coreutils 9.x). |
| `head` | done | full | 1 | 1 | Cannot stop an endless producer (see ARCHITECTURE.md, "Stopping upstream"). |
| `tail` | done | full | 2 | 1 | `-f/-F/--follow=name/--pid/--retry/-s` poll the files; an unfinished last line is printed when the file stops growing. |
| `split` | planned | full | 3 | 3 | |
| `csplit` | planned | full | 3 | 3 | |
| `fmt` | planned | full | 3 | 3 | |
| `fold` | done | full | 2 | 2 | `-b` counts characters (UTF-16 code units), not UTF-8 bytes. |
| `pr` | skip | - | - | - | Dozens of pagination options for line printers; nobody prints with it anymore. |

## Text processing

| Util | Status | Scope | Difficulty | Batch | Notes |
|---|---|---|---|---|---|
| `sort` | done | subset | 3 | 3 | `-b -d -f -g -h -i -M -n -r -V -k -t -u -s -c -C -o -m -z --sort --files0-from`; ordinal comparison (like `LC_ALL=C`); no `-R`, `--parallel` or external merge. |
| `uniq` | done | full | 2 | 2 | |
| `cut` | done | full | 2 | 2 | `-c` counts characters (GNU treats `-c` like `-b`); `-b` counts UTF-8 bytes. |
| `paste` | done | full | 2 | 2 | |
| `join` | done | full | 3 | 3 | GNU's merge algorithm incl. order checks, `-a -v -e -o auto -i -t -1 -2 -j --header -z`; ordinal comparison; identical to GNU on 30 cases. |
| `comm` | done | full | 2 | 2 | Ordinal comparison (like `LC_ALL=C`), not locale collation. |
| `tr` | done | full | 3 | 2 | Ranges, classes (C locale), `[c*n]`, `[=c=]`, escapes, `-c -d -s -t`; reads only the pipeline/console. |
| `expand` | done | full | 2 | 2 | |
| `unexpand` | done | full | 2 | 2 | Exact port of GNU's pending-blank algorithm (verified against GNU). |
| `wc` | done | full | 1 | 1 | Word and width rules approximate GNU's locale handling (whitespace = `\s`, tabs to multiples of 8). |
| `tsort` | done | full | 2 | 2 | Port of the GNU algorithm: same order and loop reports as GNU. |
| `shuf` | done | full | 2 | 2 | `--random-source` seeds the generator (reproducible, not GNU's order); `-r -o` needs `-n`. |
| `numfmt` | done | full | 3 | 3 | All options (`--from/--to` si/iec/iec-i/auto, units, `--round`, `--format`, `--padding`, `--field`, `-d`, `--header`, `--invalid`, `-z`); identical to GNU on 91 cases; [decimal] instead of long double. |
| `ptx` | skip | - | - | - | Builds permuted indexes for books; essentially unused. |

## Checksums

| Util | Status | Scope | Difficulty | Batch | Notes |
|---|---|---|---|---|---|
| `md5sum` | done | full | 1 | 1 | |
| `sha1sum` | done | full | 1 | 1 | |
| `sha256sum` | done | full | 1 | 1 | |
| `sha384sum` | done | full | 1 | 1 | |
| `sha512sum` | done | full | 1 | 1 | |
| `sha224sum` | done | full | 3 | 2 | SHA-224 implemented in PowerShell (.NET has none). |
| `cksum` | done | full | 2 | 2 | POSIX CRC; `-a sysv/bsd/crc/md5/sha1/sha224/sha256/sha384/sha512`, `--untagged`, `-c`; no blake2b/sm3/`--base64`/`--raw`/`-l`. |
| `sum` | done | full | 2 | 2 | BSD and SysV checksums. |
| `b2sum` | skip | - | - | - | .NET has no BLAKE2; a hand-written crypto hash that is subtly wrong is worse than none. Use `sha256sum`. |

## Paths and names

| Util | Status | Scope | Difficulty | Batch | Notes |
|---|---|---|---|---|---|
| `basename` | done | full | 1 | 1 | On Windows `\` is a separator too. |
| `dirname` | done | full | 1 | 1 | On Windows `\` is a separator too; `C:\foo` gives `C:\`. |
| `pathchk` | done | full | 1 | 2 | Default limits: 255 bytes per component, 4096 per name. |
| `pwd` | done | full | 1 | 1 | Default is `-P` like coreutils (bash's builtin defaults to `-L`). |

## Shell helpers and logic

| Util | Status | Scope | Difficulty | Batch | Notes |
|---|---|---|---|---|---|
| `echo` | done | full | 1 | 1 | |
| `printf` | done | full | 3 | 2 | All conversions except `%a`; `%b`, `%q`, `*` widths, Unicode escapes; errors and exit codes as GNU. |
| `yes` | done | full | 1 | 1 | `yes \| head` never ends (see ARCHITECTURE.md); use `Select-Object -First`. |
| `true` | done | full | 1 | 1 | Sets `$LASTEXITCODE`; functions cannot set `$?`. |
| `false` | done | full | 1 | 1 | |
| `test` | done | full | 3 | 2 | GNU's posixtest grammar and messages; result in `$LASTEXITCODE`; Windows approximations for -x -O -G. |
| `expr` | done | full | 3 | 2 | BigInteger arithmetic, BRE `:` matches, short-circuit `|`/`&`; string comparisons are ordinal. |
| `seq` | done | full | 2 | 1 | `inf` and hexadecimal operands are not supported yet. |
| `factor` | done | full | 3 | 2 | BigInteger, Miller-Rabin, Pollard rho; `-h`; slow when two prime factors both have more than ~12 digits. |
| `sleep` | done | full | 1 | 1 | |
| `tee` | done | full | 1 | 1 | `-i` and `--output-error` are accepted but have no effect. |
| `[` | skip | - | - | - | PowerShell parses `[` as the start of a type literal, so it cannot be called as a command. Use `test`. |

## Running commands

| Util | Status | Scope | Difficulty | Batch | Notes |
|---|---|---|---|---|---|
| `env` | done | full | 3 | 2 | `-i -0 -u -C -S`; runs native and PowerShell commands, restores the environment; no signal options. |
| `printenv` | done | full | 1 | 1 | Output sorted by name (GNU prints environment order). |
| `nice` | skip | - | - | - | Windows has priority classes, not niceness, and child processes only inherit lower priorities. Use `Start-Process` and `(Get-Process).PriorityClass`. |
| `nohup` | skip | - | - | - | Windows has no hangup signal, so only the nohup.out redirection would remain. Use `Start-Process` to keep a program running. |
| `timeout` | done | full | 3 | 2 | External programs only; signals terminate on Windows; exit codes 124/125/126/127/137 as GNU. |
| `kill` | done | subset | 2 | 2 | `-s -SIGNAL -l -t`; Linux signal numbers; Windows terminates the process tree; no process groups. |
| `stdbuf` | skip | - | - | - | Works by injecting a library through `LD_PRELOAD`, which has no Windows equivalent. |
| `chroot` | skip | - | - | - | Windows cannot change a process's file system root. |

## User and system info

| Util | Status | Scope | Difficulty | Batch | Notes |
|---|---|---|---|---|---|
| `whoami` | done | full | 1 | 1 | No `DOMAIN\` prefix (unlike `whoami.exe`). |
| `id` | done | subset | 3 | 2 | SIDs and DOMAIN\NAME on Windows; Linux reads /proc and /etc; no `-Z`. |
| `groups` | done | subset | 3 | 2 | Same sources as `id`. |
| `uname` | done | full | 1 | 1 | Kernel name `Windows_NT`, OS `Windows` on Windows. |
| `arch` | done | full | 1 | 1 | |
| `hostname` | done | subset | 1 | 1 | Setting the host name is not supported. |
| `nproc` | done | full | 1 | 1 | `--all` equals the runtime's processor count. |
| `uptime` | done | subset | 2 | 2 | coreutils line plus procps `-p -s`; no load averages on Windows. |
| `date` | done | subset | 3 | 2 | All `+FORMAT` sequences/flags, `-d -f -r -u -I -R --rfc-3339`; no date setting, no TZ variable, `-d` subset grammar, 100 ns resolution. |
| `users`, `who`, `pinky` | skip | - | - | - | Read the Unix utmp login records, which Windows does not have. |
| `logname` | skip | - | - | - | No login-terminal concept on Windows; it would just duplicate `whoami`. |
| `tty`, `stty` | skip | - | - | - | Windows consoles have no tty devices or terminal line settings. |
| `hostid` | skip | - | - | - | The Unix 32-bit host id has no meaning on Windows. |

## Other GNU packages

| Util | Status | Scope | Difficulty | Batch | Notes |
|---|---|---|---|---|---|
| `grep` | done | full | 4 | 4 | BRE/ERE translated to .NET regex (POSIX classes, `\<` `\>`, backreferences); `-P` is .NET syntax; pipeline objects are matched as displayed; piped input is searched as it arrives. |
| `sed` | planned | subset | 4 | 4 | `s///` with flags, `d p q a i c y =`, addresses and ranges, `-n -i -E -s`; no hold space (`h H g G x`), labels/branching (`b t :`) or `N D P`. |
| `find` | planned | subset | 4 | 4 | Expression parser (`! -o -a ( )`), `-name -iname -path -type -size -mtime -mmin -newer -maxdepth -mindepth -empty -print -print0 -exec -delete`; no `-printf -perm -user -group -newerXY`. |
| `xargs` | planned | full | 4 | 4 | Windows command-line quoting rules make it tricky but it is essential for pipelines. |
| `diff` | planned | subset | 4 | 4 | Myers algorithm, normal / unified / context output, `-r -u -q -i -w -b -N`. |
| `cmp` | done | full | 2 | 3 | `-b -i -l -n -s`, SKIP operands; messages and exit codes of GNU diffutils 3.12. |
| `gzip`, `gunzip`, `zcat` | planned | subset | 3 | 4 | `System.IO.Compression.GZipStream`; `-c -d -k -f -l -t -1..-9`. |
| `which` | done | full | 2 | 3 | PATH programs only (not aliases/functions); PATHEXT on Windows. |
| `less` | skip | - | - | - | Full-screen interactive pager (raw console input, resize, search). Use `less.exe` from Git for Windows or `Out-Host -Paging`. |
| `awk` | skip | - | - | - | A complete programming language (parser, interpreter, associative arrays, printf, getline). Use `gawk` from Git for Windows or `ForEach-Object`. |
| `diff3`, `sdiff` | skip | - | - | - | Three-way and interactive merging are projects of their own. Use `git merge-file`. |
| `tar` | skip | - | - | - | Windows 10+ ships `tar.exe` (bsdtar). |
| `locate`, `updatedb` | skip | - | - | - | Need a background indexing job; Windows Search already does that. |
| `egrep`, `fgrep` | skip | - | - | - | Deprecated aliases for `grep -E` / `grep -F`. |

## Command name conflicts

Enabling a util with `Enable-GnuUtil` overrides these existing commands (restored on `Disable-GnuUtil`):

| GNU name | Windows PowerShell 5.1 | PowerShell 7 on Windows | Linux/macOS |
|---|---|---|---|
| `cat` | alias of `Get-Content` | alias of `Get-Content` | `/usr/bin/cat` |
| `echo` | alias of `Write-Output` | alias of `Write-Output` | `/usr/bin/echo` |
| `pwd` | alias of `Get-Location` | alias of `Get-Location` | `/usr/bin/pwd` |
| `sleep` | alias of `Start-Sleep` | alias of `Start-Sleep` | `/usr/bin/sleep` |
| `tee` | alias of `Tee-Object` | alias of `Tee-Object` | `/usr/bin/tee` |
| `rmdir` | alias of `Remove-Item` | alias of `Remove-Item` | `/usr/bin/rmdir` |
| `mkdir` | built-in function | built-in function | `/usr/bin/mkdir` |
| `hostname`, `whoami` | `hostname.exe`, `whoami.exe` | `hostname.exe`, `whoami.exe` | native |

Run `Get-GnuUtil` to see the `Shadows` column for your own session.
