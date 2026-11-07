# Agent guide (LLMs and humans)

PSGnuUtils is a PowerShell module (PowerShell Gallery) that reimplements GNU coreutils and friends in pure
PowerShell for **Windows PowerShell 5.1 and PowerShell 7+ on Windows, Linux and macOS**.

## Start here

1. Read [TODO.md](../TODO.md): the current, concrete next steps.
2. Read the latest entries of [docs/DEVLOG.md](DEVLOG.md): what happened, what is unverified.
3. Check [docs/UTILS.md](UTILS.md) (status of every util) and [docs/PLAN.md](PLAN.md) (order, designs).
4. Read [docs/ARCHITECTURE.md](ARCHITECTURE.md) before touching `src/PSGnuUtils/Private/Core`.

## Commands

```powershell
./build.ps1 -Bootstrap                     # install Pester >= 5.5 and PSScriptAnalyzer (CurrentUser)
./build.ps1                                     # Analyze + Test
./build.ps1 -Test -TestPath tests/Utils/head.Tests.ps1
./build.ps1 -Manifest                      # regenerate FunctionsToExport after adding/removing a util
./build.ps1 -Build -TestBuild              # build out/PSGnuUtils and test the built module
./build.ps1 -Install                             # build and install into the user's module folder(s); Uninstall removes it
./tools/New-GnuUtil.ps1 -Name cut -Category 'Text processing' -Synopsis 'Remove sections from each line of files.'
```

Run tests on **both** `powershell` (5.1) and `pwsh` (7) before calling something done. Ask the user before running
the full suite if they said they are busy with something performance sensitive (they did on 2026-11-07).

## Rules

* **Every util**: `src/PSGnuUtils/Utils/<name>.ps1` (spec + `Invoke-Gnu<Name>`), `tests/Utils/<name>.Tests.ps1`
  exercising **every option** (the meta tests check this), a row in `docs/UTILS.md`, a CHANGELOG entry.
* Utils are simple functions without `param()`/`[CmdletBinding()]` that pass `$args` to `Initialize-GnuUtil`
  (see ARCHITECTURE.md "Why utils are simple functions").
* Match GNU output, messages and exit codes exactly; document every deliberate difference in the spec `Notes`
  (shown by `--help`), the comment-based help and `docs/UTILS.md`.
* PowerShell 5.1 compatible syntax only (no `? :`, `??`, `&&`, `||`, `$IsWindows`, ...). ASCII-only source and test
  files. Invariant culture for numbers. Ordinal string comparisons (`[System.StringComparison]::Ordinal`,
  `[string]::IsNullOrEmpty()` instead of `-eq ''`; see ARCHITECTURE.md). Strict mode safe code (no dot access to possibly missing hashtable keys,
  `@($x).Count`).
* Paths: `Resolve-GnuPath` (PowerShell location), never `[Environment]::CurrentDirectory`.
* Errors: `Write-GnuError` / `Write-GnuUsageError` / `Write-GnuWarning`; never `throw` for user errors, never `exit`.
* `Invoke-Gnu<Name>` is reserved for util entry points: never name a helper `Invoke-Gnu<Word>` where Word could be a util
  (a helper `Invoke-GnuLink` once replaced the `link` util). Keep functions small; move shared code into `Private/Lib`. Comment the *why*, not the *what*.
* Log every work session in `docs/DEVLOG.md` (date, what changed, what is verified / unverified, next steps) and
  keep `TODO.md` current. Commit in small logical steps with clear messages.
