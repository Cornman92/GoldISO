@echo off
echo ============================================
echo Creating RAM Disk
echo ============================================

:: Check if SoftPerfect RAM Disk is installed
if not exist "C:\Program Files\SoftPerfect RAM Disk\ramdiskws.exe" (
    echo ERROR: SoftPerfect RAM Disk is not installed. Skipping RAM disk creation.
    exit /b 1
)

:: Default size 8GB, can be overridden with parameter
set RAMDISK_SIZE=8192
if not "%~1"=="" set RAMDISK_SIZE=%~1

echo Creating %RAMDISK_SIZE% MB RAM disk at R:
"C:\Program Files\SoftPerfect RAM Disk\ramdiskws.exe" add -size:%RAMDISK_SIZE% -letter:R -fs:ntfs -label:"RAMDisk" -save

if errorlevel 1 (
    echo ERROR: Failed to create RAM disk
    exit /b 1
)

:: Create standard directories
echo Creating standard directories on RAM disk...
if not exist R:\Temp             mkdir R:\Temp
if not exist R:\Temp\User        mkdir R:\Temp\User
if not exist R:\Temp\System      mkdir R:\Temp\System
if not exist R:\BrowserCache     mkdir R:\BrowserCache
if not exist R:\BrowserCache\Edge    mkdir R:\BrowserCache\Edge
if not exist R:\BrowserCache\Chrome  mkdir R:\BrowserCache\Chrome
if not exist R:\BrowserCache\OperaGX mkdir R:\BrowserCache\OperaGX
if not exist R:\TempFiles        mkdir R:\TempFiles
if not exist R:\BuildCache       mkdir R:\BuildCache
if not exist R:\BuildCache\npm   mkdir R:\BuildCache\npm
if not exist R:\BuildCache\pip   mkdir R:\BuildCache\pip
if not exist R:\BuildCache\nuget mkdir R:\BuildCache\nuget

echo ============================================
echo RAM Disk Created Successfully
echo Size: %RAMDISK_SIZE% MB
echo Drive Letter: R:
echo Directories:
echo   R:\Temp\User          (User TEMP redirect)
echo   R:\Temp\System        (System TEMP redirect)
echo   R:\BrowserCache\Edge
echo   R:\BrowserCache\Chrome
echo   R:\BrowserCache\OperaGX
echo   R:\BuildCache\npm
echo   R:\BuildCache\pip
echo   R:\BuildCache\nuget
echo ============================================
exit /b 0
