# PSGnuUtils

GNU coreutils (`cat`, `head`, `tail`, `wc`, `seq`, `sha256sum`, `base64`, ...) implemented in **pure PowerShell**:
GNU option syntax, GNU output and GNU exit codes, on **Windows PowerShell 5.1 and PowerShell 7+** on Windows, Linux
and macOS. Nothing changes until you opt in, per command.

> Status: early development. 80 utils are implemented; see [docs/UTILS.md](docs/UTILS.md) for every util,
> what is planned and what is deliberately skipped.

## Install

```powershell
Install-Module PSGnuUtils -Scope CurrentUser      # once published to the PowerShell Gallery
```

From source:

```powershell
./build.ps1 -Install            # build and install for the current user (Windows PowerShell 5.1 and PowerShell 7)
Import-Module PSGnuUtils       # in a new session
./build.ps1 -Uninstall          # remove it again

Import-Module ./src/PSGnuUtils/PSGnuUtils.psd1   # or load the source tree directly, without installing
```

## Usage

Every util is a normal PowerShell command named `Invoke-Gnu<Name>`:

```powershell
Invoke-GnuHead -n 5 app.log
Get-Content data.csv | Invoke-GnuTail -n +2
Invoke-GnuSha256sum *.zip
```

Enable the GNU names you want. Built-in aliases such as `cat -> Get-Content` are overridden and restored when you
disable the util or remove the module:

```powershell
Enable-GnuUtil cat, head, tail, wc        # just these
Enable-GnuUtil -All -Exclude ls, rm       # everything except ls and rm
Enable-GnuUtil -All -NoClobber            # only names that do not exist yet

cat -n notes.txt
Get-ChildItem | wc -l
seq -w 1 10 | head -3

Get-GnuUtil                              # list utils, Enabled state and what each name shadows
Disable-GnuUtil cat                      # cat is Get-Content again
Disable-GnuUtil -All
```

Enable them in every session with your profile (`notepad $PROFILE`):

```powershell
Import-Module PSGnuUtils -ArgumentList @{ All = $true; Exclude = 'ls', 'rm' }
# or: Import-Module PSGnuUtils -ArgumentList @{ Name = 'cat', 'head', 'tail' }
# keys: All, Name, Exclude, NoClobber
```

Every util supports `--help` and `--version`; `Get-Help Invoke-GnuHead -Full` shows the PowerShell help.

### What an enabled name shadows

`Enable-GnuUtil cat` creates a global alias `cat -> Invoke-GnuCat`. Aliases win over everything else
(alias > function > cmdlet > native program), so while it is enabled `cat` no longer reaches `Get-Content`, and on
Linux/macOS `cat` no longer runs `/usr/bin/cat`. This applies to the whole session, including scripts and other
modules that call the name. `Get-GnuUtil` shows in its `Shadows` column what each name would run otherwise.

The originals are still there, under other names:

```powershell
Get-Content notes.txt                                   # the cmdlet behind the old alias
sort.exe data.txt                                       # Windows: a name with .exe bypasses the alias
/usr/bin/cat notes.txt                                  # Linux/macOS: the full path bypasses the alias
& (Get-Command cat -CommandType Application) notes.txt  # any OS: the native program found in PATH
Disable-GnuUtil cat                                     # or give the name back
```

Use `-NoClobber` to enable only names that do not exist yet, or `-Exclude` to keep specific names
(on Linux/macOS you may prefer to enable nothing and call `Invoke-Gnu*` directly).

## How it fits into PowerShell

* **Pipeline input is stdin.** Strings are lines; other objects are converted to the text the console would show,
  so `Get-Process | Invoke-GnuWc -l` counts the lines you see. Files from `Get-ChildItem` become their full paths.
* **Output** is one string per line, ready for other cmdlets.
* **Errors** go to the PowerShell error stream (`2>$null` works), messages are GNU's
  (`head: cannot open 'x' for reading: No such file or directory`).
* **Exit codes** are in `$LASTEXITCODE`, as with native commands.
* **Wildcards** in file operands are expanded like a Unix shell does (`cat *.txt`), because PowerShell does not glob
  for functions.
* **Encoding**: files are read as UTF-8 (BOM detected), written as UTF-8 without BOM with LF line endings.

## Known limitations

* A PowerShell function cannot stop the command that feeds it, so `yes | head -1` never ends. Use
  `yes | Select-Object -First 1`. (Details in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).)
* `$?` stays `$true` after a failing util unless it wrote an error; check `$LASTEXITCODE`.
* Some utils implement only the commonly used subset of options; each one documents it in `--help` and in
  [docs/UTILS.md](docs/UTILS.md).

## Development

```powershell
./build.ps1 -Bootstrap   # Pester >= 5.5, PSScriptAnalyzer
./build.ps1                   # analyze + test
./build.ps1 -Build       # out/PSGnuUtils (single-file module)
```

See [CONTRIBUTING.md](CONTRIBUTING.md), [docs/AGENTS.md](docs/AGENTS.md), [docs/PLAN.md](docs/PLAN.md) and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## License

GNU General Public License version 3 or later (GPL-3.0-or-later), the license of GNU coreutils; see [LICENSE](LICENSE).

PSGnuUtils is an independent PowerShell reimplementation and contains no GNU source code. Option descriptions in the
`--help` texts follow the wording of GNU coreutils (Copyright Free Software Foundation, Inc., GPL-3.0-or-later).
PSGnuUtils is not affiliated with or endorsed by the GNU Project or the Free Software Foundation.
