# Plan

Roadmap of PSGnuUtils. Utils are implemented **easiest first** (fewest lines of code), in batches. The status of
every util is tracked in [UTILS.md](UTILS.md); this file explains the order and the larger design work.

## Phase 0 - Foundation (done, 2026-11-07)

- [x] Repository structure, build script (no CI by decision of the user, 2026-11-07)
- [x] Framework: getopt_long parser, util registry, contexts, help/version, errors and exit codes
- [x] Input model (pipeline = stdin, files, wildcards) and output model (lines, NUL records)
- [x] `Get-GnuUtil`, `Enable-GnuAlias`, `Disable-GnuUtil`, import-time configuration, alias restore on module removal
- [x] Meta tests: exports, help, docs, option coverage, ASCII-only sources
- [x] Agent handoff docs (docs/AGENTS.md, agents/CLAUDE.md, DEVLOG.md, TODO.md)

## Batch 1 - trivial utils (done 2026-11-07: 698 tests green on 5.1 and 7, 95.6% coverage)

`true false yes echo basename dirname pwd sleep arch nproc whoami hostname printenv uname link unlink mkdir rmdir
truncate mktemp cat tac head tail tee wc seq base64 base32 md5sum sha1sum sha256sum sha384sum sha512sum`

Next step: run the suite once on Linux/macOS, then release 0.1.0.

## Batch 2 - easy (difficulty 1-3, mostly line filters)

Done 2026-11-07: `pathchk fold expand nl uniq cut paste comm`, plus `rm` from batch 3 (the user tried `rm -rf`).

Order: `unexpand tsort shuf tr cksum sum readlink realpath touch
sync install shred dircolors basenc sha224sum printf test expr factor env nice nohup timeout kill id groups uptime
date` and `tail -f/-F/--pid/--retry/-s`.

Shared work for this batch:
* `Private/Lib/Date.ps1`: `ConvertFrom-GnuDateString` (ISO 8601, `@epoch`, `now/today/yesterday/tomorrow`,
  "N unit(s) [ago]"), used by touch `-d` and date `-d`; `Format-GnuDate` for `date +FORMAT`.
* `Private/Lib/Process.ps1` for env / nice / nohup / timeout (start native or PowerShell commands, wait, kill).
* printf: reuse `ConvertFrom-GnuEscape` (add `\NNN` without leading 0 and `\uHHHH`) and `Format-GnuFloat`
  (add `%d %i %o %u %x %X %c %s %b %q`).

## Batch 3 - medium

`cmp which mv cp ln df du stat split csplit fmt numfmt join sort od dd ls`

* sort: key specs (`-k POS1[,POS2]` with `bnr...` modifiers), `-t`, stable merge; ordinal vs culture comparison
  needs a decision (GNU uses the locale; LC_ALL=C is ordinal).
* ls: column layout (`-C`, width from the console), `-l` long format (permissions string from attributes on
  Windows), colors from `LS_COLORS` / dircolors.

## Batch 4 - hard but worth it

`grep xargs diff find sed gzip gunzip zcat`

grep design:
1. GNU args (done by the framework): `UsageExitCode = 2`; exit 0 match / 1 none / 2 error.
2. Pattern -> .NET regex: BRE translator (`\( \) \{ \} \| \+ \?` special, bare ones literal), ERE mostly as is,
   POSIX classes `[[:alpha:]]` -> `\p{L}`, `-w` -> `(?<!\w)(?:p)(?!\w)`, `-x` -> `^(?:p)$`, `-i` -> IgnoreCase,
   `-F` -> `String.IndexOf` (ordinal), `-P` -> as is. Always `RegexOptions.Compiled`.
3. Inputs: files, `-r` with `--include/--exclude/--exclude-dir`, binary detection (NUL in the first 8 KB),
   pipeline input (objects rendered like the console, so `Get-Process | grep pwsh` works).
4. Output: `-n -H -h -c -l -L -o -q -s -m`, context `-A -B -C` (ring buffer + `--` separators),
   `--color=auto|always|never` (auto = console output not redirected).

## Release

* 0.1.0: tests green on Windows PowerShell 5.1 and PowerShell 7 (Windows, ideally Linux/macOS too).
* Before the first publish: set `ProjectUri` in the manifest (needs the public repository URL),
  then `./build.ps1 -Publish -NuGetApiKey <key>` and tag `v0.1.0`.
* Versioning: semantic versioning; every batch is a minor release.

## Open questions

* Should importing the module auto-enable a default set of non-conflicting utils? (Currently: nothing is enabled.)
* Option to write GNU style errors to the raw stderr stream instead of the PowerShell error stream (shorter output)?
* Stopping upstream for `yes | head` (see ARCHITECTURE.md).
