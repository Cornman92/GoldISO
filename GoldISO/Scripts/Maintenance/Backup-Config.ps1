#Requires -Version 5.1
<#
.SYNOPSIS
    Backup GoldISO configuration files
.DESCRIPTION
    Creates timestamped backups of configuration files before build.
    Keeps last 5 backups by default.
.PARAMETER ConfigPath
    Path to config file to backup (default: autounattend.xml)
.PARAMETER KeepBackups
    Number of backups to retain (default: 5)
.EXAMPLE
    .\Backup-Config.ps1
.EXAMPLE
    .\Backup-Config.ps1 -KeepBackups 3
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = "",
    [int]$KeepBackups = 5
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$ConfigDir = Join-Path $ProjectRoot "Config"

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $ProjectRoot "autounattend.xml"
}

if (-not (Test-Path $ConfigPath)) {
    Write-Host "Config file not found: $ConfigPath" -ForegroundColor Red
    exit 1
}

$sourceFile = Get-Item $ConfigPath
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupPath = "$ConfigPath.backup-$timestamp.xml"

Write-Host "=== GoldISO Config Backup ===" -ForegroundColor Cyan
Write-Host "Source: $ConfigPath" -ForegroundColor Gray
Write-Host "Backup: $backupPath" -ForegroundColor Gray
Write-Host ""

try {
    Copy-Item -Path $ConfigPath -Destination $backupPath -Force -ErrorAction Stop
    Write-Host "Backup created" -ForegroundColor Green
}
catch {
    Write-Host "Failed to create backup: $_" -ForegroundColor Red
    exit 1
}

$configDir = Split-Path $ConfigPath -Parent
$baseName = Split-Path $ConfigPath -Leaf
$baseName = $baseName -replace '\.xml$', ''

$backups = Get-ChildItem -Path $configDir -Filter "$baseName.backup-*.xml" | Sort-Object LastWriteTime -Descending

$removed = 0
if ($backups.Count -gt $KeepBackups) {
    $toRemove = $backups | Select-Object -Skip $KeepBackups
    
    foreach ($b in $toRemove) {
        try {
            Remove-Item -Path $b.FullName -Force -ErrorAction Stop
            $removed++
        }
        catch {
            Write-Host "Failed to remove: $($b.Name)" -ForegroundColor Yellow
        }
    }
    
    Write-Host "Removed $removed old backup(s)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Current backups:" -ForegroundColor Yellow
$backups | ForEach-Object {
    $sizeKB = [math]::Round($_.Length / 1KB, 1)
    Write-Host "  $($_.Name) (${sizeKB} KB)" -ForegroundColor Gray
}

$latest = Get-Item $ConfigPath
Write-Host ""
Write-Host "Latest: $($latest.Name) ($([math]::Round($latest.Length/1KB,1)) KB)" -ForegroundColor Green