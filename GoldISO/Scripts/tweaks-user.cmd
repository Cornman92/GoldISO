@echo off
echo ============================================
echo Applying USER-Level Tweaks (HKCU)
echo ============================================
echo Running as: %USERNAME%
echo Date: %date% %time%
echo ============================================

:: ------------------------------------------------
:: GAME MODE
:: ------------------------------------------------
echo Ensuring Game Mode is enabled
reg add "HKCU\Software\Microsoft\GameBar" /v AllowAutoGameMode /t REG_DWORD /d 1 /f
reg add "HKCU\Software\Microsoft\GameBar" /v AutoGameModeEnabled /t REG_DWORD /d 1 /f

echo Disabling Game Bar overlay only
reg add "HKCU\Software\Microsoft\GameBar" /v ShowStartupPanel /t REG_DWORD /d 0 /f
reg add "HKCU\Software\Microsoft\GameBar" /v UseNexusForGameBarEnabled /t REG_DWORD /d 0 /f

:: ------------------------------------------------
:: INPUT LATENCY TWEAKS
:: ------------------------------------------------
echo Reducing keyboard input delay
reg add "HKCU\Control Panel\Keyboard" /v KeyboardDelay /t REG_SZ /d 0 /f
reg add "HKCU\Control Panel\Keyboard" /v KeyboardSpeed /t REG_SZ /d 31 /f

echo Improving mouse responsiveness
reg add "HKCU\Control Panel\Mouse" /v MouseSensitivity /t REG_SZ /d 10 /f
reg add "HKCU\Control Panel\Mouse" /v MouseSpeed /t REG_SZ /d 0 /f
reg add "HKCU\Control Panel\Mouse" /v MouseThreshold1 /t REG_SZ /d 0 /f
reg add "HKCU\Control Panel\Mouse" /v MouseThreshold2 /t REG_SZ /d 0 /f

echo Preventing background apps from stealing focus
reg add "HKCU\Control Panel\Desktop" /v ForegroundLockTimeout /t REG_DWORD /d 0 /f

:: ------------------------------------------------
:: USB + HID LATENCY TUNING
:: ------------------------------------------------
echo Reducing USB selective suspend
reg add "HKLM\SYSTEM\CurrentControlSet\Services\USB" /v DisableSelectiveSuspend /t REG_DWORD /d 1 /f

echo Improving HID latency
reg add "HKLM\SYSTEM\CurrentControlSet\Services\HidUsb" /v IdleTimeout /t REG_DWORD /d 0 /f

:: ------------------------------------------------
:: EXPLORER + UI TWEAKS (HKCU)
:: ------------------------------------------------
echo Showing file extensions and hidden files
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v HideFileExt /t REG_DWORD /d 0 /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Hidden /t REG_DWORD /d 1 /f

echo Disabling recent files in Quick Access
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer" /v ShowRecent /t REG_DWORD /d 0 /f

echo Speeding up menu animations
reg add "HKCU\Control Panel\Desktop" /v MenuShowDelay /t REG_SZ /d 0 /f

echo Disabling transparency effects
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v EnableTransparency /t REG_DWORD /d 0 /f

echo Disabling background apps
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" /v GlobalUserDisabled /t REG_DWORD /d 1 /f

echo Disabling Snap Assist
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v SnapAssist /t REG_DWORD /d 0 /f

echo Disabling Aero Peek
reg add "HKCU\Control Panel\Desktop" /v DisableAeroPeek /t REG_DWORD /d 1 /f

:: ------------------------------------------------
:: PRIVACY TWEAKS (HKCU)
:: ------------------------------------------------
echo Disabling advertising ID
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v Enabled /t REG_DWORD /d 0 /f

:: ------------------------------------------------
:: USER TEMP to R:\Temp (if RAM disk exists)
:: ------------------------------------------------
if exist R:\ (
    echo Setting user TEMP to R:\Temp
    reg add "HKCU\Environment" /v TEMP /t REG_EXPAND_SZ /d "R:\Temp" /f
    reg add "HKCU\Environment" /v TMP /t REG_EXPAND_SZ /d "R:\Temp" /f
)

echo ============================================
echo USER TWEAKS APPLIED SUCCESSFULLY
echo ============================================
exit /b 0
