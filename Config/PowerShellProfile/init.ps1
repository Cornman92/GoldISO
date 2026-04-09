Set-PSReadLineOption -EditMode Windows
Set-PSReadLineOption -HistorySearchCursorMovesToEnd
Set-PSReadLineOption -PredictionSource History

function prompt {
    $location = Get-Location
    $gitStatus = & {
        $gitInfo = git rev-parse --abbrev-ref HEAD 2>$null
        if ($gitInfo) {
            $branch = $gitInfo
            $ahead = (git rev-list --count @{u}..HEAD 2>$null) -as [int]
            $behind = (git rev-list HEAD..@{u} 2>$null) -as [int]
            $suffix = ""
            if ($ahead -and $ahead -gt 0) { $suffix += "+$ahead" }
            if ($behind -and $behind -gt 0) { $suffix += "-$behind" }
            if ($suffix) { " [$branch$suffix]" } else " [$branch]" }
    }
    Write-Host "PS " -NoNewline -ForegroundColor Cyan
    Write-Host $location -NoNewline -ForegroundColor Green
    if ($gitStatus) { Write-Host $gitStatus -NoNewline -ForegroundColor Yellow }
    "> "
}

function ll { Get-ChildItem -Force @args }
function la { Get-ChildItem -Force -Hidden @args }
function which { Get-Command -Name @args | Select-Object -ExpandProperty Source }
function rmrf { Remove-Item -Recurse -Force @args }
function cdf { Set-Location (Get-Clipboard) }

# Git shorthand functions (Set-Alias cannot wrap multi-word commands)
function Invoke-GsShort  { git status @args }
function Invoke-GaShort  { git add @args }
function Invoke-GcShort  { git commit @args }
function Invoke-GpShort  { git push @args }
function Invoke-GlShort  { git pull @args }
function Invoke-GdShort  { git diff @args }
function Invoke-GcoShort { git checkout @args }
function Invoke-GbShort  { git branch @args }
Set-Alias -Name gs  -Value Invoke-GsShort  -Scope Global -Force
Set-Alias -Name ga  -Value Invoke-GaShort  -Scope Global -Force
Set-Alias -Name gc  -Value Invoke-GcShort  -Scope Global -Force
Set-Alias -Name gp  -Value Invoke-GpShort  -Scope Global -Force
Set-Alias -Name gl  -Value Invoke-GlShort  -Scope Global -Force
Set-Alias -Name gd  -Value Invoke-GdShort  -Scope Global -Force
Set-Alias -Name gco -Value Invoke-GcoShort -Scope Global -Force
Set-Alias -Name gb  -Value Invoke-GbShort  -Scope Global -Force

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8