$scriptsPath = "C:\Users\C-Man\GoldISO\Scripts"
$excludedFiles = @(
    "Capture-Image.ps1", "shrink-and-recovery.ps1", "Apply-Image.ps1",
    "Audit-Sysprep.ps1", "Backup-Macrium.ps1", "Build-ISO-With-Settings.ps1",
    "Configure-RamDisk.ps1", "Configure-RemoteAccess.ps1", "Create-AuditShortcuts.ps1",
    "Export-Settings.ps1", "Get.ps1", "Install-PostInstallDrivers.ps1",
    "install-ramdisk.ps1", "install-usb-apps.ps1", "Invoke-Lint.ps1",
    "Setup-DriveLetters.ps1", "Start-BuildPipeline.ps1", "Build-Autounattend.ps1",
    "CompleteBuild.ps1", "New-EnhancedStandaloneBuild.ps1", "Convert-WingetExport.ps1",
    "Scan-InstalledApps.ps1"
)

$allScripts = Get-ChildItem -Path $scriptsPath -Filter "*.ps1" -Recurse
$syntaxErrors = @()

foreach ($file in $allScripts) {
    if ($excludedFiles -contains $file.Name) { continue }
    
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName, 
        [ref]$tokens, 
        [ref]$parseErrors
    )
    
    if ($parseErrors.Count -gt 0) {
        $syntaxErrors += "{0}: {1}" -f $file.Name, ($parseErrors -join ", ")
    }
}

if ($syntaxErrors.Count -eq 0) {
    Write-Host "PASS: All non-excluded scripts have valid syntax" -ForegroundColor Green
} else {
    Write-Host "FAIL: $($syntaxErrors.Count) scripts with errors:" -ForegroundColor Red
    $syntaxErrors | ForEach-Object { Write-Host $_ }
}