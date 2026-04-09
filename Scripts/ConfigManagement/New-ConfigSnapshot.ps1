#Requires -Version 5.1
<#
.SYNOPSIS
    Creates and manages GoldISO configuration snapshots.
.DESCRIPTION
    Maintains versioned snapshots of config files before major changes.
    Allows rollback to previous configurations.
.PARAMETER Action
    Action: Create, List, Restore, or Diff
.PARAMETER Name
    Snapshot name (for Create/Restore)
.PARAMETER ConfigPath
    Path to config file or directory to snapshot
.EXAMPLE
    .\New-ConfigSnapshot.ps1 -Action Create -Name "before-driver-update"
.EXAMPLE
    .\New-ConfigSnapshot.ps1 -Action List
.EXAMPLE
    .\New-ConfigSnapshot.ps1 -Action Restore -Name "before-driver-update"
.EXAMPLE
    .\New-ConfigSnapshot.ps1 -Action Diff -Name "before-driver-update"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Create", "List", "Restore", "Diff")]
    [string]$Action,

    [string]$Name = "",

    [string]$ConfigPath = ""
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$snapshotDir = Join-Path $projectRoot "Config\Snapshots"
if (-not (Test-Path $snapshotDir)) {
    New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null
}

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $projectRoot "Config"
}

function New-Snapshot {
    param([string]$SnapshotName)
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $snapshotName = if ($SnapshotName) { "$SnapshotName-$timestamp" } else { "snapshot-$timestamp" }
    $snapshotPath = Join-Path $snapshotDir $snapshotName
    
    Write-Host "Creating snapshot: $snapshotName" -ForegroundColor Cyan
    
    New-Item -ItemType Directory -Path $snapshotPath -Force | Out-Null
    
    $files = Get-ChildItem $ConfigPath -File -Recurse -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        $relativePath = $file.FullName.Replace($ConfigPath, "").TrimStart("\")
        $destPath = Join-Path $snapshotPath $relativePath
        $destDir = Split-Path $destPath -Parent
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item $file.FullName $destPath -Force
    }
    
    $metadata = @{
        Created = (Get-Date).ToString("o")
        ConfigPath = $ConfigPath
        Files = $files.Count
    } | ConvertTo-Json
    
    $metadata | Set-Content (Join-Path $snapshotPath "metadata.json") -Encoding UTF8
    
    Write-Host "Snapshot created with $($files.Count) files" -ForegroundColor Green
    return $snapshotName
}

function Get-SnapshotList {
    $snapshots = Get-ChildItem $snapshotDir -Directory | Sort-Object LastWriteTime -Descending
    if ($snapshots.Count -eq 0) {
        Write-Host "No snapshots found" -ForegroundColor Yellow
        return
    }
    Write-Host "Available Snapshots:" -ForegroundColor Cyan
    Write-Host "=" * 60
    foreach ($snap in $snapshots) {
        $metaPath = Join-Path $snap.FullName "metadata.json"
        if (Test-Path $metaPath) {
            $meta = Get-Content $metaPath -Raw | ConvertFrom-Json
            Write-Host "$($snap.Name) - $($meta.Created.Substring(0,10)) ($($meta.Files) files)" -ForegroundColor White
        } else {
            Write-Host "$($snap.Name)" -ForegroundColor White
        }
    }
}

function Restore-Snapshot {
    param([string]$SnapshotName)
    
    $snapshotPath = Join-Path $snapshotDir $SnapshotName
    if (-not (Test-Path $snapshotPath)) {
        Write-Error "Snapshot not found: $SnapshotName"
        exit 1
    }
    
    Write-Host "Restoring snapshot: $SnapshotName" -ForegroundColor Yellow
    
    $files = Get-ChildItem $snapshotPath -File -Recurse
    foreach ($file in $files) {
        $relativePath = $file.FullName.Replace($snapshotPath, "").TrimStart("\")
        $destPath = Join-Path $ConfigPath $relativePath
        $destDir = Split-Path $destPath -Parent
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item $file.FullName $destPath -Force
    }
    
    Write-Host "Snapshot restored" -ForegroundColor Green
}

function Compare-Snapshot {
    param([string]$SnapshotName)
    
    $snapshotPath = Join-Path $snapshotDir $SnapshotName
    if (-not (Test-Path $snapshotPath)) {
        Write-Error "Snapshot not found: $SnapshotName"
        exit 1
    }
    
    Write-Host "Comparing current config with: $SnapshotName" -ForegroundColor Cyan
    Write-Host "=" * 60
    
    $snapFiles = Get-ChildItem $snapshotPath -File -Recurse
    foreach ($snapFile in $snapFiles) {
        $relativePath = $snapFile.FullName.Replace($snapshotPath, "").TrimStart("\")
        $currentPath = Join-Path $ConfigPath $relativePath
        
        if (-not (Test-Path $currentPath)) {
            Write-Host "[NEW] $relativePath" -ForegroundColor Green
        } else {
            $snapHash = (Get-FileHash $snapFile.FullName -Algorithm MD5).Hash
            $currHash = (Get-FileHash $currentPath -Algorithm MD5).Hash
            if ($snapHash -ne $currHash) {
                Write-Host "[MODIFIED] $relativePath" -ForegroundColor Yellow
            }
        }
    }
}

switch ($Action) {
    "Create" { New-Snapshot -SnapshotName $Name }
    "List" { Get-SnapshotList }
    "Restore" { Restore-Snapshot -SnapshotName $Name }
    "Diff" { Compare-Snapshot -SnapshotName $Name }
}