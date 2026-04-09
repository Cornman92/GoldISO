# FZF Key Bindings for PowerShell

if (Get-Command -Name 'fzf' -ErrorAction SilentlyContinue) {
    # Import fzf's PowerShell module if available
    $fzfModulePath = Join-Path -Path $env:USERPROFILE -ChildPath 'scoop\shims\fzf.ps1'
    
    # Set fzf default options for better UX
    $env:FZF_DEFAULT_OPTS = '--height 40% --layout=reverse --border'
    
    # Ctrl+T: Find files recursively
    Set-PSReadLineKeyHandler -Key 'Ctrl+t' -BriefDescription 'FzfFileSearch' -LongDescription 'Search for files using fzf' -ScriptBlock {
        $files = Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        $selected = $files | fzf --multi --preview 'bat --style=numbers --color=always {}' 2>$null
        if ($selected) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($selected)
        }
    }
    
    # Ctrl+R: Search command history with fzf
    Set-PSReadLineKeyHandler -Key 'Ctrl+r' -BriefDescription 'FzfHistory' -LongDescription 'Search command history using fzf' -ScriptBlock {
        $history = Get-History | Select-Object -Last 100 -Property CommandLine | Select-Object -ExpandProperty CommandLine
        $selected = $history | fzf --tac 2>$null
        if ($selected) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($selected)
        }
    }
    
    # Alt+C: Change directory with fzf
    Set-PSReadLineKeyHandler -Key 'Alt+c' -BriefDescription 'FzfCd' -LongDescription 'Change directory using fzf' -ScriptBlock {
        $dirs = Get-ChildItem -Directory -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        $selected = $dirs | fzf --preview 'ls -la {}' 2>$null
        if ($selected -and (Test-Path -Path $selected)) {
            Set-Location -Path $selected
        }
    }
    
    # Alt+D: Search processes and kill
    Set-PSReadLineKeyHandler -Key 'Alt+d' -BriefDescription 'FzfKillProcess' -LongDescription 'Find and kill process using fzf' -ScriptBlock {
        $processes = Get-Process | Select-Object Id, Name, CPU | ForEach-Object { "$($_.Id) - $($_.Name) - CPU: $($_.CPU)" }
        $selected = $processes | fzf --multi 2>$null
        if ($selected) {
            $selected | ForEach-Object {
                $pid = ($_ -split ' - ')[0]
                Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    # Function to search and open files with default application
    function Invoke-FzfOpen {
        $files = Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        $selected = $files | fzf --multi --preview 'bat --style=numbers --color=always {}' 2>$null
        if ($selected) {
            $selected | ForEach-Object { Start-Process -FilePath $_ }
        }
    }
    Set-Alias -Name 'fo' -Value 'Invoke-FzfOpen' -Scope Global -ErrorAction SilentlyContinue
    
    # Function to grep in files using fzf + ripgrep
    function Invoke-FzfGrep {
        param([string]$Path = '.', [string]$Pattern = '')
        if (-not $Pattern) {
            $Pattern = Read-Host 'Search pattern'
        }
        $results = & rg -l $Pattern $Path 2>$null
        if ($results) {
            $selected = $results | fzf --preview "bat --style=numbers --color=always {} -C 3" 2>$null
            if ($selected) {
                return $selected
            }
        }
    }
    Set-Alias -Name 'fg' -Value 'Invoke-FzfGrep' -Scope Global -ErrorAction SilentlyContinue
    
    Write-Host 'FZF keybindings loaded (Ctrl+T, Ctrl+R, Alt+C, Alt+D)' -ForegroundColor Green
}
else {
    Write-Warning -Message 'fzf not found. Install with: scoop install fzf'
}