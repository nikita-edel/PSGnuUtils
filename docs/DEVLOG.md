# Development log

Newest entry first. Every work session adds an entry: what changed, what was verified, what is unverified, what is
next. Keep entries short and factual so the next person (or LLM) can continue without guessing.

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
- `./build.ps1 -Task Build` (merged psm1) has not been run.

**Next**
- See TODO.md.
