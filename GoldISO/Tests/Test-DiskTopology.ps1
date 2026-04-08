#Requires -Version 5.1
<#
.SYNOPSIS
    Validate disk topology before deployment
.DESCRIPTION
    Verifies target machine matches expected disk layout:
    - Expected disk count
    - Unallocated space on target disk
    - Partition configuration
.PARAMETER ExpectedDiskCount
    Expected number of disks (default: 3)
.PARAMETER TargetDiskNumber
    Target disk number for Windows (default: 2)
.PARAMETER ExpectedUnallocatedGB
    Expected unallocated space in GB on target disk (default: 90)
.EXAMPLE
    .\Test-DiskTopology.ps1
.EXAMPLE
    .\Test-DiskTopology.ps1 -ExpectedDiskCount 2 -TargetDiskNumber 1
#>
[CmdletBinding()]
param(
    [int]$ExpectedDiskCount = 3,
    [int]$TargetDiskNumber = 2,
    [int]$ExpectedUnallocatedGB = 90
)

$ErrorActionPreference = "Stop"

Write-Host "=== GoldISO Disk Topology Validation ===" -ForegroundColor Cyan
Write-Host ""

$disks = Get-Disk | Where-Object { $_.OperationalStatus -eq "Online" }
$diskCount = $disks.Count

Write-Host "Disk Count: $diskCount (expected: $ExpectedDiskCount)" -ForegroundColor $(if ($diskCount -ge $ExpectedDiskCount) { "Green" } else { "Yellow" })

if ($diskCount -lt $ExpectedDiskCount) {
    Write-Host "Warning: Fewer disks than expected" -ForegroundColor Yellow
}

$targetDisk = $disks | Where-Object { $_.Number -eq $TargetDiskNumber } | Select-Object -First 1

if (-not $targetDisk) {
    Write-Host "Target disk $TargetDiskNumber not found" -ForegroundColor Red
    Write-Host ""
    Write-Host "Validation: FAILED" -ForegroundColor Red
    exit 1
}

$unallocatedGB = [math]::Round($targetDisk.AllocatedSize / 1GB, 0)
$partitionCount = (Get-Partition -DiskNumber $TargetDiskNumber -ErrorAction SilentlyContinue).Count

Write-Host ""
Write-Host "Target Disk ($TargetDiskNumber):" -ForegroundColor Yellow
Write-Host "  Allocated: $unallocatedGB GB"
Write-Host "  Partitions: $partitionCount"

$allPassed = $true

if ($unallocatedGB -ge $ExpectedUnallocatedGB) {
    Write-Host "  Unallocated: PASS ($unallocatedGB GB >= $ExpectedUnallocatedGB GB)" -ForegroundColor Green
}
else {
    Write-Host "  Unallocated: FAIL ($unallocatedGB GB < $ExpectedUnallocatedGB GB)" -ForegroundColor Red
    $allPassed = $false
}

if ($partitionCount -ge 2) {
    Write-Host "  Partitions: PASS" -ForegroundColor Green
}
else {
    Write-Host "  Partitions: FAIL (expected >= 2)" -ForegroundColor Red
    $allPassed = $false
}

Write-Host ""
Write-Host "Disk Details:" -ForegroundColor Yellow

$disks | Where-Object { $_.Number -le 2 } | ForEach-Object {
    $sizeGB = [math]::Round($_.Size / 1GB, 0)
    $freeGB = [math]::Round($_.Size / 1GB, 0)
    
    Write-Host "  Disk $($_.Number): $($_.FriendlyName) - ${sizeGB} GB" -ForegroundColor Gray
    
    $partitions = Get-Partition -DiskNumber $_.Number -ErrorAction SilentlyContinue
    foreach ($part in $partitions) {
        $partSize = if ($part.Size) { [math]::Round($part.Size / 1GB, 1) } else { 0 }
        $driveLetter = if ($part.DriveLetter) { "$($part.DriveLetter):" } else { "-" }
        $type = if ($part.PartitionStyle) { $part.PartitionStyle } else { "RAW" }
        
        Write-Host "    $driveLetter ${partSize}GB ($type)" -ForegroundColor Gray
    }
}

Write-Host ""
if ($allPassed) {
    Write-Host "Validation: PASSED" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "Validation: FAILED" -ForegroundColor Red
    exit 1
}