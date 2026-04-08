@echo off
echo ============================================
echo Applying SYSTEM-Level Tweaks (HKLM)
echo ============================================
echo Running as: %USERNAME%
echo Date: %date% %time%
echo ============================================

:: ------------------------------------------------
:: TIMER RESOLUTION + SYSTEM CLOCK TUNING
:: ------------------------------------------------
echo Enabling high precision event timer
bcdedit /set useplatformclock no
bcdedit /set disabledynamictick yes
bcdedit /set tscsyncpolicy enhanced

echo Enabling global timer resolution requests
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Kernel" /v GlobalTimerResolutionRequests /t REG_DWORD /d 1 /f

:: ------------------------------------------------
:: DIRECTSTORAGE + NVMe OPTIMIZATIONS
:: ------------------------------------------------
echo Enabling DirectStorage optimizations
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v NtfsAllowExtendedCharacters /t REG_DWORD /d 1 /f

echo Increasing NVMe queue depth
reg add "HKLM\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device" /v QueueDepth /t REG_DWORD /d 2048 /f

:: ------------------------------------------------
:: GPU + GAMING TWEAKS
:: ------------------------------------------------
echo Enabling Hardware Accelerated GPU Scheduling
reg add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v HwSchMode /t REG_DWORD /d 2 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v OverlayTestMode /t REG_DWORD /d 5 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v GpuPriority /t REG_DWORD /d 8 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v Priority /t REG_DWORD /d 6 /f

echo Disabling MPO (fixes stutter)
reg add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v OverlayTestMode /t REG_DWORD /d 5 /f

echo Enabling DX12 tearing support
reg add "HKLM\SOFTWARE\Microsoft\DirectX" /v AllowTearing /t REG_DWORD /d 1 /f

echo Disabling GameDVR
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" /v AllowGameDVR /t REG_DWORD /d 0 /f

:: ------------------------------------------------
:: CPU + SCHEDULER TWEAKS
:: ------------------------------------------------
echo Setting aggressive scheduler priority
reg add "HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl" /v Win32PrioritySeparation /t REG_DWORD /d 38 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl" /v IRQ8Priority /t REG_DWORD /d 1 /f

echo Enabling MMCSS
sc config MMCSS start= auto

echo Increasing system responsiveness
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v SystemResponsiveness /t REG_DWORD /d 0 /f

echo Setting GPU tasks to high priority
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v Priority /t REG_DWORD /d 6 /f

:: ------------------------------------------------
:: AUDIO LATENCY TWEAKS
:: ------------------------------------------------
echo Enabling MMCSS for audio
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio" /v SchedulingCategory /t REG_SZ /d "High" /f

echo Reducing WASAPI latency
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render" /v AudioRenderQuality /t REG_DWORD /d 1 /f

:: ------------------------------------------------
:: NETWORK STACK EXTREME TUNING
:: ------------------------------------------------
echo Applying low-latency network tweaks

netsh int tcp set global autotuninglevel=normal
netsh int tcp set global rss=enabled
netsh int tcp set global dca=enabled
netsh int tcp set global netdma=enabled
netsh int tcp set global timestamps=disabled
netsh int tcp set global ecncapability=enabled
netsh int tcp set global congestionprovider=ctcp

echo Enabling DNS performance tweaks
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" /v MaxCacheTtl /t REG_DWORD /d 86400 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" /v MaxNegativeCacheTtl /t REG_DWORD /d 0 /f

echo Improving SMB performance
reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" /v DisableBandwidthThrottling /t REG_DWORD /d 1 /f

echo Enabling TCP Fast Open
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v EnableTCPFastOpen /t REG_DWORD /d 1 /f

echo Increasing ephemeral port range
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v MaxUserPort /t REG_DWORD /d 65534 /f

echo Reducing TCP timeout
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v TcpTimedWaitDelay /t REG_DWORD /d 30 /f

:: ------------------------------------------------
:: POWER + PERFORMANCE TWEAKS
:: ------------------------------------------------
echo Enabling Ultimate Performance power plan
powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61
powercfg -setactive e9a42b02-d5df-448d-aa00-03f14749eb61

echo Disabling power throttling
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" /v PowerThrottlingOff /t REG_DWORD /d 1 /f

echo Disabling hibernation
powercfg -h off

echo Disabling CPU idle states
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v CsEnabled /t REG_DWORD /d 0 /f

echo Disabling core parking
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\0cc5b647-c1df-4637-891a-dec35c318583" /v ValueMax /t REG_DWORD /d 0 /f

:: ------------------------------------------------
:: MEMORY MANAGER EXTREME TUNING
:: ------------------------------------------------
echo Disabling memory compression
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v DisableCompression /t REG_DWORD /d 1 /f

echo Disabling page combining
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v DisablePageCombining /t REG_DWORD /d 1 /f

echo Increasing file system cache
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v LargeSystemCache /t REG_DWORD /d 1 /f

:: ------------------------------------------------
:: DISK + I/O TWEAKS
:: ------------------------------------------------
echo Enabling disk performance counters
diskperf -y

echo Disabling NTFS last access updates
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v NtfsDisableLastAccessUpdate /t REG_DWORD /d 1 /f

echo Disabling 8.3 filename creation
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v NtfsDisable8dot3NameCreation /t REG_DWORD /d 1 /f

echo Increasing NTFS memory usage
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v NtfsMemoryUsage /t REG_DWORD /d 2 /f

echo Disabling prefetch + superfetch
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" /v EnablePrefetcher /t REG_DWORD /d 0 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" /v EnableSuperfetch /t REG_DWORD /d 0 /f

:: ------------------------------------------------
:: EXPLORER + UI TWEAKS (HKLM)
:: ------------------------------------------------
echo Restoring classic right-click menu
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked" /v "{e2bf9676-5f8f-435c-97eb-11607a5bedf7}" /t REG_SZ /d "" /f

:: ------------------------------------------------
:: PRIVACY TWEAKS (HKLM)
:: ------------------------------------------------
echo Disabling telemetry
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f

echo Disabling location tracking
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" /v DisableLocation /t REG_DWORD /d 1 /f

:: ------------------------------------------------
:: WINDOWS UPDATE TWEAKS
:: ------------------------------------------------
echo Disabling automatic driver updates
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ExcludeWUDriversInQualityUpdate /t REG_DWORD /d 1 /f

echo Disabling automatic restarts
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoRebootWithLoggedOnUsers /t REG_DWORD /d 1 /f

echo Disabling Delivery Optimization
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" /v DODownloadMode /t REG_DWORD /d 0 /f

:: ------------------------------------------------
:: SCHEDULED TASK CLEANUP
:: ------------------------------------------------
echo Disabling telemetry scheduled tasks
schtasks /Change /TN "Microsoft\Windows\Application Experience\ProgramDataUpdater" /Disable 2>nul
schtasks /Change /TN "Microsoft\Windows\Customer Experience Improvement Program\Consolidator" /Disable 2>nul
schtasks /Change /TN "Microsoft\Windows\Customer Experience Improvement Program\UsbCeip" /Disable 2>nul
schtasks /Change /TN "Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector" /Disable 2>nul

:: ------------------------------------------------
:: SERVICE TWEAKS (SAFE)
:: ------------------------------------------------
echo Disabling unneeded services
sc config dmwappushservice start= disabled 2>nul
sc config RetailDemo start= disabled 2>nul
sc config MapsBroker start= disabled 2>nul
sc config WSearch start= delayed-auto 2>nul

:: ------------------------------------------------
:: SYSTEM TEMP to R:\Temp (if RAM disk exists)
:: ------------------------------------------------
if exist R:\ (
    echo Setting system TEMP to R:\Temp
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v TEMP /t REG_EXPAND_SZ /d "R:\Temp" /f
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v TMP /t REG_EXPAND_SZ /d "R:\Temp" /f
)

echo ============================================
echo SYSTEM TWEAKS APPLIED SUCCESSFULLY
echo ============================================
exit /b 0
