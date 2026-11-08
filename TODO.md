# TODO

Concrete next steps, most important first. Keep this list short and current; history goes to docs/DEVLOG.md.

## Now

- [x] Bootstrap, Analyze, Test on 5.1 and 7, Build + TestBuild (all green, 2026-11-07; see docs/DEVLOG.md).
- [x] Coverage: 100% on Windows / PowerShell 7 (build fails below 98% with -CodeCoverage).
- [ ] Run the suite once on Linux/macOS (no CI): symlinks, `/` vs `\`, Unix modes.
- [ ] Run the symlink tests once with developer mode enabled (they are skipped otherwise on Windows).
- [ ] `./build.ps1 -TestBuild` fails 87 tests: Module.Tests "is defined by its own Utils file" (86 utils; the build
      merges them into PSGnuUtils.psm1) and Injected.Tests "falls back to the manifest" (default path assumes the
      source tree). Make both aware of the built module before releasing.

## Next

- [ ] After all utils are done (100% coverage): `./build.ps1 -Package` -> zip with the module and an
      `install.ps1` that installs it offline (user request 2026-11-09).
- [ ] Then ONE manual GitHub workflow (workflow_dispatch, no tests): publish to PSGallery (repo secret with the
      API key), package the zip and upload it to the release of the latest tag; the release text is the diff of
      CHANGELOG.md against the latest release (the user writes the changelog).

- [ ] Daily-use utils still missing: `find sed xargs diff` (then the rest of batch 2/3).

- [ ] Release 0.1.0: set ProjectUri in the manifest, `./build.ps1 -Publish -NuGetApiKey <key>`, tag `v0.1.0`.
- [x] Batch D: `cmp od split csplit fmt join numfmt stat df du dd`.
- [ ] `dd` holds the whole input in memory (2 GB limit): stream files instead if large copies matter.

## Ideas

- [ ] Stop upstream commands for `yes | head` (C# helper cmdlet via Add-Type?).
- [ ] Optional GNU-style stderr output instead of PowerShell error records.
- [ ] Integration tests that compare with real GNU tools when available (Linux, Git for Windows).
