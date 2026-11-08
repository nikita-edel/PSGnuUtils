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
- `rm` (pulled forward from batch 3): `-f -i -I --interactive -r -R -d -v --preserve-root --no-preserve-root --one-file-system`.
- Daily-use utils: `touch which ln mv cp sort ls grep`.
- Batch A: `readlink realpath basenc unexpand tsort shuf sha224sum cksum sum factor`.
- Batch B: `tr printf test expr date`.
- Batch C: `env timeout kill id groups uptime install shred dircolors`, and `tail -f/-F/--pid/--retry/-s`.
- Batch D: `od cmp join`.
- Build script (Bootstrap, Manifest, Analyze, Test, Build, TestBuild, Install, Uninstall, Publish, Clean).
