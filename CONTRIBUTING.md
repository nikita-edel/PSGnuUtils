# Contributing

Thanks for helping! The short version of the rules is in [docs/AGENTS.md](docs/AGENTS.md); the design is in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Setup

```powershell
git clone <repo>
cd PS-GnuUtils
./build.ps1 -Bootstrap     # Pester >= 5.5, PSScriptAnalyzer
./build.ps1                     # analyze + test
```

Test with both Windows PowerShell 5.1 (`powershell`) and PowerShell 7 (`pwsh`) when you can; CI also runs Linux
and macOS.

## Adding a util

1. Pick the next util from [docs/PLAN.md](docs/PLAN.md) / [docs/UTILS.md](docs/UTILS.md).
2. Scaffold it:
   ```powershell
   ./tools/New-GnuUtil.ps1 -Name cut -Category 'Text processing' -Synopsis 'Remove sections from each line of files.'
   ```
3. Fill in the spec (`Register-GnuUtil @{ ... }`): every GNU option with its GNU help text, `Notes` for PowerShell
   specific differences. Look at an existing util of similar shape:
   * line filter with streaming: `cat.ps1`, `head.ps1`
   * whole-input processing: `tac.ps1`, `wc.ps1`
   * operands only: `basename.ps1`, `seq.ps1`
   * file system changes: `mkdir.ps1`, `truncate.ps1`
4. Implement `Invoke-Gnu<Name>`. Keep it short; put the work in a helper function in the same file, or in
   `Private/Lib` if another util needs it too.
5. Write `tests/Utils/<name>.Tests.ps1` with `Invoke-TestGnu`:
   ```powershell
   $r = Invoke-TestGnu cut '-d', ',', '-f', '2' -InputObject 'a,b,c'
   $r.Output   | Should -Be @('b')
   $r.ExitCode | Should -Be 0
   ```
   Cover every option (the meta tests fail otherwise), errors and exit codes, pipeline input and files.
   Compare with real GNU behaviour (e.g. Git for Windows' `usr/bin`, WSL or a Linux container) when unsure.
6. Update `docs/UTILS.md` (status `done`), `CHANGELOG.md`, `docs/DEVLOG.md`.
7. `./build.ps1` must pass (analyzer + all tests).

## Style

* 4 spaces, LF, UTF-8, ASCII-only `.ps1`/`.psm1`/`.psd1` files.
* Full cmdlet names and named parameters in module code, approved verbs, `$null` on the left of comparisons.
* PowerShell 5.1 compatible syntax; invariant culture for numbers.
* Comments explain why something is done, especially GNU quirks (`# GNU: tac joins an unterminated last line`).
