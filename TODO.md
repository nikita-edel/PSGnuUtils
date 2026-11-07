# TODO

Concrete next steps, most important first. Keep this list short and current; history goes to docs/DEVLOG.md.

## Now

- [x] Bootstrap, Analyze, Test on 5.1 and 7, Build + TestBuild (all green, 2026-11-07; see docs/DEVLOG.md).
- [x] Coverage: 95.6% (target 90%).
- [ ] Push to GitHub and check the CI matrix (Linux/macOS especially: symlinks, `/` vs `\`, Unix modes).
- [ ] Run the symlink tests once with developer mode enabled (they are skipped otherwise on Windows).

## Next

- [ ] Release 0.1.0: set ProjectUri in the manifest, add the PSGALLERY_API_KEY secret, tag `v0.1.0`.
- [ ] Batch 2 (see docs/PLAN.md), next: `unexpand tsort shuf tr cksum sum readlink realpath touch`.
      unexpand: replicate GNU's pending-blank rules exactly (one blank before a tab stop stays a space).
- [ ] `tail -f/-F/--pid/--retry/-s`.

## Ideas

- [ ] Stop upstream commands for `yes | head` (C# helper cmdlet via Add-Type?).
- [ ] Optional GNU-style stderr output instead of PowerShell error records.
- [ ] Integration tests that compare with real GNU tools when available (Linux CI, Git for Windows).
