# TODO

Concrete next steps, most important first. Keep this list short and current; history goes to docs/DEVLOG.md.

## Now

- [x] Bootstrap, Analyze, Test on 5.1 and 7, Build + TestBuild (all green, 2026-11-07; see docs/DEVLOG.md).
- [x] Coverage: 100% on Windows / PowerShell 7 (build fails below 98% with -CodeCoverage).
- [ ] Run the suite once on Linux/macOS (no CI): symlinks, `/` vs `\`, Unix modes.
- [ ] Run the symlink tests once with developer mode enabled (they are skipped otherwise on Windows).

## Next

- [ ] Daily-use utils still missing: `find sed xargs diff` (then the rest of batch 2/3).

- [ ] Release 0.1.0: set ProjectUri in the manifest, `./build.ps1 -Publish -NuGetApiKey <key>`, tag `v0.1.0`.
- [ ] Batch B: `tr printf test expr date`.
- [ ] Batch C: `env nice nohup timeout kill id groups uptime sync install shred dircolors`.
- [ ] Batch D: `cmp od split csplit fmt join numfmt stat df du dd`.
- [ ] `tail -f/-F/--pid/--retry/-s`.

## Ideas

- [ ] Stop upstream commands for `yes | head` (C# helper cmdlet via Add-Type?).
- [ ] Optional GNU-style stderr output instead of PowerShell error records.
- [ ] Integration tests that compare with real GNU tools when available (Linux, Git for Windows).
