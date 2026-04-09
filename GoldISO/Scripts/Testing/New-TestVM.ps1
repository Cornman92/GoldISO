#Requires -Version 5.1
<#
.SYNOPSIS
    Create Hyper-V test VM for GoldISO testing
.DESCRIPTION
    Creates a Generation 2 (UEFI) Hyper-V VM with:
    - 100GB dynamic VHDX
    - 4 vCPUs, 8GB RAM (dynamic)
    - Network: Default Switch
    - Boots from GoldISO ISO
.PARAMETER VMName
    Name of the VM (default: GoldISO-Test)
.PARAMETER VHDSizeGB
    Size of the VHDX in GB (default: 100)
.PARAMETER MemoryGB
    RAM in GB (default: 8)
.PARAMETER CPUs
    Number of vCPUs (default: 4)
.PARAMETER ISOPath
    Path to the ISO to boot from (auto-detected if not provided)
.PARAMETER SwitchName
    Virtual switch name (default: "Default Switch")
.EXAMPLE
    .\New-TestVM.ps1
.EXAMPLE
    .\New-TestVM.ps1 -VMName "MyTestVM" -VHDSizeGB 50
#>
[CmdletBinding()]
param(
    [string]$VMName = "GoldISO-Test",
    [int]$VHDSizeGB = 100,
    [int]$MemoryGB = 8,
    [int]$CPUs = 4,
    [string]$ISOPath = "",
    [string]$SwitchName = "Default Switch"
)

$ErrorActionPreference = "Stop"

function Write-VMLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    switch ($Level) {
        "ERROR" { Write-Host $entry -ForegroundColor Red }
        "SUCCESS" { Write-Host $entry -ForegroundColor Green }
        "WARNING" { Write-Host $entry -ForegroundColor Yellow }
        default { Write-Host $entry }
    }
}

function Test-HyperV {
    Write-VMLog "Checking Hyper-V availability..."
    
    $hyperv = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction SilentlyContinue
    if (-not $hyperv -or $hyperv.State -ne "Enabled") {
        Write-VMLog "ERROR: Hyper-V is not enabled. Enable it in Windows Features." "ERROR"
        Write-VMLog "Run: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All" "ERROR"
        exit 1
    }
    
    $hypervService = Get-Service -Name vmms -ErrorAction SilentlyContinue
    if (-not $hypervService -or $hypervService.Status -ne "Running") {
        Write-VMLog "ERROR: Hyper-V Virtual Machine Management service is not running." "ERROR"
        exit 1
    }
    
    Write-VMLog "Hyper-V is available" "SUCCESS"
}

function Get-DefaultSwitch {
    Write-VMLog "Finding virtual switch..."
    
    $switch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
    if (-not $switch) {
        # Try to find any available switch
        $switches = Get-VMSwitch -ErrorAction SilentlyContinue | Where-Object { $_.SwitchType -eq "External" }
        if ($switches) {
            $switch = $switches[0]
            Write-VMLog "Using switch: $($switch.Name)" "WARNING"
        } else {
            Write-VMLog "ERROR: No virtual switch found. Create one first in Hyper-V Manager." "ERROR"
            exit 1
        }
    }
    
    Write-VMLog "Using switch: $($switch.Name)" "SUCCESS"
    return $switch.Name
}

function New-TestVM {
    param(
        [string]$Name,
        [int]$VHDSize,
        [int]$Memory,
        [int]$CPUCount,
        [string]$Switch,
        [string]$ISO
    )
    
    $vmPath = "C:\VMs\$Name"
    $vhdxPath = "$vmPath\$Name.vhdx"
    
    Write-VMLog "=========================================="
    Write-VMLog "Creating VM: $Name"
    Write-VMLog "=========================================="
    
    # Check if VM already exists
    $existingVM = Get-VM -Name $Name -ErrorAction SilentlyContinue
    if ($existingVM) {
        Write-VMLog "VM '$Name' already exists. Removing..." "WARNING"
        Stop-VM -Name $Name -Force -ErrorAction SilentlyContinue
        Remove-VM -Name $Name -Force -ErrorAction SilentlyContinue
    }
    
    # Create VM directory
    if (-not (Test-Path $vmPath)) {
        New-Item -ItemType Directory -Path $vmPath -Force | Out-Null
    }
    
    Write-VMLog "Creating Generation 2 VM..."
    New-VM -Name $Name `
           -Generation 2 `
           -MemoryStartupBytes ($Memory * 1GB) `
           -Path $vmPath `
           -SwitchName $Switch | Out-Null
    
    Set-VM -Name $Name -ProcessorCount $CPUCount -DynamicMemoryEnabled $true -MemoryMinimumBytes (512MB) -MemoryMaximumBytes ($Memory * 1GB) | Out-Null
    
    Write-VMLog "Creating VHDX ($VHDSize GB)..."
    New-VHD -Path $vhdxPath -SizeBytes ($VHDSize * 1GB) -Dynamic | Out-Null
    Add-VMHardDiskDrive -VMName $Name -Path $vhdxPath -ControllerType SCSI | Out-Null
    
    # Set DVD drive and ISO
    if ($ISO) {
        Set-VMDvdDrive -VMName $Name -Path $ISO | Out-Null
        Write-VMLog "Attached ISO: $ISO" "SUCCESS"
    } else {
        Write-VMLog "No ISO attached (specify with -ISOPath)" "WARNING"
    }
    
    # Disable Secure Boot (required for custom/unsigned ISOs)
    Set-VMFirmware -VMName $Name -EnableSecureBoot Off | Out-Null
    Write-VMLog "Secure Boot disabled (required for custom ISO)" "SUCCESS"

    # Set boot order: DVD first, then VHDX
    $dvd  = Get-VMDvdDrive  -VMName $Name
    $disk = Get-VMHardDiskDrive -VMName $Name
    if ($dvd -and $disk) {
        Set-VMFirmware -VMName $Name -BootOrder $dvd, $disk | Out-Null
        Write-VMLog "Boot order: DVD -> VHDX" "SUCCESS"
    }

    Write-VMLog "=========================================="
    Write-VMLog "VM Created Successfully" "SUCCESS"
    Write-VMLog "  Name: $Name"
    Write-VMLog "  CPUs: $CPUCount (dynamic memory: 512MB - ${Memory}GB)"
    Write-VMLog "  VHDX: $vhdxPath ($VHDSize GB dynamic)"
    Write-VMLog "  Switch: $Switch"
    if ($ISO) { Write-VMLog "  ISO: $ISO" }
    Write-VMLog "=========================================="
}

function Start-TestVM {
    param([string]$Name)
    Write-VMLog "Starting VM: $Name"
    Start-VM -Name $Name
    Write-VMLog "VM started" "SUCCESS"
}

# ==========================================
# MAIN EXECUTION
# ==========================================

Write-Host "=========================================="
Write-Host "GoldISO Test VM Creation"
Write-Host "=========================================="
Write-Host ""

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-VMLog "ERROR: This script must be run as Administrator." "ERROR"
    exit 1
}

# Check Hyper-V
Test-HyperV

# Auto-detect ISO if not provided
if (-not $ISOPath) {
    $projectRoot = Split-Path $PSScriptRoot -Parent
    $possibleISOs = @(
        Join-Path $projectRoot "GamerOS-Win11x64Pro25H2.iso"
        Join-Path $projectRoot "GamerOS_Win11_25H2.iso"
    )
    foreach ($iso in $possibleISOs) {
        if (Test-Path $iso) {
            $ISOPath = $iso
            break
        }
    }
    if (-not $ISOPath) {
        Write-VMLog "ISO not found. Building ISO first..." "WARNING"
        Write-VMLog "Run: .\Build-GoldISO.ps1" "INFO"
    }
}

# Get virtual switch
$switch = Get-DefaultSwitch

# Create VM
New-TestVM -Name $VMName `
           -VHDSize $VHDSizeGB `
           -Memory $MemoryGB `
           -CPUCount $CPUs `
           -Switch $switch `
           -ISO $ISOPath

# Ask to start
Write-Host ""
$startNow = Read-Host "Start VM now? (Y/N)"
if ($startNow -eq "Y" -or $startNow -eq "y") {
    Start-TestVM -Name $VMName
    Write-VMLog "VM is starting. Connect with: VMConnect $env:COMPUTERNAME $VMName" "INFO"
} else {
    Write-VMLog "To start manually: Start-VM -Name $VMName" "INFO"
    Write-VMLog "To connect: VMConnect $env:COMPUTERNAME $VMName" "INFO"
}