<#
.SYNOPSIS
    Registry Tools module for C-Man's PowerShell Profile.
.DESCRIPTION
    Registry search, backup/restore keys, compare snapshots, watch for
    changes, common tweak library, and export to .reg format.
.NOTES
    Module: 26-RegistryTools.ps1
    Requires: PowerShell 5.1+, Windows
#>

#region ── Registry Search ────────────────────────────────────────────────────

<#
.SYNOPSIS
    Searches registry keys and values by name or data.
.PARAMETER Pattern
    Search pattern (supports wildcards).
.PARAMETER Hive
    Registry hive to search.
.PARAMETER SearchData
    Also search value data, not just names.
.PARAMETER MaxDepth
    Maximum recursion depth.
.EXAMPLE
    Search-Registry -Pattern '*Better11*' -Hive HKCU
.EXAMPLE
    regsearch 'PowerShell' -Hive HKLM -MaxDepth 5
#>
function Search-Registry {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Pattern,

        [Parameter(Position = 1)]
        [ValidateSet('HKCU', 'HKLM', 'HKCR', 'HKU', 'HKCC')]
        [string]$Hive = 'HKCU',

        [Parameter()]
        [switch]$SearchData,

        [Parameter()]
        [ValidateRange(1, 20)]
        [int]$MaxDepth = 8
    )

    Write-Host "`n  Registry Search: '$Pattern' in $Hive" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 55)" -ForegroundColor $script:Theme.Muted

    $rootPath = "${Hive}:\"
    $found = 0

    function Search-RegistryRecursive {
        param([string]$KeyPath, [int]$Depth)
        if ($Depth -gt $MaxDepth) { return }

        try {
            $key = Get-Item -Path $KeyPath -ErrorAction SilentlyContinue
            if ($null -eq $key) { return }

            # Check key name
            if ($key.Name -match $Pattern -or $key.Name -like "*$Pattern*") {
                Write-Host "  KEY  $($key.Name)" -ForegroundColor $script:Theme.Accent
                $script:found++
            }

            # Check value names and data
            foreach ($valueName in $key.GetValueNames()) {
                $nameMatch = $valueName -match $Pattern -or $valueName -like "*$Pattern*"
                $dataMatch = $false

                if ($SearchData) {
                    $data = $key.GetValue($valueName)
                    if ($null -ne $data -and $data.ToString() -like "*$Pattern*") {
                        $dataMatch = $true
                    }
                }

                if ($nameMatch -or $dataMatch) {
                    $data = $key.GetValue($valueName)
                    $dataPreview = if ($null -ne $data) { $data.ToString() } else { '(null)' }
                    if ($dataPreview.Length -gt 50) { $dataPreview = $dataPreview.Substring(0, 47) + '...' }

                    Write-Host "  VAL  " -ForegroundColor $script:Theme.Success -NoNewline
                    Write-Host "$($key.Name)\$valueName" -ForegroundColor $script:Theme.Text -NoNewline
                    Write-Host " = $dataPreview" -ForegroundColor $script:Theme.Muted
                    $script:found++
                }
            }

            # Recurse subkeys
            foreach ($subKeyName in $key.GetSubKeyNames()) {
                $subPath = Join-Path -Path $KeyPath -ChildPath $subKeyName
                Search-RegistryRecursive -KeyPath $subPath -Depth ($Depth + 1)
            }
        }
        catch { }
    }

    Search-RegistryRecursive -KeyPath $rootPath -Depth 0
    Write-Host "`n  Found $found match(es)." -ForegroundColor $script:Theme.Muted
    Write-Host ''
}

#endregion

#region ── Backup / Restore ───────────────────────────────────────────────────

<#
.SYNOPSIS
    Exports a registry key to a .reg file.
.PARAMETER KeyPath
    Full registry key path.
.PARAMETER OutputPath
    Output .reg file path.
.EXAMPLE
    Export-RegistryKey -KeyPath 'HKCU:\Software\Better11' -OutputPath '.\b11-backup.reg'
.EXAMPLE
    regbackup 'HKCU:\Software\Better11' '.\backup.reg'
#>
function Export-RegistryKey {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$KeyPath,

        [Parameter(Mandatory, Position = 1)]
        [string]$OutputPath
    )

    if (-not $PSCmdlet.ShouldProcess($KeyPath, 'Export registry key')) { return }

    # Convert PS path to reg.exe format
    $regPath = $KeyPath -replace '^HKCU:', 'HKEY_CURRENT_USER' `
                        -replace '^HKLM:', 'HKEY_LOCAL_MACHINE' `
                        -replace '^HKCR:', 'HKEY_CLASSES_ROOT'

    $regPath = $regPath -replace '\\$', ''

    & reg export $regPath $OutputPath /y 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Exported: $KeyPath → $OutputPath" -ForegroundColor $script:Theme.Success
    }
    else {
        Write-Warning -Message "Export failed for: $KeyPath"
    }
}

<#
.SYNOPSIS
    Imports a .reg file into the registry.
.PARAMETER Path
    Path to the .reg file.
.EXAMPLE
    Import-RegistryFile -Path '.\backup.reg'
#>
function Import-RegistryFile {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path -Path $_ })]
        [string]$Path
    )

    if (-not $PSCmdlet.ShouldProcess($Path, 'Import registry file')) { return }

    & reg import $Path 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Imported: $Path" -ForegroundColor $script:Theme.Success
    }
    else {
        Write-Warning -Message "Import failed for: $Path"
    }
}

#endregion

#region ── Registry Snapshot & Compare ────────────────────────────────────────

<#
.SYNOPSIS
    Takes a snapshot of a registry key for later comparison.
.PARAMETER KeyPath
    Registry key to snapshot.
.PARAMETER Name
    Snapshot name for identification.
.EXAMPLE
    Save-RegistrySnapshot -KeyPath 'HKCU:\Software' -Name 'before-install'
#>
function Save-RegistrySnapshot {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$KeyPath,

        [Parameter(Position = 1)]
        [string]$Name = 'snapshot'
    )

    Write-Host "  Taking snapshot: $KeyPath..." -ForegroundColor $script:Theme.Info

    $snapshot = @{
        Name      = $Name
        KeyPath   = $KeyPath
        Timestamp = [datetime]::UtcNow.ToString('o')
        Values    = @{}
        SubKeys   = @()
    }

    try {
        $key = Get-Item -Path $KeyPath -ErrorAction Stop
        foreach ($valueName in $key.GetValueNames()) {
            $snapshot.Values[$valueName] = @{
                Data = $key.GetValue($valueName)
                Kind = $key.GetValueKind($valueName).ToString()
            }
        }
        $snapshot.SubKeys = @($key.GetSubKeyNames())
    }
    catch {
        Write-Warning -Message "Cannot read: $($_.Exception.Message)"
    }

    $cacheDir = Join-Path -Path $script:ProfileRoot -ChildPath 'Cache'
    $snapshotPath = Join-Path -Path $cacheDir -ChildPath "reg-snapshot-${Name}.json"
    $snapshot | ConvertTo-Json -Depth 5 | Set-Content -Path $snapshotPath
    Write-Host "  Saved: $snapshotPath" -ForegroundColor $script:Theme.Success

    return $snapshot
}

<#
.SYNOPSIS
    Compares current registry state against a saved snapshot.
.PARAMETER Name
    Snapshot name to compare against.
.EXAMPLE
    Compare-RegistrySnapshot -Name 'before-install'
.EXAMPLE
    regdiff before-install
#>
function Compare-RegistrySnapshot {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name
    )

    $cacheDir = Join-Path -Path $script:ProfileRoot -ChildPath 'Cache'
    $snapshotPath = Join-Path -Path $cacheDir -ChildPath "reg-snapshot-${Name}.json"

    if (-not (Test-Path -Path $snapshotPath)) {
        Write-Warning -Message "Snapshot '$Name' not found."
        return
    }

    $snapshot = Get-Content -Path $snapshotPath -Raw | ConvertFrom-Json
    Write-Host "`n  Registry Diff: $($snapshot.KeyPath) (vs $Name)" -ForegroundColor $script:Theme.Primary
    Write-Host "  Snapshot from: $($snapshot.Timestamp)" -ForegroundColor $script:Theme.Muted
    Write-Host "  $('─' * 55)" -ForegroundColor $script:Theme.Muted

    try {
        $key = Get-Item -Path $snapshot.KeyPath -ErrorAction Stop
        $currentValues = @{}
        foreach ($valueName in $key.GetValueNames()) {
            $currentValues[$valueName] = $key.GetValue($valueName)
        }

        $snapshotValues = @{}
        foreach ($prop in $snapshot.Values.PSObject.Properties) {
            $snapshotValues[$prop.Name] = $prop.Value.Data
        }

        $allKeys = @($snapshotValues.Keys + $currentValues.Keys | Sort-Object -Unique)
        $changes = 0

        foreach ($vName in $allKeys) {
            $inOld = $snapshotValues.ContainsKey($vName)
            $inNew = $currentValues.ContainsKey($vName)

            if ($inOld -and -not $inNew) {
                Write-Host "  - REMOVED: $vName" -ForegroundColor $script:Theme.Error
                $changes++
            }
            elseif (-not $inOld -and $inNew) {
                Write-Host "  + ADDED:   $vName = $($currentValues[$vName])" -ForegroundColor $script:Theme.Success
                $changes++
            }
            elseif ($snapshotValues[$vName].ToString() -ne $currentValues[$vName].ToString()) {
                Write-Host "  ~ CHANGED: $vName" -ForegroundColor $script:Theme.Warning
                Write-Host "      Old: $($snapshotValues[$vName])" -ForegroundColor $script:Theme.Error
                Write-Host "      New: $($currentValues[$vName])" -ForegroundColor $script:Theme.Success
                $changes++
            }
        }

        # Check subkeys
        $currentSubKeys = @($key.GetSubKeyNames())
        $oldSubKeys = @($snapshot.SubKeys)

        $addedKeys = $currentSubKeys | Where-Object -FilterScript { $_ -notin $oldSubKeys }
        $removedKeys = $oldSubKeys | Where-Object -FilterScript { $_ -notin $currentSubKeys }

        foreach ($k in $addedKeys) { Write-Host "  + SUBKEY:  $k" -ForegroundColor $script:Theme.Success; $changes++ }
        foreach ($k in $removedKeys) { Write-Host "  - SUBKEY:  $k" -ForegroundColor $script:Theme.Error; $changes++ }

        if ($changes -eq 0) {
            Write-Host '  No changes detected.' -ForegroundColor $Global:Theme.Success
        }
        else {
            Write-Host "`n  $changes change(s) detected." -ForegroundColor $script:Theme.Warning
        }
    }
    catch {
        Write-Warning -Message "Cannot compare: $($_.Exception.Message)"
    }
    Write-Host ''
}

#endregion

#region ── Common Tweaks ──────────────────────────────────────────────────────

<#
.SYNOPSIS
    Applies common Windows registry tweaks.
.DESCRIPTION
    Library of safe, reversible registry tweaks for Windows customization.
    Each tweak shows its current state and can be toggled.
.PARAMETER Tweak
    Name of the tweak to apply.
.PARAMETER List
    List all available tweaks.
.PARAMETER Revert
    Revert a tweak to Windows default.
.EXAMPLE
    Set-RegistryTweak -List
.EXAMPLE
    Set-RegistryTweak -Tweak ShowFileExtensions
.EXAMPLE
    regtweaks
#>
function Set-RegistryTweak {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'Apply')]
        [string]$Tweak,

        [Parameter(ParameterSetName = 'List')]
        [switch]$List,

        [Parameter(ParameterSetName = 'Apply')]
        [switch]$Revert
    )

    $tweaks = @{
        'ShowFileExtensions' = @{
            Path    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
            Name    = 'HideFileExt'
            On      = 0; Off = 1
            Desc    = 'Show file extensions in Explorer'
        }
        'ShowHiddenFiles' = @{
            Path    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
            Name    = 'Hidden'
            On      = 1; Off = 2
            Desc    = 'Show hidden files and folders'
        }
        'DisableSearchHighlights' = @{
            Path    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'
            Name    = 'IsDynamicSearchBoxEnabled'
            On      = 0; Off = 1
            Desc    = 'Disable search highlights in Start menu'
        }
        'ClassicContextMenu' = @{
            Path    = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
            Name    = '(Default)'
            On      = ''; Off = $null
            Desc    = 'Use classic right-click context menu (Win11)'
        }
        'TaskbarAlignLeft' = @{
            Path    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
            Name    = 'TaskbarAl'
            On      = 0; Off = 1
            Desc    = 'Align taskbar icons to the left (Win11)'
        }
        'VerboseLogon' = @{
            Path    = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
            Name    = 'VerboseStatus'
            On      = 1; Off = 0
            Desc    = 'Show detailed status during logon/logoff'
        }
        'DisableWebSearch' = @{
            Path    = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
            Name    = 'DisableSearchBoxSuggestions'
            On      = 1; Off = 0
            Desc    = 'Disable Bing web search in Start menu'
        }
    }

    if ($List -or [string]::IsNullOrEmpty($Tweak)) {
        Write-Host "`n  Registry Tweaks" -ForegroundColor $script:Theme.Primary
        Write-Host "  $('─' * 60)" -ForegroundColor $script:Theme.Muted

        foreach ($key in ($tweaks.Keys | Sort-Object)) {
            $t = $tweaks[$key]
            $current = Get-ItemProperty -Path $t.Path -Name $t.Name -ErrorAction SilentlyContinue
            $isActive = ($null -ne $current -and $current.$($t.Name) -eq $t.On)
            $icon = if ($isActive) { '✓' } else { '✗' }
            $color = if ($isActive) { $Global:Theme.Success } else { $Global:Theme.Muted }

            Write-Host "  $icon " -ForegroundColor $color -NoNewline
            Write-Host "$($key.PadRight(30))" -ForegroundColor $script:Theme.Accent -NoNewline
            Write-Host "$($t.Desc)" -ForegroundColor $script:Theme.Text
        }
        Write-Host ''
        return
    }

    if (-not $tweaks.ContainsKey($Tweak)) {
        Write-Warning -Message "Unknown tweak: $Tweak. Use -List to see options."
        return
    }

    $t = $tweaks[$Tweak]
    $value = if ($Revert) { $t.Off } else { $t.On }

    if (-not $PSCmdlet.ShouldProcess($Tweak, 'Apply registry tweak')) { return }

    try {
        if (-not (Test-Path -Path $t.Path)) {
            $null = New-Item -Path $t.Path -Force
        }
        Set-ItemProperty -Path $t.Path -Name $t.Name -Value $value -Type DWord -Force -ErrorAction Stop
        $action = if ($Revert) { 'Reverted' } else { 'Applied' }
        Write-Host "  $action`: $Tweak" -ForegroundColor $script:Theme.Success
        Write-Host '  Note: Some changes require Explorer restart or logoff.' -ForegroundColor $Global:Theme.Muted
    }
    catch {
        Write-Warning -Message "Failed: $($_.Exception.Message)"
    }
}

#endregion

#region ── Aliases ─────────────────────────────────────────────────────────────

Set-Alias -Name 'regsearch'  -Value 'Search-Registry'           -Scope Global -Force
Set-Alias -Name 'regbackup'  -Value 'Export-RegistryKey'         -Scope Global -Force
Set-Alias -Name 'regimport'  -Value 'Import-RegistryFile'        -Scope Global -Force
Set-Alias -Name 'regsnap'    -Value 'Save-RegistrySnapshot'      -Scope Global -Force
Set-Alias -Name 'regdiff'    -Value 'Compare-RegistrySnapshot'   -Scope Global -Force
Set-Alias -Name 'regtweaks'  -Value 'Set-RegistryTweak'          -Scope Global -Force

#endregion

