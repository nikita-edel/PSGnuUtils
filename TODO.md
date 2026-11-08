# TODO

Concrete next steps, most important first. Keep this list short and current; history goes to docs/DEVLOG.md.

## Now

- [x] Bootstrap, Analyze, Test on 5.1 and 7, Build + TestBuild (all green, 2026-11-07; see docs/DEVLOG.md).
- [x] Coverage: 100% on Windows / PowerShell 7 (build fails below 98% with -CodeCoverage).
- [x] Run the suite once on Linux (Ubuntu in WSL, 2026-11-08). In WSL the GNU tools are `gnudd`, `gnudu`, ...;
      plain `dd` etc. are uutils.
- [ ] Run the suite once on macOS (no CI): symlinks, `/` vs `\`, Unix modes.
- [ ] Run the symlink tests once with developer mode enabled (they are skipped otherwise on Windows).

## Next

- [x] `./build.ps1 -Package` and `.github/workflows/release.yml` (manual, no tests). Before the first run: push to
      GitHub, set ProjectUri in the manifest, add the repository secret PSGALLERY_API_KEY, tag `v<ModuleVersion>`.

- [ ] Daily-use utils still missing: `xargs` (then the rest of batch 2/3).
- [ ] `find -ls -fls -perm -user -group -uid -gid -nouser -nogroup -links -inum -samefile -newerXY -readable
      -writable -executable -files0-from`.
- [ ] `diff --color[=WHEN]` and `--palette`.
- [ ] Audit every util against GNU: make sure all its flags are implemented, and verify that each flag really exists in GNU.

- [ ] Release 0.1.0: set ProjectUri in the manifest, `./build.ps1 -Publish -NuGetApiKey <key>`, tag `v0.1.0`.
- [x] Batch D: `cmp od split csplit fmt join numfmt stat df du dd`.

## Ideas

- [ ] Stop upstream commands for `yes | head` (C# helper cmdlet via Add-Type?).
- [ ] Optional GNU-style stderr output instead of PowerShell error records.
- [ ] Integration tests that compare with real GNU tools when available (Linux, Git for Windows).
