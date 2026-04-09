[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Task creation requires output')]
param()

#region ─────────────────────────────────────────────────────────────────────────────
# Scoop Bucket Maintenance - Weekly Scheduled Task
# Checks and updates scoop buckets once per week
# ─────────────────────────────────────────────────────────────────────────────

$taskName = 'PowerShellProfile-ScoopBucketCheck'
$taskPath = '\PowerShellProfile'

$action = New-ScheduledTaskAction `
    -Execute 'pwsh.exe' `
    -Argument '-NoProfile -WindowStyle Hidden -Command "& { scoop update * 2>&1 | Out-Null; scoop cache rm * 2>&1 | Out-Null; $cacheFile = ''N:\GWIG\Config\PowerShellProfile\Cache\scoop-buckets.cache''; if (Test-Path $cacheFile) { Remove-Item $cacheFile -Force }; New-Item -Path $cacheFile -ItemType File -Force | Out-Null }"' `
    -Description 'Weekly scoop bucket and cache maintenance for PowerShell Profile'

$trigger = New-ScheduledTaskTrigger `
    -Weekly `
    -DaysOfWeek Sunday `
    -At '3:00AM'

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30) `
    -RunOnlyIfNetworkAvailable

$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType S4U `
    -RunLevel Limited

$task = New-ScheduledTask `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description 'Weekly scoop bucket and cache maintenance for PowerShell Profile'

# Register or update the task
$existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue

if ($existingTask) {
    Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false
    Write-Host "Updated scheduled task: $taskName" -ForegroundColor Yellow
}

Register-ScheduledTask `
    -TaskName $taskName `
    -TaskPath $taskPath `
    -InputObject $task `
    -Force

Write-Host "Created scheduled task: $taskName (runs weekly on Sunday at 3:00 AM)" -ForegroundColor Green

#endregion
