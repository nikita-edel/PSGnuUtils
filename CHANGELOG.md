# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Licensed under GPL-3.0-or-later (same as GNU coreutils).
- Module framework: GNU getopt_long compatible argument parsing, generated `--help` / `--version`, GNU style errors
  and exit codes (`$LASTEXITCODE`), pipeline input as stdin, shell-like wildcard expansion.
- `Get-GnuUtil`, `Enable-GnuUtil`, `Disable-GnuUtil` and import-time configuration
  (`Import-Module PSGnuUtils -ArgumentList @{ All = $true; Exclude = 'ls' }`); replaced aliases are restored on
  disable and on module removal.
- Batch 1 utils: `arch base32 base64 basename cat dirname echo false head hostname link md5sum mkdir mktemp nproc
  printenv pwd rmdir seq sha1sum sha256sum sha384sum sha512sum sleep tac tail tee true truncate uname unlink wc
  whoami yes`.
- Batch 2 (first part): `comm cut expand fold nl paste pathchk uniq`.
- Build script (Bootstrap, Manifest, Analyze, Test, Build, TestBuild, Install, Uninstall, Publish, Clean), CI for Windows PowerShell 5.1
  and PowerShell 7 on Windows, Linux and macOS, tag-triggered publishing to the PowerShell Gallery.
