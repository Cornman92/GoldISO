#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Summary of registry-only settings not covered by GPO
.DESCRIPTION
    This script documents and can apply the registry-only optimizations
    that remain after GPO migration. These settings have no GPO equivalent
    or must be applied at the registry level.
.NOTES
    Part of GoldISO GPO Migration - Registry-only optimizations
#>

[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# Import common module
Import-Module (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1") -Force

# ============================================================================
# REGISTRY-ONLY OPTIMIZATIONS
# These settings have no GPO equivalent and must be applied via registry
# ============================================================================

$RegistrySettings = @{
    # === TIMER RESOLUTION & SYSTEM CLOCK =====================================
    "TimerResolution" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Kernel"
        Name = "GlobalTimerResolutionRequests"
        Value = 1
        Type = "DWord"
        Description = "Enable high precision timer resolution requests"
    }
    
    # === NVMe OPTIMIZATIONS ==================================================
    "NVMeQueueDepth" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device"
        Name = "QueueDepth"
        Value = 2048
        Type = "DWord"
        Description = "Increase NVMe queue depth for better I/O performance"
    }
    
    # === GPU & GRAPHICS ======================================================
    "HWSchMode" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        Name = "HwSchMode"
        Value = 2
        Type = "DWord"
        Description = "Enable Hardware Accelerated GPU Scheduling (HAGS)"
    }
    "OverlayTestMode" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        Name = "OverlayTestMode"
        Value = 5
        Type = "DWord"
        Description = "Disable MPO to fix stuttering issues"
    }
    "GpuPriority" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        Name = "GpuPriority"
        Value = 8
        Type = "DWord"
        Description = "Set GPU priority for gaming"
    }
    "DirectXTearing" = @{
        Path = "HKLM:\SOFTWARE\Microsoft\DirectX"
        Name = "AllowTearing"
        Value = 1
        Type = "DWord"
        Description = "Enable DX12 tearing support for reduced latency"
    }
    
    # === CPU & SCHEDULER ====================================================
    "Win32PrioritySeparation" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
        Name = "Win32PrioritySeparation"
        Value = 38
        Type = "DWord"
        Description = "Set aggressive foreground priority (hex 0x26)"
    }
    "IRQ8Priority" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
        Name = "IRQ8Priority"
        Value = 1
        Type = "DWord"
        Description = "Set Real-Time Clock priority"
    }
    "SystemResponsiveness" = @{
        Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        Name = "SystemResponsiveness"
        Value = 0
        Type = "DWord"
        Description = "Minimize system responsiveness delay for multimedia"
    }
    "GamesPriority" = @{
        Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
        Name = "Priority"
        Value = 6
        Type = "DWord"
        Description = "Set games priority class"
    }
    "AudioScheduling" = @{
        Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio"
        Name = "SchedulingCategory"
        Value = "High"
        Type = "String"
        Description = "Set audio processing to high priority scheduling"
    }
    
    # === NETWORK OPTIMIZATIONS ==============================================
    "DNSMaxCacheTtl" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters"
        Name = "MaxCacheTtl"
        Value = 86400
        Type = "DWord"
        Description = "Increase DNS cache TTL to 24 hours"
    }
    "DNSMaxNegativeCacheTtl" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters"
        Name = "MaxNegativeCacheTtl"
        Value = 0
        Type = "DWord"
        Description = "Disable negative DNS caching"
    }
    "SMBBandwidthThrottling" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters"
        Name = "DisableBandwidthThrottling"
        Value = 1
        Type = "DWord"
        Description = "Disable SMB bandwidth throttling"
    }
    "TCPFastOpen" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
        Name = "EnableTCPFastOpen"
        Value = 1
        Type = "DWord"
        Description = "Enable TCP Fast Open for reduced connection latency"
    }
    "MaxUserPort" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
        Name = "MaxUserPort"
        Value = 65534
        Type = "DWord"
        Description = "Increase ephemeral port range"
    }
    "TcpTimedWaitDelay" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
        Name = "TcpTimedWaitDelay"
        Value = 30
        Type = "DWord"
        Description = "Reduce TCP TIME_WAIT delay to 30 seconds"
    }
    
    # === POWER & PERFORMANCE =================================================
    "PowerThrottlingOff" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"
        Name = "PowerThrottlingOff"
        Value = 1
        Type = "DWord"
        Description = "Disable CPU power throttling for consistent performance"
    }
    "CsEnabled" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Power"
        Name = "CsEnabled"
        Value = 0
        Type = "DWord"
        Description = "Disable connected standby (desktop systems)"
    }
    "CoreParking" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\0cc5b647-c1df-4637-891a-dec35c318583"
        Name = "ValueMax"
        Value = 0
        Type = "DWord"
        Description = "Disable core parking for consistent CPU availability"
    }
    
    # === MEMORY MANAGEMENT ===================================================
    "DisableCompression" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
        Name = "DisableCompression"
        Value = 1
        Type = "DWord"
        Description = "Disable memory compression for reduced latency"
    }
    "DisablePageCombining" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
        Name = "DisablePageCombining"
        Value = 1
        Type = "DWord"
        Description = "Disable page combining for consistent memory performance"
    }
    "LargeSystemCache" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
        Name = "LargeSystemCache"
        Value = 1
        Type = "DWord"
        Description = "Enable large system cache for better file performance"
    }
    "DisablePrefetcher" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"
        Name = "EnablePrefetcher"
        Value = 0
        Type = "DWord"
        Description = "Disable prefetcher (SSD-optimized systems)"
    }
    "DisableSuperfetch" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"
        Name = "EnableSuperfetch"
        Value = 0
        Type = "DWord"
        Description = "Disable Superfetch (SSD-optimized systems)"
    }
    
    # === FILE SYSTEM OPTIMIZATIONS ===========================================
    "NtfsDisableLastAccessUpdate" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
        Name = "NtfsDisableLastAccessUpdate"
        Value = 1
        Type = "DWord"
        Description = "Disable NTFS last access time updates for reduced I/O"
    }
    "NtfsDisable8dot3NameCreation" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
        Name = "NtfsDisable8dot3NameCreation"
        Value = 1
        Type = "DWord"
        Description = "Disable 8.3 filename creation for better performance"
    }
    "NtfsMemoryUsage" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
        Name = "NtfsMemoryUsage"
        Value = 2
        Type = "DWord"
        Description = "Increase NTFS memory usage for better caching"
    }
    
    # === EXPLORER TWEAKS =====================================================
    "ClassicContextMenu" = @{
        Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked"
        Name = "{e2bf9676-5f8f-435c-97eb-11607a5bedf7}"
        Value = ""
        Type = "String"
        Description = "Restore classic right-click context menu"
    }
    
    # === INPUT LATENCY =======================================================
    "KeyboardDelay" = @{
        Path = "HKCU:\Control Panel\Keyboard"
        Name = "KeyboardDelay"
        Value = "0"
        Type = "String"
        Description = "Minimize keyboard repeat delay"
    }
    "KeyboardSpeed" = @{
        Path = "HKCU:\Control Panel\Keyboard"
        Name = "KeyboardSpeed"
        Value = "31"
        Type = "String"
        Description = "Maximize keyboard repeat speed"
    }
    "MouseSensitivity" = @{
        Path = "HKCU:\Control Panel\Mouse"
        Name = "MouseSensitivity"
        Value = "10"
        Type = "String"
        Description = "Set mouse sensitivity"
    }
    "MouseSpeed" = @{
        Path = "HKCU:\Control Panel\Mouse"
        Name = "MouseSpeed"
        Value = "0"
        Type = "String"
        Description = "Disable mouse acceleration"
    }
    "ForegroundLockTimeout" = @{
        Path = "HKCU:\Control Panel\Desktop"
        Name = "ForegroundLockTimeout"
        Value = 0
        Type = "DWord"
        Description = "Prevent applications from stealing focus"
    }
    
    # === USB & HID LATENCY ===================================================
    "USBSelectiveSuspend" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Services\USB"
        Name = "DisableSelectiveSuspend"
        Value = 1
        Type = "DWord"
        Description = "Disable USB selective suspend for reduced input latency"
    }
    "HIDIdleTimeout" = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Services\HidUsb"
        Name = "IdleTimeout"
        Value = 0
        Type = "DWord"
        Description = "Disable HID idle timeout for consistent input"
    }
}

# ============================================================================
# FUNCTIONS
# ============================================================================

function Apply-RegistrySetting {
    param([string]$Name, [hashtable]$Setting, [switch]$WhatIf)
    
    try {
        # Create path if it doesn't exist
        if (-not (Test-Path $Setting.Path)) {
            if (-not $WhatIf) {
                New-Item -Path $Setting.Path -Force | Out-Null
            }
            Write-GoldISOLog -Message "Created path: $($Setting.Path)" -Level "INFO"
        }
        
        # Get current value for comparison
        $currentValue = Get-ItemProperty -Path $Setting.Path -Name $Setting.Name -ErrorAction SilentlyContinue
        $needsUpdate = $true
        
        if ($currentValue) {
            $current = $currentValue.($Setting.Name)
            $needsUpdate = $current -ne $Setting.Value
        }
        
        if ($needsUpdate) {
            if (-not $WhatIf) {
                Set-ItemProperty -Path $Setting.Path -Name $Setting.Name -Value $Setting.Value -Type $Setting.Type -Force
            }
            Write-GoldISOLog -Message "Set: $Name - $($Setting.Description)" -Level "SUCCESS"
            return $true
        } else {
            Write-GoldISOLog -Message "Skip: $Name (already set)" -Level "SKIP"
            return $false
        }
    }
    catch {
        Write-GoldISOLog -Message "Failed: $Name - $_" -Level "ERROR"
        return $false
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Registry-Only Optimizations Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verify admin rights using common module
Test-GoldISOAdmin -ExitIfNotAdmin

# Display summary
Write-Host "Total Registry-Only Settings: $($RegistrySettings.Count)" -ForegroundColor Yellow
Write-Host ""

if ($DryRun -or -not $Apply) {
    Write-Host "Mode: ANALYSIS ONLY (use -Apply to make changes)" -ForegroundColor Magenta
    Write-Host ""
    
    # Display all settings
    $RegistrySettings.GetEnumerator() | Sort-Object Name | ForEach-Object {
        $name = $_.Key
        $setting = $_.Value
        Write-Host "  $name" -ForegroundColor Cyan
        Write-Host "    Path:  $($setting.Path)" -ForegroundColor Gray
        Write-Host "    Name:  $($setting.Name)" -ForegroundColor Gray
        Write-Host "    Value: $($setting.Value)" -ForegroundColor Gray
        Write-Host "    Type:  $($setting.Type)" -ForegroundColor Gray
        Write-Host "    Desc:  $($setting.Description)" -ForegroundColor Gray
        Write-Host ""
    }
}

if ($Apply) {
    Write-Host "Mode: APPLYING REGISTRY SETTINGS" -ForegroundColor Green
    Write-Host ""
    
    $applied = 0
    $skipped = 0
    $failed = 0
    
    $RegistrySettings.GetEnumerator() | Sort-Object Name | ForEach-Object {
        $result = Apply-RegistrySetting -Name $_.Key -Setting $_.Value -WhatIf:$DryRun
        if ($result -eq $true) { $applied++ }
        elseif ($result -eq $false) { $skipped++ }
        else { $failed++ }
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Results:" -ForegroundColor Cyan
    Write-Host "  Applied: $applied" -ForegroundColor Green
    Write-Host "  Skipped (already set): $skipped" -ForegroundColor Yellow
    Write-Host "  Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Gray" })
    Write-Host "========================================" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "Note: These settings complement the GPO-based configuration." -ForegroundColor DarkGray
Write-Host "      GPO settings are applied via Apply-GPOSettings.ps1 during OOBE." -ForegroundColor DarkGray
Write-Host ""
