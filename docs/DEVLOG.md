# Development log

Newest entry first. Every work session adds an entry: what changed, what was verified, what is unverified, what is
next. Keep entries short and factual so the next person (or LLM) can continue without guessing.

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
- Open: `.github/workflows` were deleted in the working tree by the user (not committed); waiting for a decision.

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
