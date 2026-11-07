# TODO

Concrete next steps, most important first. Keep this list short and current; history goes to docs/DEVLOG.md.

## Now

- [ ] Run `./build.ps1 -Task Bootstrap` on Windows PowerShell 5.1 and PowerShell 7.
- [ ] Run `./build.ps1 -Task Analyze` and fix the findings.
- [ ] Run `./build.ps1 -Task Test` on 5.1 and 7; fix failing tests. The suite was written without being run, so
      check both sides when a test fails: the expectation may be wrong (compare with real GNU behaviour) or the code.
- [ ] Run `./build.ps1 -Task Build, TestBuild` (merged single-file module).
- [ ] Push to GitHub and check the CI matrix (Linux/macOS especially: symlinks, `/` vs `\`, Unix modes).
- [ ] Measure line coverage: `./build.ps1 -Task Test -CodeCoverage` (target 90%).

## Next

- [ ] Release 0.1.0: set ProjectUri/LicenseUri in the manifest, add the PSGALLERY_API_KEY secret, tag `v0.1.0`.
- [ ] Batch 2 (see docs/PLAN.md), starting with `pathchk fold expand unexpand nl uniq cut paste comm`.
- [ ] `tail -f/-F/--pid/--retry/-s`.

## Ideas

- [ ] Stop upstream commands for `yes | head` (C# helper cmdlet via Add-Type?).
- [ ] Optional GNU-style stderr output instead of PowerShell error records.
- [ ] Integration tests that compare with real GNU tools when available (Linux CI, Git for Windows).
