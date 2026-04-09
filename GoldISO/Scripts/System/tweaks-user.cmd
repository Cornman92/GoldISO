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
:: NOTE: Game Mode and Game Bar settings are now configured via Group Policy (User-Policy.txt)
:: See: Config\GPO\User-Policy.txt

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
:: NOTE: The following Explorer and UI settings are now configured via Group Policy (User-Policy.txt):
:: - HideFileExt (Show file extensions)
:: - Hidden (Show hidden files)
:: - ShowRecent (Recent files in Quick Access)
:: - MenuShowDelay (Menu animation speed)
:: - EnableTransparency (Transparency effects)
:: - GlobalUserDisabled (Background apps)
:: - SnapAssist (Snap Assist)
:: - DisableAeroPeek (Aero Peek)
:: See: Config\GPO\User-Policy.txt

:: ------------------------------------------------
:: PRIVACY TWEAKS (HKCU)
:: ------------------------------------------------
:: NOTE: Privacy settings are now configured via Group Policy (User-Policy.txt):
:: - AdvertisingInfo\Enabled (Advertising ID)
:: - ContentDeliveryManager settings (Suggestions, tips)
:: See: Config\GPO\User-Policy.txt

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
