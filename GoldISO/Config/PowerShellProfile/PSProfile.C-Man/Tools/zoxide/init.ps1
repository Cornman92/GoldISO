# Zoxide Initialization for PowerShell
# Smarter cd command that learns your habits

if (Get-Command -Name 'zoxide' -ErrorAction SilentlyContinue) {
    # Initialize zoxide with PowerShell
    Invoke-Expression (& zoxide init powershell)
    
    # Alias z to zoxide for quick navigation
    Set-Alias -Name 'z' -Value 'zoxide' -Scope Global -ErrorAction SilentlyContinue
    
    # Function to add current directory to zoxide database
    function Add-DirectoryToZoxide {
        if (Test-Path -Path '.') {
            $pwdPath = (Get-Location).Path
            & zoxide add $pwdPath
            Write-Host "Added '$pwdPath' to zoxide database" -ForegroundColor Green
        }
    }
    Set-Alias -Name 'za' -Value 'Add-DirectoryToZoxide' -Scope Global -ErrorAction SilentlyContinue
    
    # Function to query zoxide for directories
    function Get-DirectoryMatch {
        param([string]$Query)
        if ($Query) {
            & zoxide query $Query
        }
        else {
            & zoxide query --list
        }
    }
    Set-Alias -Name 'zq' -Value 'Get-DirectoryMatch' -Scope Global -ErrorAction SilentlyContinue
}
else {
    Write-Warning -Message 'zoxide not found. Install with: scoop install zoxide'
}