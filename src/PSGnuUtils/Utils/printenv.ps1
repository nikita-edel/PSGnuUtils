Register-GnuUtil @{
    Name        = 'printenv'
    Category    = 'Running commands'
    Synopsis    = 'Print all or part of environment.'
    Usage       = @('printenv [OPTION]... [VARIABLE]...')
    Description = @(
        'Print the values of the specified environment VARIABLE(s).',
        'If no VARIABLE is specified, print name and value pairs for them all.'
    )
    Options     = @(
        @{ Short = '0'; Long = 'null'; Help = 'end each output line with NUL, not newline' }
    )
    Notes       = @(
        'Exit status is 1 if any VARIABLE is not set.',
        'PowerShell note: without VARIABLE the pairs are sorted by name; on Windows names are case-insensitive.'
    )
}

function Invoke-GnuPrintenv {
    <#
    .SYNOPSIS
    GNU printenv: print all or part of the environment.

    .DESCRIPTION
    Prints the value of each named environment variable (exit code 1 if one is missing), or
    every NAME=value pair sorted by name.
    Enable the GNU name with: Enable-GnuUtil printenv

    .EXAMPLE
    Invoke-GnuPrintenv HOME PATH
    #>
    begin { $ctx = Initialize-GnuUtil -Name 'printenv' -Arguments $args -ExpectingInput $MyInvocation.ExpectingInput }
    end {
        if (-not $ctx.Done) {
            $operands = @($ctx.Operands)
            $records = New-Object 'System.Collections.Generic.List[string]'
            if ($operands.Count -eq 0) {
                $variables = [System.Environment]::GetEnvironmentVariables()
                $names = New-Object 'System.Collections.Generic.List[string]'
                foreach ($key in $variables.Keys) { $names.Add([string]$key) }
                $names.Sort([System.StringComparer]::Ordinal)
                foreach ($name in $names) { $records.Add("$name=$($variables[$name])") }
            }
            else {
                foreach ($name in $operands) {
                    $value = $null
                    if ($name -ne '' -and $name.IndexOf('=') -lt 0) { $value = [System.Environment]::GetEnvironmentVariable($name) }
                    if ($null -eq $value) { $ctx.ExitCode = 1 } else { $records.Add($value) }
                }
            }
            ConvertTo-GnuRecordOutput -Record $records.ToArray() -Zero:(Test-GnuOption -Context $ctx -Key 'null')
        }
        Complete-GnuUtil -Context $ctx
    }
}
