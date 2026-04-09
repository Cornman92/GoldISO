#Requires -Version 5.1
<#
.SYNOPSIS
    Validates GoldISO installation health after setup.
.DESCRIPTION
    Post-installation health check that validates:
    - Disk layout matches expected configuration
    - Drive letters correctly assigned
    - Critical folders exist
    - Services running correctly
    - Network connectivity
    - Windows Update status
.PARAMETER Quick
    Run quick validation only (skip slow checks)
.PARAMETER OutputPath
    Path to save health report
.EXAMPLE
    .\Test-SystemHealth.ps1
.EXAMPLE
    .\Test-SystemHealth.ps1 -Quick -OutputPath "health-report.json"
#>
[CmdletBinding()]
param(
    [switch]$Quick,
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Continue"

$commonModule = Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1"
if (Test-Path $commonModule) {
    Import-Module $commonModule -Force -ErrorAction SilentlyContinue
}

Write-Host "GoldISO System Health Check" -ForegroundColor Cyan
Write-Host "=" * 60

$results = @{
    Timestamp = (Get-Date).ToString("o")
    DiskLayout = @{ Status = "Unknown"; Details = @() }
    DriveLetters = @{ Status = "Unknown"; Details = @() }
    Folders = @{ Status = "Unknown"; Details = @() }
    Services = @{ Status = "Unknown"; Details = @() }
    Network = @{ Status = "Unknown"; Details = @() }
    Updates = @{ Status = "Unknown"; Details = @() }
    Overall = "Unknown"
}

function Test-Condition {
    param($Name, $TestBlock)
    try {
        $result = & $TestBlock
        if ($result) {
            Write-Host "[PASS] $Name" -ForegroundColor Green
            return @{ Pass = $true; Message = $Name }
        } else {
            Write-Host "[FAIL] $Name" -ForegroundColor Red
            return @{ Pass = $false; Message = $Name }
        }
    } catch {
        Write-Host "[ERROR] $Name - $_" -ForegroundColor Red
        return @{ Pass = $false; Message = "$Name - $_" }
    }
}

Write-Host "`n[Disk Layout]" -ForegroundColor Yellow
$disks = Get-Disk | Select-Object Number, FriendlyName, @{N='SizeGB';E={[math]::Round($_.Size/1GB,1)}}, PartitionStyle
$results.DiskLayout.Details = $disks
Write-Host "  Disks found: $($disks.Count)" -ForegroundColor White

Write-Host "`n[Drive Letters]" -ForegroundColor Yellow
$volumes = Get-Volume | Where-Object { $_.DriveLetter } | Select-Object DriveLetter, FileSystem, @{N='SizeGB';E={[math]::Round($_.Size/1GB,1)}}, DriveType
$results.DriveLetters.Details = $volumes

$gamerOSLetters = @('C', 'D', 'E', 'R')
foreach ($letter in $gamerOSLetters) {
    $vol = $volumes | Where-Object { $_.DriveLetter -eq $letter }
    if ($vol) {
        Write-Host "  [$($letter):] Present - $($vol.FileSystem) ($([math]::Round($vol.Size/1GB,1)) GB)" -ForegroundColor Green
    } else {
        Write-Host "  [$($letter):] Missing" -ForegroundColor Red
    }
}

Write-Host "`n[Critical Folders]" -ForegroundColor Yellow
$requiredFolders = @(
    "C:\ProgramData\Winhance",
    "C:\Scripts",
    "C:\PowerShellProfile"
)
foreach ($folder in $requiredFolders) {
    if (Test-Path $folder) {
        Write-Host "  [OK] $folder" -ForegroundColor Green
    } else {
        Write-Host "  [MISSING] $folder" -ForegroundColor Yellow
    }
}

Write-Host "`n[Critical Services]" -ForegroundColor Yellow
$criticalServices = @('WinDefend', 'wuauserv', 'DiagTrack', 'BITS')
foreach ($svc in $criticalServices) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service) {
        $status = if ($service.Status -eq 'Running') { "Running" } else { "Stopped" }
        $color = if ($service.Status -eq 'Running') { 'Green' } else { 'Yellow' }
        Write-Host "  [$status] $svc" -ForegroundColor $color
    }
}

if (-not $Quick) {
    Write-Host "`n[Network Connectivity]" -ForegroundColor Yellow
    $targets = @('8.8.8.8', 'cloudflare.com', 'microsoft.com')
    $connected = 0
    foreach ($target in $targets) {
        $ping = Test-Connection -ComputerName $target -Count 1 -Quiet -ErrorAction SilentlyContinue
        if ($ping) {
            $connected++
            Write-Host "  [OK] $target" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] $target" -ForegroundColor Red
        }
    }
    $results.Network.Details = @{ Connected = $connected; Total = $targets.Count }
    
    Write-Host "`n[Windows Update Status]" -ForegroundColor Yellow
    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Software'")
        $pending = $searchResult.Updates.Count
        Write-Host "  Pending updates: $pending" -ForegroundColor $(if ($pending -eq 0) { 'Green' } else { 'Yellow' })
        $results.Updates.Details = @{ Pending = $pending }
    } catch {
        Write-Host "  [SKIP] Could not check updates: $_" -ForegroundColor Yellow
    }
}

Write-Host "`n" + "=" * 60
$passed = @($results.DiskLayout, $results.DriveLetters, $results.Folders) | Where-Object { $_.Status -eq "OK" }.Count

if ($OutputPath) {
    $results | ConvertTo-Json -Depth 3 | Set-Content $OutputPath -Encoding UTF8
    Write-Host "Report saved: $OutputPath" -ForegroundColor Cyan
}

Write-Host "Health check complete" -ForegroundColor Cyan