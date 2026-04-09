[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Prompt rendering requires Write-Host')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Prompt state must be global')]
param()

#region -- Prompt Engine ------------------------------------------------------

<#
.SYNOPSIS
    Intelligent prompt with Oh-My-Posh primary, custom PowerShell fallback.
    Features: git status, admin indicator, last command duration, error status,
    path truncation, and Nerd Font glyph support.
#>

# Track last command duration for prompt display
$Global:LastCommandDuration = $null
$Global:LastCommandFailed = $false

# Track if predictive loading has been initialized
$script:PredictiveLoadingInitialized = $false

# Oh-My-Posh initialization
$script:OhMyPoshAvailable = $false
$script:PromptMode = 'Custom'

# Check if ProfileConfig exists and has PromptStyle set
if ($Global:ProfileConfig -and $Global:ProfileConfig.PromptStyle -eq 'OhMyPosh') {
    $ompPath = Get-Command -Name 'oh-my-posh' -ErrorAction SilentlyContinue
    if ($ompPath) {
        $script:OhMyPoshAvailable = $true
        $script:PromptMode = 'OhMyPosh'

        # Use custom theme if it exists, otherwise use built-in
        $customThemePath = Join-Path -Path $script:ProfileRoot -ChildPath 'Themes' |
            Join-Path -ChildPath $Global:ProfileConfig.OhMyPoshTheme
        if (Test-Path -Path $customThemePath) {
            & oh-my-posh init pwsh --config $customThemePath | Invoke-Expression
        }
        else {
            # Generate and save custom Matrix theme
            $themeConfig = Get-MatrixOmpTheme
            $themeConfig | Set-Content -Path $customThemePath -Encoding UTF8
            & oh-my-posh init pwsh --config $customThemePath | Invoke-Expression
        }
    }
}

function Get-MatrixOmpTheme {
    <#
    .SYNOPSIS
        Generates a Matrix-themed Oh-My-Posh JSON config.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return @'
{
  "$schema": "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json",
  "version": 2,
  "final_space": true,
  "console_title_template": "{{ .Folder }}{{ if .Root }} [ROOT]{{ end }}",
  "blocks": [
    {
      "type": "prompt",
      "alignment": "left",
      "newline": true,
      "segments": [
        {
          "type": "os",
          "style": "diamond",
          "foreground": "#00ff00",
          "background": "#1a1a2e",
          "leading_diamond": "\ue0b6",
          "template": " {{ if .WSL }}\ue712{{ else }}\ue70f{{ end }} "
        },
        {
          "type": "session",
          "style": "powerline",
          "powerline_symbol": "\ue0b0",
          "foreground": "#00ff00",
          "background": "#16213e",
          "template": " {{ if .Root }}\uf0e7 {{ end }}{{ .UserName }}@{{ .HostName }} "
        },
        {
          "type": "path",
          "style": "powerline",
          "powerline_symbol": "\ue0b0",
          "foreground": "#00cc00",
          "background": "#0f3460",
          "properties": {
            "style": "agnoster_short",
            "max_depth": 3,
            "folder_icon": "\uf115",
            "home_icon": "\uf7db"
          },
          "template": " {{ .Path }} "
        },
        {
          "type": "git",
          "style": "powerline",
          "powerline_symbol": "\ue0b0",
          "foreground": "#00ff00",
          "foreground_templates": [
            "{{ if gt .Ahead 0 }}#00ffff{{ end }}",
            "{{ if gt .Behind 0 }}#ffff00{{ end }}",
            "{{ if and (gt .Ahead 0) (gt .Behind 0) }}#ff00ff{{ end }}"
          ],
          "background": "#1a1a2e",
          "background_templates": [
            "{{ if or (.Working.Changed) (.Staging.Changed) }}#2d1b00{{ end }}",
            "{{ if and (gt .Ahead 0) (gt .Behind 0) }}#2d002d{{ end }}"
          ],
          "properties": {
            "branch_icon": "\ue725 ",
            "cherry_pick_icon": "\ue29b ",
            "commit_icon": "\uf417 ",
            "fetch_status": true,
            "fetch_upstream_icon": true,
            "merge_icon": "\ue727 ",
            "no_commits_icon": "\uf0c3 ",
            "rebase_icon": "\ue728 ",
            "revert_icon": "\uf0e2 ",
            "tag_icon": "\uf412 "
          },
          "template": " {{ .HEAD }}{{ if .BranchStatus }} {{ .BranchStatus }}{{ end }}{{ if .Working.Changed }} \uf044 {{ .Working.String }}{{ end }}{{ if .Staging.Changed }} \uf046 {{ .Staging.String }}{{ end }}{{ if gt .StashCount 0 }} \uf692 {{ .StashCount }}{{ end }} "
        },
        {
          "type": "executiontime",
          "style": "powerline",
          "powerline_symbol": "\ue0b0",
          "foreground": "#ffff00",
          "background": "#1a1a2e",
          "properties": {
            "threshold": 3000,
            "style": "roundrock"
          },
          "template": " \ufbab {{ .FormattedMs }} "
        },
        {
          "type": "status",
          "style": "diamond",
          "foreground": "#ff0000",
          "background": "#1a1a2e",
          "trailing_diamond": "\ue0b4",
          "properties": {
            "always_enabled": false
          },
          "template": " \uf00d {{ .Code }} "
        }
      ]
    },
    {
      "type": "prompt",
      "alignment": "right",
      "segments": [
        {
          "type": "dotnet",
          "style": "plain",
          "foreground": "#00cc6a",
          "template": "\ue77f {{ .Full }}"
        },
        {
          "type": "node",
          "style": "plain",
          "foreground": "#6ca35e",
          "template": " \ue718 {{ .Full }}"
        },
        {
          "type": "python",
          "style": "plain",
          "foreground": "#ffde57",
          "template": " \ue235 {{ if .Venv }}{{ .Venv }} {{ end }}{{ .Full }}"
        },
        {
          "type": "docker",
          "style": "plain",
          "foreground": "#0db7ed",
          "template": " \uf308 {{ .Context }}"
        },
        {
          "type": "time",
          "style": "plain",
          "foreground": "#555555",
          "template": " {{ .CurrentDate | date .Format }}",
          "properties": {
            "time_format": "15:04:05"
          }
        }
      ]
    },
    {
      "type": "prompt",
      "alignment": "left",
      "newline": true,
      "segments": [
        {
          "type": "text",
          "style": "plain",
          "foreground": "#00ff00",
          "foreground_templates": [
            "{{ if gt .Code 0 }}#ff0000{{ end }}"
          ],
          "template": "\u276f"
        }
      ]
    }
  ],
  "transient_prompt": {
    "foreground": "#00ff00",
    "foreground_templates": [
      "{{ if gt .Code 0 }}#ff0000{{ end }}"
    ],
    "template": "\u276f "
  }
}
'@
}

#endregion

#region -- Fallback Custom Prompt ---------------------------------------------

if ($script:PromptMode -eq 'Custom') {
    function Global:prompt {
        $lastSuccess = $?
        $lastCmd = Get-History -Count 1 -ErrorAction SilentlyContinue

        # Compute last command duration
        $durationStr = ''
        if ($null -ne $lastCmd) {
            $duration = $lastCmd.EndExecutionTime - $lastCmd.StartExecutionTime
            if ($duration.TotalMilliseconds -ge $Global:ProfileConfig.SlowCommandThresholdMs) {
                if ($duration.TotalSeconds -ge 60) {
                    $durationStr = ' [{0:N0}m {1:N0}s]' -f [math]::Floor($duration.TotalMinutes), ($duration.Seconds)
                }
                else {
                    $durationStr = ' [{0:N1}s]' -f $duration.TotalSeconds
                }
            }
        }

        $tc = $Global:Theme
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        $prefix = if ($isAdmin) { "`e[91m\uf0e7 ADMIN `e[0m" } else { '' }

        # Truncated path
        $currentPath = $ExecutionContext.SessionState.Path.CurrentLocation.Path
        $homePath = $env:USERPROFILE
        if ($currentPath.StartsWith($homePath, [StringComparison]::OrdinalIgnoreCase)) {
            $currentPath = '~' + $currentPath.Substring($homePath.Length)
        }
        else {
            $maxLength = 30
            if ($currentPath.Length -gt $maxLength) {
                $currentPath = '...' + $currentPath.Substring($currentPath.Length - $maxLength)
            }
        }

        # Git status
        $gitInfo = ''
        if ($Global:ProfileConfig.EnableGitPrompt) {
            try {
                $status = & git status --porcelain 2>$null
                if ($status) {
                    $changes = $status -split "`n" | Where-Object { $_ }
                    $staged = ($changes | Where-Object { $_ -match '^[AMDRCU]\s' }).Count
                    $unstaged = ($changes | Where-Object { $_ -match '^\s[AMDRCU]\s' }).Count
                    $untracked = ($changes | Where-Object { $_ -match '^\?\?' }).Count
                    $ahead = 0
                    $behind = 0
                    try {
                        $aheadBehind = & git rev-list --count --left-right "@{u}...HEAD" 2>$null
                        if ($aheadBehind) {
                            $parts = $aheadBehind -split '\t'
                            if ($parts.Count -ge 2) {
                                $ahead = [int]$parts[0]
                                $behind = [int]$parts[1]
                            }
                        }
                    }
                    catch { }

                    $statusParts = @()
                    if ($staged -gt 0) { $statusParts += "+$staged" }
                    if ($unstaged -gt 0) { $statusParts += "!$unstaged" }
                    if ($untracked -gt 0) { $statusParts += "?$untracked" }
                    if ($ahead -gt 0) { $statusParts += "↑$ahead" }
                    if ($behind -gt 0) { $statusParts += "↓$behind" }
                    $gitStatus = if ($statusParts) { $statusParts -join ' ' } else { '=' }

                    $gitInfo = " [$gitStatus]"
                }
            }
            catch { }
        }

        # Error indicator
        $errorStr = ''
        if (-not $lastSuccess) {
            $errorStr = ' `e[91m\u2716`e[0m'
        }

        # Duration indicator
        $durStr = if ($durationStr) { "`e[33m$durationStr`e[0m" } else { '' }

        # Build prompt
        $promptChar = if ($isAdmin) { '#' } else { [char]0x276F }
        $promptColor = if ($lastSuccess) { '32' } else { '91' }

        "${prefix}`e[${promptColor}m${currentPath}`e[0m${gitInfo}${durStr}`n${errorStr}`e[${promptColor}m${promptChar}`e[0m "
    }
}

# Predictive loading runs once per session via prompt on first non-empty directory change
$script:PredictiveLoadingInitialized = $false

#endregion

#region -- Prompt Utilities ---------------------------------------------------

function Set-PromptStyle {
    <#
    .SYNOPSIS
        Switch between Oh-My-Posh and custom fallback prompt.
    .PARAMETER Style
        OhMyPosh or Custom.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('OhMyPosh', 'Custom')]
        [string]$Style
    )

    $Global:ProfileConfig.PromptStyle = $Style
    Write-Host -Object "Prompt style changed to $Style. Restart shell to apply." -ForegroundColor $Global:Theme.Warning
}

#endregion
