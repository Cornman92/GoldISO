#Requires -Version 5.1
<#
.SYNOPSIS
    Shared helper functions for GoldISO Pester test suites.
#>

function Find-ScriptPath {
    <#
    .SYNOPSIS
        Finds a script file by name anywhere under the Scripts directory tree.
    .DESCRIPTION
        Returns the full path of the first matching script file found recursively
        under $script:ProjectRoot\Scripts. Returns $null if not found.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Name)

    $root = if ($script:ProjectRoot) { $script:ProjectRoot } else { Split-Path $MyInvocation.ScriptName -Parent | Split-Path -Parent }
    $scriptsRoot = Join-Path $root "Scripts"
    $match = Get-ChildItem -Path $scriptsRoot -Filter $Name -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($match) { return $match.FullName }
    return $null
}
