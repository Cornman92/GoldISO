#Requires -Version 5.1
<#
.SYNOPSIS
    Verifies ISO integrity using SHA256 checksum.
.DESCRIPTION
    Compares an ISO file against its .sha256 checksum file,
    or generates a checksum if none exists.
.PARAMETER ISOPath
    Path to the ISO file to verify.
.PARAMETER ChecksumPath
    Path to the .sha256 checksum file (auto-detected if not provided).
.PARAMETER Generate
    Generate a new checksum file instead of verifying.
.EXAMPLE
    .\Verify-ISO.ps1 -ISOPath "GamerOS-Win11x64Pro25H2.iso"
.EXAMPLE
    .\Verify-ISO.ps1 -ISOPath "GamerOS-Win11x64Pro25H2.iso" -Generate
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ISOPath,

    [string]$ChecksumPath = "",

    [switch]$Generate
)

$ErrorActionPreference = "Stop"

if (Test-Path (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1")) {
    Import-Module (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1") -Force
}

if (-not (Test-Path $ISOPath)) {
    Write-Error "ISO not found: $ISOPath"
    exit 1
}

$isoSizeGB = [math]::Round((Get-Item $ISOPath).Length / 1GB, 2)
Write-Host "ISO: $ISOPath ($isoSizeGB GB)" -ForegroundColor Cyan

if ($Generate) {
    $checksumPath = $ISOPath + ".sha256"
    Write-Host "Generating SHA256 checksum..." -ForegroundColor Yellow
    $hash = Get-FileHash $ISOPath -Algorithm SHA256
    "$($hash.Hash)  $([System.IO.Path]::GetFileName($ISOPath))" | Set-Content $checksumPath -Encoding UTF8
    Write-Host "Checksum saved: $checksumPath" -ForegroundColor Green
    Write-Host "SHA256: $($hash.Hash)" -ForegroundColor Gray
    exit 0
}

if (-not $ChecksumPath) {
    $ChecksumPath = $ISOPath + ".sha256"
}

if (-not (Test-Path $ChecksumPath)) {
    Write-Warning "Checksum file not found: $ChecksumPath"
    Write-Host "Use -Generate to create a checksum file" -ForegroundColor Yellow
    exit 1
}

Write-Host "Verifying against: $ChecksumPath" -ForegroundColor Yellow
$storedHash = (Get-Content $ChecksumPath -Raw).Split(' ')[0].Trim()
$actualHash = (Get-FileHash $ISOPath -Algorithm SHA256).Hash

Write-Host "Stored:  $storedHash" -ForegroundColor Gray
Write-Host "Actual:  $actualHash" -ForegroundColor Gray

if ($storedHash -eq $actualHash) {
    Write-Host "PASS: ISO integrity verified" -ForegroundColor Green
    exit 0
} else {
    Write-Host "FAIL: Hash mismatch - ISO may be corrupted" -ForegroundColor Red
    exit 1
}
