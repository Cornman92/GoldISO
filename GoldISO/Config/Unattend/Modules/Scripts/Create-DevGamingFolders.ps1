#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Creates Dev and Gaming folders during OOBE for SingleDisk-DevGaming layout.
.DESCRIPTION
    Creates C:\Dev and C:\Gaming folders with appropriate permissions.
    Run as a FirstLogonCommand during Windows setup.
.EXAMPLE
    .\Create-DevGamingFolders.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Define folders to create
$folders = @(
    @{ Path = 'C:\Dev'; Description = 'Development projects and apps' },
    @{ Path = 'C:\Gaming'; Description = 'Games and game launchers (Steam, Battle.net, Epic, etc.)' }
)

foreach ($folder in $folders) {
    $folderPath = $folder.Path
    $description = $folder.Description

    try {
        if (-not (Test-Path $folderPath)) {
            New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
            Write-Host "Created folder: $folderPath" -ForegroundColor Green
        } else {
            Write-Host "Folder already exists: $folderPath" -ForegroundColor Yellow
        }

        # Set permissions - grant Users modify access
        $acl = Get-Acl $folderPath

        # Check if rule already exists
        $existingRules = $acl.GetAccessRules($true, $true, [System.Security.Principal.NTAccount])
        $ruleExists = $false

        foreach ($rule in $existingRules) {
            if ($rule.IdentityReference -eq "BUILTIN\Users" -and $rule.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Modify) {
                $ruleExists = $true
                break
            }
        }

        if (-not $ruleExists) {
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "BUILTIN\Users",
                "Modify",
                "ContainerInherit,ObjectInherit",
                "None",
                "Allow"
            )
            $acl.AddAccessRule($rule)
            Set-Acl $folderPath $acl
            Write-Host "Set permissions on: $folderPath" -ForegroundColor Green
        }

        # Create a descriptive info file
        $readmePath = Join-Path $folderPath "README.txt"
        if (-not (Test-Path $readmePath)) {
            $readmeContent = @"
$description

Created by GoldISO SingleDisk-DevGaming setup.

For more information, see: https://github.com/Cornman92/GoldISO
"@
            Set-Content -Path $readmePath -Value $readmeContent -Encoding UTF8
        }
    }
    catch {
        Write-Host "Error processing $folderPath`: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "Dev and Gaming folders ready." -ForegroundColor Green
