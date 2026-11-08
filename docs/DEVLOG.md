# Development log

Newest entry first. Every work session adds an entry: what changed, what was verified, what is unverified, what is
next. Keep entries short and factual so the next person (or LLM) can continue without guessing.

## 2026-11-08 (later) - dd streams files, TestBuild green

- dd reads and writes files block by block (read 2 MB past the 3 GB mark of a 3 GB file); pipeline data stays in
  memory. Like GNU it now sizes the output before copying (seek extends or truncates even with nothing to copy), and
  if=X of=X empties X while conv=notrunc copies in place. Read and write errors end the copy and print statistics.
- dd statistics round to nearest (du/df round up) and drop the IEC form below 1024 bytes, as GNU does.
- TestBuild: Get-GnuModuleVersion finds the manifest next to the merged psm1; the per-util origin meta test checks
  the definition there. Was 87 failures, now 0.
- Compared with GNU 8.32 (172 cases, 5.1 and 7.6): 169 identical; the other 3 are the ones explained below.
- Not done: WSL. It has no pwsh, installing needs sudo, and downloading a portable pwsh was denied by the session's
  permission rules. Linux/macOS remain unverified.

## 2026-11-08 (end of Batch D) - dd df du, unquoted comma lists

- New: dd, df, du. Shared in Private/Lib/Size.ps1: Format-GnuHumanSize, ConvertFrom-GnuBlockSize (GNU's SIZE rules
  and df header labels), Get-GnuSizeScale, Format-GnuScaledSize, Write-GnuSizeArgumentError.
- Parser: arrays are rejoined when GNU reads them as one option value (`cut -f 1,3`); Context.Spellings records how
  an option was written, for messages like `invalid -B argument`. -h --si -k -m -B (du also -b) share the key
  'scale' so the last one wins.
- Compared with GNU coreutils 8.32 (145 cases, 5.1 and 7.6): 142 identical. The other 3: two du runs where GNU sees
  real NTFS allocation and we estimate 4 KiB clusters (documented), and one harness artifact (no newline after -0).
  The comparison found: conv=swab across odd blocks, overflow exceptions on huge numbers, unit suffixes for -BM,
  -P header sizes, option order for size options, the mutual-exclusion errors of df --output, and several messages.
- Results: 2353 tests on 7.6 (100% coverage, analyzer clean), 2348 on 5.1. Windows PowerShell started from a
  PowerShell 7 shell inherits its PSModulePath and loses core cmdlets; use `env -u PSModulePath powershell`.
- Unverified: Linux/macOS. df with the real /proc/mounts has only mocked coverage.
- TestBuild: 2266 pass, 87 fail, all from two tests that assume the source layout (see TODO.md); neither involves
  this batch's code. Not fixed here.
- Also suppressed a false-positive analyzer warning in stat.ps1 (a parameter used only in a MatchEvaluator).
- Next: find sed xargs diff (TODO.md).

## 2026-11-09 (later) - Batch C: env timeout kill id groups uptime install shred dircolors, tail -f

- Skipped after review with the user: nice, nohup, sync (reasons in UTILS.md). kill stays (user request).
- New core: Private/Core/Command.ps1 (signal table, Send-GnuSignal, child commands, Windows command-line
  quoting, ProcessStartInfo with ArgumentList or a quoted command line), Private/Lib/Identity.ps1 (Windows SIDs,
  Linux /proc + /etc files, other Unix via id(1); paths and commands injectable for tests),
  Private/Lib/DircolorsDatabase.ps1 (GNU 8.32 database).
- timeout polls ReadLineAsync (no .NET event handlers, they have no runspace); env builds a script block for
  PowerShell commands because splatted '-Name' strings are positional; tail -f/-F/--pid/--retry/-s poll.
- Compared with GNU 8.32: dircolors -b/-c/-p identical; install/shred/kill/timeout messages and exit codes.
- Traps (ARCHITECTURE.md): .NET 9 keeps variables set to '' ([NullString]::Value), $? after a script block,
  $Error.Count capped at 256 in long runs, "$x:" needs ${x}, argument-mode casts, .NET Framework misreading an
  emptied environment block, Windows PowerShell 5.1 not escaping quotes for native programs.
- Results: 1843 tests green on 7.6 (100% coverage, analyzer clean), 1837 + the fixed env test on 5.1.

## 2026-11-09 - Batch B: tr printf test expr date

- tr: sets with ranges, C-locale classes, [c*n], [=c=], octal escapes (GNU's two-digit rule above \377),
  -c/-C -d -s -t and every GNU operand / set error; output compared with GNU tr (identical).
- printf: conversions d i o u x X f F e E g G c s b q, flags, `*` widths, escapes incl. Unicode, strtoimax-style
  number parsing with GNU's messages (not completely converted, out of range, expected a numeric value).
- test: port of GNU's posixtest (1-4 argument rules, then ! ( ) -a -o grammar) with GNU's messages and quirks
  (`-l` with string operators); file tests use .NET, Unix file types via PowerShell 7's UnixMode (mockable).
- expr: GNU's grammar with BigInteger, short-circuit evaluation of | and &, anchored BRE matches.
- date: strftime engine with flags/widths, -d -f -r -u -I -R --rfc-3339; ConvertFrom-GnuDateString got -Utc and
  100 ns fractions. Every sequence compared with GNU date -u (identical except %N below 100 ns).
- Traps found (in ARCHITECTURE.md): [int] rounds half to even (+05:30 became +06:30), [char] -eq is
  case-insensitive, hashtable literals reject keys differing only in case, heredocs/tools mangle backslash escapes.
- Results: 1659 tests green on 7.6, 1664 on 5.1, 99.84% coverage before the last gap fixes, analyzer clean.

## 2026-11-08 (night) - Batch A: readlink realpath basenc unexpand tsort shuf sha224sum cksum sum factor

- New libs: Private/Lib/Canonical.ps1 (Get-GnuCanonicalPath for readlink -f/-e/-m and realpath), Sha224.ps1
  (SHA-224 in PowerShell; the checksum engine takes algorithms with a `Compute` scriptblock). Base32 takes an
  alphabet (base32hex).
- Compared with the GNU coreutils 8.32 binaries of Git for Windows: cksum, sum (-r/-s), unexpand (all tab list
  forms), basenc (all encodings) and tsort give byte-identical output. tsort is a port of GNU's algorithm (strcmp
  order, successors newest first, GNU's loop detection), so order and loop reports match. `cksum -a` and
  `factor -h` are 9.x features and could not be compared.
- Found: a help line starting with `.NET` breaks comment-based help; Pollard rho in PowerShell cannot factor
  numbers with two large (17+ digit) prime factors in reasonable time (documented, test replaced); `shuf -r -o`
  without `-n` looped forever (now a usage error). Added to ARCHITECTURE.md.
- Results: full suites 1440 passed on 7.6 / 1435 on 5.1 with 2 failures (the help trap and a hard-coded
  `sha*sum` count), both fixed and re-run green; coverage 99.95%; analyzer clean.

## 2026-11-08 (evening) - grep

- grep with Private/Lib/Regex.ps1 (POSIX BRE/ERE -> .NET, reusable for sed); one line engine for streamed pipeline
  input and files: -A/-B/-C/-NUM with '--', -c -l -L -o -q -m -n -b -H -h -Z --label, -r/-R with
  --include/--exclude/--exclude-dir, binary detection (-a, -I, --binary-files), -z, --color; exit 0/1/2.
- Found: .NET Framework regex errors are localized (German here), so unbalanced groups are detected by
  Get-GnuParenthesisBalance instead of parsing messages. NUL characters in a failing test's message break
  Pester's NUnit XML export (only on failures).
- Results: 1232 tests green on 5.1, 1237 on 7.6, 99.8% coverage, analyzer clean.

## 2026-11-08 (later) - sort and ls

- sort: keys, separators, n/g/h/V/M orders, -u/-s/-c/-C/-o/-z, GNU's last-resort whole-line comparison, exit code 2 on trouble.
- ls: columns on the console (Test-GnuConsoleOutput: last in pipeline and not redirected), -l with owners
  (User/Group properties on Unix, Get-Acl on Windows), -h, -R, -t/-S/-U/-r, -F/-p, --color with LS_COLORS.
- Traps found: a [string] parameter turns $null into '' (sort's "no -t" became an empty separator); commas bind
  tighter than '*'; Int32.CompareTo(Int64) throws. Added to ARCHITECTURE.md.
- Results: 1177 tests green on 5.1, 1182 on 7.6, 99.7% coverage, analyzer clean.

## 2026-11-08 - CI removed, touch/which/ln/mv/cp

- No CI (user decision): workflows deleted, docs updated; publish by hand with ./build.ps1 -Publish.
- New: touch (Private/Lib/Date.ps1), which, ln, mv, cp (Private/Lib/Transfer.ps1: target planning, tree copy/removal,
  symlink creation); prompts moved to Private/Core/Prompt.ps1.
- Bugs found: a helper named Invoke-GnuLink replaced the link util (meta test now checks every util function comes
  from its own file); Directory.Delete(recursive) fails on junctions (Remove-GnuTree removes links itself).
- Results: 1110 tests green on 5.1, 1115 on 7.6, 99.9% coverage, analyzer clean.
- Next: ls, sort, grep (see TODO.md).

## 2026-11-07 (late night) - rm, build switches, Install

- The user ran `rm -rf meow` and got Remove-Item: rm was not implemented yet (batch 3), so Enable-GnuUtil had
  nothing to alias. Implemented rm now: -f -i -I --interactive[=WHEN] -r -R -d -v --preserve-root[=all]
  --no-preserve-root --one-file-system. Links/junctions are deleted, never followed; '/' and drive roots refused
  (tests simulate roots via a mocked Test-GnuRootPath, a real root is never touched); '.'/'..' refused; read-only
  files removed; prompts go to the console's stderr and read [Console]::In; piped FileSystemInfo objects are operands.
- build.ps1: Install/Uninstall tasks (user module folders, both editions on Windows) and one switch per task
  (`./build.ps1 -Install`); the user found `-Task Install` clumsy.
- Results: 945 tests green on 5.1, 951 on 7.6, 100% coverage (4650 commands), analyzer clean.

## 2026-11-07 (night) - 100% coverage

- Coverage 98.9% -> 100% (4449/4449 commands on PowerShell 7.6 / Windows). `./build.ps1 -Test -CodeCoverage`
  now fails below 98% (Linux/macOS cannot run the Windows-only branches and vice versa).
- Made environment-dependent code injectable instead of untestable: `Test-GnuOSPlatform`, `Get-GnuRuntimeInformation`
  (reflection, no try/catch), `Get-GnuUnixModeMethod`, `Get-GnuLinkTarget`, `Get-GnuModuleVersion -Module -ManifestPath`,
  mktemp's `New-GnuRandomText`. Tests live in `tests/Core/Injected.Tests.ps1`.
- mktemp: file creation now relies on `FileMode.CreateNew` to detect collisions atomically (no check-then-create race);
  a taken name is retried and is not reported as an error.
- Bug fixed: `Resolve-GnuPath` could still throw on Windows PowerShell 5.1 for names with control characters
  (`Path.Combine` validates on .NET Framework).
- Pester notes: coverage does not see default parameter values (set defaults in the body); Pester 6 does not fall back to
  the real command when a filtered mock does not match, and a module-qualified call inside a mock recurses into the mock.
- A test without `Push-Location` created an empty `cAAA` in the repo root; removed, and the test fixed.
- Results: 918 tests green on 5.1, 923 on 7.6, analyzer clean.

## 2026-11-07 (evening) - GPL, coverage, batch 2 part 1

- License changed to GPL-3.0-or-later (same as GNU coreutils) at the user's request; LICENSE is the GPLv3 text,
  `--version` prints the GNU style license notice, README credits GNU's help-text wording.
- Coverage 95.6% -> 98.9%: junction fallback for link tests (no admin needed on Windows), console stdin via
  `[Console]::SetIn`, locked-file read errors, mocked alias failures, platform branches with explicit input.
  Remaining misses: Linux/macOS-only branches, mktemp name-collision retries, the endless `sleep inf` loop.
- Bugs found: `mkdir 'bad|name'` threw on .NET Framework (`GetDirectoryName`), parsed option keys were
  case-insensitive (`-p`/`-P` collided) -> the options hashtable is now ordinal.
- New utils: pathchk, fold, expand (shared `Private/Lib/TabStop.ps1`), nl, uniq, cut, paste, comm.
  GNU details checked while writing tests: `uniq -f` keeps the blanks before a field, `uniq --group=append`
  separates groups too, `paste` stops without output when a file cannot be opened.
- Results: 893 tests green on Windows PowerShell 5.1, 892 on PowerShell 7.6 (each skips one test for the other
  runtime), analyzer clean.
- `.github/workflows` were deleted by the user; decided later the same day: no CI (deletion committed).

## 2026-11-07 (later) - First test run, all green on 5.1 and 7

**Results** (Windows 11, Windows PowerShell 5.1.26100 + Pester 5.x, PowerShell 7.6.7 + Pester 6.2.0)
- `./build.ps1 -Test`: 698 passed, 0 failed, 4 skipped on both 5.1 and 7 (skips: 3 symlink tests need admin or
  developer mode, 1 Unix-only mode test).
- `./build.ps1 -Build -TestBuild`: the merged single-file module passes the same 698 tests on both.
- `./build.ps1 -Analyze`: no issues.
- `-CodeCoverage`: 95.6% of 3211 commands. Remaining gaps: Linux/macOS branches in Platform.ps1/Path.ps1 and the
  skipped symlink paths (CI on Linux/macOS will exercise them).

**Bugs found by the first run and fixed**
- Culture-aware string comparisons: `"a`0b".EndsWith("`0")` is `$true`, and `[char]0x80 -eq ''` is `$true`
  (control characters are "ignorable"). All `StartsWith/EndsWith/IndexOf(string)` calls now pass `Ordinal`, and
  empty checks use `[string]::IsNullOrEmpty()`. Rule added to ARCHITECTURE.md and docs/AGENTS.md.
- `--version` printed `0.0`: the module version is not set while the psm1 is loading -> `Get-GnuModuleVersion`
  reads it at call time.
- `mktemp -p DIR` treated DIR as missing (it was modelled as an optional argument; only `--tmpdir` has one).
- `Resolve-GnuPath` fallback threw on .NET Framework for names containing `:`.
- Test bugs: `[decimal]'1.50'` drops the trailing zero; `seq -f FMT 2` prints two numbers; 5.1's `Get-ChildItem
  -Include -Recurse` returns directories; 5.1 does not escape quotes in native arguments (use `-EncodedCommand`);
  importing the module during Pester discovery hid load-time code from coverage.

**Environment notes**
- Starting Windows PowerShell from a PowerShell 7 session (or a shell started by one) inherits PS7's
  `PSModulePath`, so PackageManagement/PowerShellGet do not load. Run it with the default module path
  (`env -u PSModulePath powershell ...` from bash, or from cmd.exe). The bootstrap now explains this.
- The user moved `AGENTS.md` to `docs/AGENTS.md` and `CLAUDE.md` to `agents/CLAUDE.md`; links were updated.
  Note: Claude Code auto-loads `CLAUDE.md` only from the repo root (or `.claude/`), not from `agents/`.

## 2026-11-07 - Foundation and batch 1

**Context.** The user asked for a PSGallery module of GNU utils: everything tested, utils configurable
(list them, or `-All` with exclusions), PowerShell 5.1 + 7 + other OSes, automation scripts, clean structure, good
docs and logs so an LLM can continue; start with the easiest utils. The user was gaming and asked to write the
tests but **not run them** (performance). Functions use normal PowerShell names plus GNU-name aliases that override
existing aliases (user's request mid-session).

**Done**
- Repository layout, `build.ps1`, PSScriptAnalyzer settings (5.1/7 syntax compatibility), CI + publish workflows,
  `tools/New-GnuUtil.ps1` scaffolding, docs (README, AGENTS, CONTRIBUTING, ARCHITECTURE, PLAN, UTILS, CHANGELOG, TODO).
- Framework in `src/PSGnuUtils/Private/Core`, shared libraries in `Private/Lib`.
- 34 utils of batch 1 (list in PLAN.md) with tests for every option, plus core, public-command and meta tests.
- The former `PORTING.md` was folded into `docs/UTILS.md` (now with Scope/Difficulty/Batch columns, subset and skip
  reasons).

**Verified with small probes (not the test suite), on Windows PowerShell 5.1.26100 and PowerShell 7.6.7**
- In a simple function `$args` keeps `--` and `'--'`; `-5` arrives as `[int]`, `1.5` as `[double]`, `a,b` as an
  array; `-n:5` arrives as `'-n:'`, `5`. Array splatting passes `--` through.
- `$MyInvocation.ExpectingInput` is `$false` without pipeline input and `$true` with it, in begin/process/end.
- Creating a steppable `Select-Object -First` inside a function (in begin or process) to stop upstream commands
  terminates the **whole script** on both versions. Not usable; documented as a limitation.
- `Set-Alias -Scope Global -Option AllScope -Force` from inside a module overrides `ls` (AllScope on 5.1, None on 7),
  works from nested functions, and restoring with `Set-Alias` / `Remove-Item Alias:\x` from the module works.
- `Write-Error` in a helper shows the helper's name in the displayed error; `2>$null` and `2>&1` work.
- Strict mode Latest: `$hashtable.MissingKey` throws `PropertyNotFoundStrict`; `$scalar.Count` and `$null.Count`
  throw; `@($null).Count` is 1, `@(<command with no output>).Count` is 0.
- A function named `h` is shadowed by the built-in alias `h` (Get-History), a live example of why GNU names must be
  aliases.
- Hash test vectors in the checksum tests were verified with Python's hashlib.

**Unverified**
- Nothing in the Pester suite has been run yet; PSScriptAnalyzer has not been run. Expect some failures on first run.
- The CI workflow (`defaults.run.shell: ${{ matrix.shell }}`) has not run on GitHub yet.
- `./build.ps1 -Build` (merged psm1) has not been run.

**Next**
- See TODO.md.
