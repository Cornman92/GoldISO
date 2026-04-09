#Requires -Version 5.1
<#
.SYNOPSIS
    Generates Ventoy plugin configuration for GoldISO.
.DESCRIPTION
    Creates Ventoy plugin files for:
    - Auto-installation (autounattend.xml)
    - Theme configuration
    - Persistence configuration
    - Secure boot support
.PARAMETER OutputPath
    Path to output Ventoy plugin directory. Default: Ventoy in project root.
.PARAMETER Theme
    Ventoy theme to use (default, dark, light).
.PARAMETER Persistence
    Enable persistence with size in MB.
.EXAMPLE
    .\New-VentoyPlugin.ps1
.EXAMPLE
    .\New-VentoyPlugin.ps1 -Theme dark -Persistence 2048
#>
[CmdletBinding()]
param(
    [string]$OutputPath = "",
    [ValidateSet("default", "dark", "light")]
    [string]$Theme = "default",
    [int]$Persistence = 0
)

$ErrorActionPreference = "Stop"

if (Test-Path (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1")) {
    Import-Module (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1") -Force
}

$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $OutputPath) {
    $OutputPath = Join-Path $projectRoot "Ventoy"
}

Write-Host "Generating Ventoy plugins at: $OutputPath" -ForegroundColor Cyan

New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

$ventoyJson = @{
    "theme" = @{
        "file" = "theme/$Theme/theme.txt"
        "background" = "theme/$Theme/background.jpg"
        "cursor" = "theme/$Theme/cursor.png"
        "css" = "theme/$Theme/style.css"
    }
} | ConvertTo-Json -Depth 3

$ventoyJson | Set-Content (Join-Path $OutputPath "ventoy.json") -Encoding UTF8
Write-Host "  ventoy.json created" -ForegroundColor Green

$autounattend = @{
    "image" = @(
        @{
            "image" = "/GamerOS-Win11x64Pro25H2.iso"
            "template" = "/ventoy/script/autounattend.xml"
        }
    )
} | ConvertTo-Json -Depth 3

$autounattend | Set-Content (Join-Path $OutputPath "autounattend.json") -Encoding UTF8
Write-Host "  autounattend.json created" -ForegroundColor Green

if ($Persistence -gt 0) {
    $persistJson = @{
        "persistence" = @(
            @{
                "image" = "/GamerOS-Win11x64Pro25H2.iso"
                "persistence" = "/ventoy/persistence.img"
                "filesystem" = "ext4"
                "size" = $Persistence
            }
        )
    } | ConvertTo-Json -Depth 3

    $persistJson | Set-Content (Join-Path $OutputPath "persistence.json") -Encoding UTF8
    Write-Host "  persistence.json created ($Persistence MB)" -ForegroundColor Green
}

$scriptDir = Join-Path $OutputPath "script"
New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null

@'
<?xml version="1.0" encoding="utf-8"?>
<Ventoy>
  <profile>
    <menu class="submenu" name="GamerOS Windows 11 Pro 25H2 (Auto Install)">
      <image>/GamerOS-Win11x64Pro25H2.iso</image>
      <template>ventoy://script/autounattend.xml</template>
    </menu>
  </profile>
</Ventoy>
'@ | Set-Content (Join-Path $scriptDir "autounattend.xml") -Encoding UTF8
Write-Host "  script/autounattend.xml created" -ForegroundColor Green

Write-Host ""
Write-Host "Ventoy plugin structure generated!" -ForegroundColor Green
Write-Host "Copy the Ventoy/ folder contents to your Ventoy USB drive" -ForegroundColor Yellow
