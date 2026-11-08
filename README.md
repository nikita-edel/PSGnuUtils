# PSGnuUtils

GNU coreutils in pure PowerShell, for Windows PowerShell 5.1 and PowerShell 7+. See [docs/UTILS.md](docs/UTILS.md)
for the list of utils.

```powershell
./build.ps1 -Install # or Install-Module PSGnuUtils or download the Release and run the installscript
Import-Module PSGnuUtils
Import-GnuUtil -MostUsed # all utils LazyLoad by default (at runtime)
Invoke-GnuHead -n 5 app.log       # every util is Invoke-Gnu<Name>
Enable-GnuAlias cat, head, tail   # opt in to the GNU names
Disable-GnuAlias -All
```
