# TODO

Concrete next steps, most important first. Keep this list short and current; history goes to docs/DEVLOG.md.

## Now

- [x] Bootstrap, Analyze, Test on 5.1 and 7, Build + TestBuild (all green, 2026-11-07; see docs/DEVLOG.md).
- [x] Coverage: 95.6% (target 90%).
- [ ] Rewrite the `--help` texts (Description/Notes/option Help in the util specs) in our own words; several are
      close to GNU's GPL-licensed help text (see docs/DEVLOG.md / license discussion).
- [ ] Push to GitHub and check the CI matrix (Linux/macOS especially: symlinks, `/` vs `\`, Unix modes).
- [ ] Run the symlink tests once with developer mode enabled (they are skipped otherwise on Windows).

## Next

- [ ] Release 0.1.0: set ProjectUri/LicenseUri in the manifest, add the PSGALLERY_API_KEY secret, tag `v0.1.0`.
- [ ] Batch 2 (see docs/PLAN.md), starting with `pathchk fold expand unexpand nl uniq cut paste comm`.
- [ ] `tail -f/-F/--pid/--retry/-s`.

## Ideas

- [ ] Stop upstream commands for `yes | head` (C# helper cmdlet via Add-Type?).
- [ ] Optional GNU-style stderr output instead of PowerShell error records.
- [ ] Integration tests that compare with real GNU tools when available (Linux CI, Git for Windows).
