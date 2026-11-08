<#
.SYNOPSIS
    Scaffolds a new util: src/PSGnuUtils/Utils/<name>.ps1, tests/Utils/<name>.Tests.ps1, manifest export.

.DESCRIPTION
    Creates both files from templates that follow the repository conventions (see CONTRIBUTING.md)
    and regenerates FunctionsToExport. Afterwards: implement the util, fill in the tests, update
    docs/UTILS.md (status), CHANGELOG.md and docs/DEVLOG.md.

.EXAMPLE
    ./tools/New-GnuUtil.ps1 -Name cut -Category 'Text processing' -Synopsis 'Remove sections from each line of files.'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9][a-z0-9_]*$')]
    [string]$Name,

    [Parameter(Mandatory)]
    [ValidateSet('File and directory operations', 'Permissions and ownership', 'File info and disk usage',
        'Viewing file contents', 'Text processing', 'Checksums', 'Paths and names', 'Shell helpers',
        'Running commands', 'User and system info', 'Searching and comparing', 'Archiving and compression')]
    [string]$Category,

    [Parameter(Mandatory)]
    [string]$Synopsis
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$functionName = 'Invoke-Gnu' + $Name.Substring(0, 1).ToUpperInvariant() + $Name.Substring(1)
$utilPath = Join-Path $repoRoot "src/PSGnuUtils/Utils/$Name.ps1"
$testPath = Join-Path $repoRoot "tests/Utils/$Name.Tests.ps1"
foreach ($path in @($utilPath, $testPath)) {
    if (Test-Path -LiteralPath $path) { throw "$path already exists." }
}

$util = @"
Register-GnuUtil @{
    Name         = '$Name'
    Category     = '$Category'
    Synopsis     = '$Synopsis'
    Usage        = @('$Name [OPTION]... [FILE]...')
    Description  = @('$Synopsis', '', 'With no FILE, or when FILE is -, read standard input.')
    FileOperands = `$true
    Options      = @(
        # @{ Short = 'x'; Long = 'example'; Help = 'describe the option' }
    )
}

function $functionName {
    <#
    .SYNOPSIS
    GNU ${Name}: $Synopsis

    .DESCRIPTION
    TODO: describe behaviour and PowerShell specific notes.
    Enable the GNU name with: Enable-GnuAlias $Name

    .EXAMPLE
    $functionName file.txt
    #>
    begin { `$ctx = Initialize-GnuUtil -Name '$Name' -Arguments `$args -ExpectingInput `$MyInvocation.ExpectingInput }
    process { if (-not `$ctx.Done) { Add-GnuPipelineInput -Context `$ctx -InputObject `$_ } }
    end {
        if (-not `$ctx.Done) {
            `$operands = @(`$ctx.Operands)
            if (`$operands.Count -eq 0) { `$operands = @('-') }
            foreach (`$operand in `$operands) {
                foreach (`$line in @(Get-GnuInputLine -Context `$ctx -Operand `$operand)) {
                    `$line   # TODO
                }
            }
        }
        Complete-GnuUtil -Context `$ctx
    }
}
"@

$test = @"
BeforeAll {
    . (Join-Path -Path (Split-Path -Parent `$PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe '$Name' {
    It 'processes pipeline input' {
        `$r = Invoke-TestGnu $Name -InputObject 'a', 'b'
        `$r.Text | Should -BeExactly "a``nb"
        `$r.ExitCode | Should -Be 0
    }

    It 'reports missing files' {
        `$r = Invoke-TestGnu $Name (Join-Path `$TestDrive 'missing')
        `$r.ExitCode | Should -Be 1
        `$r.ErrorText | Should -Match 'No such file or directory'
    }
}
"@

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($utilPath, $util.Replace("`r`n", "`n"), $utf8)
[System.IO.File]::WriteAllText($testPath, $test.Replace("`r`n", "`n"), $utf8)
& (Join-Path $repoRoot 'build.ps1') -Manifest

Write-Host "Created $utilPath"
Write-Host "Created $testPath"
Write-Host 'Next: implement the util, write the tests, update docs/UTILS.md, CHANGELOG.md and docs/DEVLOG.md.'
