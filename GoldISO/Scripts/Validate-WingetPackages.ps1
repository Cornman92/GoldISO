#Requires -Version 5.1
<#
.SYNOPSIS
    Validate winget package identifiers in Config/winget-packages.json.

.DESCRIPTION
    For each PackageIdentifier in the manifest, runs `winget show` to confirm
    the package still exists and the ID is valid. Outputs a summary table and
    writes results to Logs/.

.PARAMETER ManifestPath
    Path to winget-packages.json. Default: Config/winget-packages.json

.PARAMETER OutputPath
    Directory to write the validation log. Default: Logs/ (project root)

.EXAMPLE
    .\Validate-WingetPackages.ps1

.EXAMPLE
    .\Validate-WingetPackages.ps1 -Verbose
#>
[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"
$script:ProjectRoot = Split-Path $PSScriptRoot -Parent

Import-Module (Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1") -Force

if (-not $ManifestPath) {
    $ManifestPath = Join-Path $script:ProjectRoot "Config\winget-packages.json"
}
if (-not $OutputPath) {
    $OutputPath = Join-Path $script:ProjectRoot "Logs"
}

$logPath = Join-Path $OutputPath "winget-validation-$(Get-Date -Format yyyyMMdd-HHmmss).log"
Initialize-Logging -LogPath $logPath

Write-GoldISOLog "Winget Package Validator" -Level "INFO"
Write-GoldISOLog "Manifest: $ManifestPath" -Level "INFO"

# Validate prerequisites
if (-not (Test-Path $ManifestPath)) {
    Write-GoldISOLog "Manifest not found: $ManifestPath" -Level "ERROR"
    exit 1
}

$winget = Get-Command winget -ErrorAction SilentlyContinue
if (-not $winget) {
    Write-GoldISOLog "winget not found in PATH - install App Installer from the Microsoft Store" -Level "ERROR"
    exit 1
}

# Parse manifest
$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
$packages  = $manifest.Sources[0].Packages
Write-GoldISOLog "Loaded $($packages.Count) packages from manifest" -Level "INFO"

# Validate each package
$results = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($pkg in $packages) {
    $id = $pkg.PackageIdentifier
    Write-Verbose "Checking: $id"

    try {
        $output = winget show $id --disable-interactivity 2>&1
        $valid = ($LASTEXITCODE -eq 0) -and ($output -notmatch "No package found")
        $status = if ($valid) { "OK" } else { "NOT FOUND" }
    }
    catch {
        $valid  = $false
        $status = "ERROR: $($_.Exception.Message)"
    }

    $results.Add([PSCustomObject]@{
        PackageIdentifier = $id
        Category          = $pkg.Category
        Status            = $status
        Valid             = $valid
    })

    $level = if ($valid) { "SUCCESS" } else { "WARN" }
    Write-GoldISOLog "[$status] $id ($($pkg.Category))" -Level $level
}

# Summary
$valid   = ($results | Where-Object Valid).Count
$invalid = ($results | Where-Object { -not $_.Valid }).Count

Write-GoldISOLog "----------------------------------------" -Level "INFO"
Write-GoldISOLog "Results: $valid valid, $invalid invalid / $($results.Count) total" -Level $(if ($invalid -gt 0) { "WARN" } else { "SUCCESS" })

if ($invalid -gt 0) {
    Write-GoldISOLog "Invalid packages:" -Level "WARN"
    $results | Where-Object { -not $_.Valid } | ForEach-Object {
        Write-GoldISOLog "  $($_.PackageIdentifier) [$($_.Category)] - $($_.Status)" -Level "WARN"
    }
}

Write-GoldISOLog "Full log: $logPath" -Level "INFO"

# Return structured result for pipeline use
return [PSCustomObject]@{
    Total   = $results.Count
    Valid   = $valid
    Invalid = $invalid
    Results = $results
}
