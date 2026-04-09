<#
.SYNOPSIS
    Credential & Secret Vault module for C-Man's PowerShell Profile.
.DESCRIPTION
    Provides SecretManagement module integration, encrypted local vault,
    quick secret retrieval, auto-expiring session tokens, and SSH key
    agent helpers. Falls back to DPAPI-encrypted local store when
    SecretManagement is unavailable.
.NOTES
    Module: 15-SecretVault.ps1
    Requires: PowerShell 5.1+
#>

#region ── Configuration ──────────────────────────────────────────────────────

$script:VaultDir = Join-Path -Path $script:ProfileRoot -ChildPath 'Vault'
$script:VaultFile = Join-Path -Path $script:VaultDir -ChildPath 'secrets.enc.xml'
$script:TokenCacheFile = Join-Path -Path $script:VaultDir -ChildPath 'token-cache.enc.xml'
$script:VaultStore = @{}
$script:TokenCache = @{}
$script:UseSecretManagement = $false

if (-not (Test-Path -Path $script:VaultDir)) {
    $null = New-Item -Path $script:VaultDir -ItemType Directory -Force
}

#endregion

#region ── Vault Backend Detection ────────────────────────────────────────────

<#
.SYNOPSIS
    Initializes the secret vault backend.
.DESCRIPTION
    Detects whether Microsoft.PowerShell.SecretManagement is available and
    configures the appropriate backend. Falls back to DPAPI-encrypted
    local XML store on Windows.
#>
function Initialize-VaultBackend {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (Get-Module -ListAvailable -Name 'Microsoft.PowerShell.SecretManagement' -ErrorAction SilentlyContinue) {
        $script:UseSecretManagement = $true
        Import-Module -Name 'Microsoft.PowerShell.SecretManagement' -ErrorAction SilentlyContinue
        Write-Host '  SecretManagement backend detected' -ForegroundColor $Global:Theme.Muted
    }
    else {
        $script:UseSecretManagement = $false
        Import-LocalVault
    }
}

#endregion

#region ── Local DPAPI Vault ──────────────────────────────────────────────────

<#
.SYNOPSIS
    Imports the local encrypted vault from disk.
.DESCRIPTION
    Reads the DPAPI-encrypted XML vault file and deserializes it into
    the in-memory vault store. Creates an empty vault if none exists.
#>
function Import-LocalVault {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (Test-Path -Path $script:VaultFile) {
        try {
            $script:VaultStore = Import-Clixml -Path $script:VaultFile
        }
        catch {
            Write-Warning -Message "Failed to load vault: $($_.Exception.Message)"
            $script:VaultStore = @{}
        }
    }
    else {
        $script:VaultStore = @{}
    }

    if (Test-Path -Path $script:TokenCacheFile) {
        try {
            $script:TokenCache = Import-Clixml -Path $script:TokenCacheFile
        }
        catch {
            $script:TokenCache = @{}
        }
    }
}

<#
.SYNOPSIS
    Saves the local vault to disk with DPAPI encryption.
.DESCRIPTION
    Serializes the in-memory vault store to a DPAPI-encrypted XML file.
    Only the current Windows user can decrypt the data.
#>
function Save-LocalVault {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    try {
        $script:VaultStore | Export-Clixml -Path $script:VaultFile -Force
    }
    catch {
        Write-Warning -Message "Failed to save vault: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Saves the token cache to disk.
#>
function Save-TokenCache {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    try {
        $script:TokenCache | Export-Clixml -Path $script:TokenCacheFile -Force
    }
    catch {
        Write-Warning -Message "Failed to save token cache: $($_.Exception.Message)"
    }
}

#endregion

#region ── Secret CRUD Operations ─────────────────────────────────────────────

<#
.SYNOPSIS
    Stores a secret in the vault.
.DESCRIPTION
    Adds or updates a named secret. Supports plain strings, SecureStrings,
    PSCredential objects, and hashtables. Metadata tags can be attached
    for organization.
.PARAMETER Name
    The unique name/key for the secret.
.PARAMETER Value
    The secret value to store.
.PARAMETER SecureValue
    A SecureString value to store.
.PARAMETER Credential
    A PSCredential object to store.
.PARAMETER Tags
    Optional tags for organizing secrets.
.PARAMETER VaultName
    SecretManagement vault name (when using SM backend).
.EXAMPLE
    Set-VaultSecret -Name 'GitHubPAT' -Value 'ghp_xxxx' -Tags 'github','token'
.EXAMPLE
    Set-VaultSecret -Name 'DBCred' -Credential (Get-Credential)
#>
function Set-VaultSecret {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'String')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Position = 1, ParameterSetName = 'String')]
        [string]$Value,

        [Parameter(ParameterSetName = 'Secure')]
        [System.Security.SecureString]$SecureValue,

        [Parameter(ParameterSetName = 'Credential')]
        [PSCredential]$Credential,

        [Parameter()]
        [string[]]$Tags = @(),

        [Parameter()]
        [string]$VaultName = 'ProfileVault'
    )

    if (-not $PSCmdlet.ShouldProcess($Name, 'Store secret')) {
        return
    }

    if ($script:UseSecretManagement) {
        $secretValue = switch ($PSCmdlet.ParameterSetName) {
            'String'     { $Value }
            'Secure'     { $SecureValue }
            'Credential' { $Credential }
        }
        Set-Secret -Name $Name -Secret $secretValue -Vault $VaultName -ErrorAction SilentlyContinue
        if ($Tags.Count -gt 0) {
            Set-SecretInfo -Name $Name -Vault $VaultName -Metadata @{ Tags = ($Tags -join ',') } -ErrorAction SilentlyContinue
        }
    }
    else {
        $entry = @{
            Type      = $PSCmdlet.ParameterSetName
            Tags      = $Tags
            CreatedAt = [datetime]::UtcNow.ToString('o')
            UpdatedAt = [datetime]::UtcNow.ToString('o')
        }

        switch ($PSCmdlet.ParameterSetName) {
            'String' {
                $secStr = ConvertTo-SecureString -String $Value -AsPlainText -Force
                $entry['Secret'] = $secStr
            }
            'Secure' {
                $entry['Secret'] = $SecureValue
            }
            'Credential' {
                $entry['Secret'] = $Credential.Password
                $entry['Username'] = $Credential.UserName
            }
        }

        $script:VaultStore[$Name] = $entry
        Save-LocalVault
    }

    Write-Host "  Secret '$Name' stored successfully." -ForegroundColor $script:Theme.Success
}

<#
.SYNOPSIS
    Retrieves a secret from the vault.
.DESCRIPTION
    Returns the decrypted value of a named secret. For credentials, returns
    a PSCredential object. For strings, returns the plaintext value.
    Use -AsSecureString to get the raw SecureString.
.PARAMETER Name
    The name of the secret to retrieve.
.PARAMETER AsSecureString
    Return the value as a SecureString instead of plaintext.
.PARAMETER AsCredential
    Return the value as a PSCredential object.
.PARAMETER VaultName
    SecretManagement vault name (when using SM backend).
.EXAMPLE
    Get-VaultSecret -Name 'GitHubPAT'
.EXAMPLE
    $cred = Get-VaultSecret -Name 'DBCred' -AsCredential
#>
function Get-VaultSecret {
    [CmdletBinding(DefaultParameterSetName = 'Plain')]
    [OutputType([string], [System.Security.SecureString], [PSCredential])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(ParameterSetName = 'Secure')]
        [switch]$AsSecureString,

        [Parameter(ParameterSetName = 'Credential')]
        [switch]$AsCredential,

        [Parameter()]
        [string]$VaultName = 'ProfileVault'
    )

    if ($script:UseSecretManagement) {
        $secret = Get-Secret -Name $Name -Vault $VaultName -ErrorAction SilentlyContinue
        if ($null -eq $secret) {
            Write-Warning -Message "Secret '$Name' not found."
            return $null
        }
        if ($AsSecureString) { return $secret }
        if ($AsCredential -and $secret -is [PSCredential]) { return $secret }
        if ($secret -is [System.Security.SecureString]) {
            return [System.Net.NetworkCredential]::new('', $secret).Password
        }
        return $secret
    }

    if (-not $script:VaultStore.ContainsKey($Name)) {
        Write-Warning -Message "Secret '$Name' not found in local vault."
        return $null
    }

    $entry = $script:VaultStore[$Name]

    if ($AsCredential) {
        $username = if ($entry.ContainsKey('Username')) { $entry['Username'] } else { $Name }
        return [PSCredential]::new($username, $entry['Secret'])
    }

    if ($AsSecureString) {
        return $entry['Secret']
    }

    return [System.Net.NetworkCredential]::new('', $entry['Secret']).Password
}

<#
.SYNOPSIS
    Removes a secret from the vault.
.PARAMETER Name
    The name of the secret to remove.
.PARAMETER VaultName
    SecretManagement vault name (when using SM backend).
.EXAMPLE
    Remove-VaultSecret -Name 'OldToken'
#>
function Remove-VaultSecret {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [string]$VaultName = 'ProfileVault'
    )

    if (-not $PSCmdlet.ShouldProcess($Name, 'Remove secret')) {
        return
    }

    if ($script:UseSecretManagement) {
        Remove-Secret -Name $Name -Vault $VaultName -ErrorAction SilentlyContinue
    }
    else {
        if ($script:VaultStore.ContainsKey($Name)) {
            $script:VaultStore.Remove($Name)
            Save-LocalVault
        }
        else {
            Write-Warning -Message "Secret '$Name' not found."
            return
        }
    }

    Write-Host "  Secret '$Name' removed." -ForegroundColor $script:Theme.Warning
}

<#
.SYNOPSIS
    Lists all secrets in the vault.
.DESCRIPTION
    Displays a table of stored secret names, types, tags, and timestamps.
    Does not reveal secret values.
.PARAMETER Tag
    Filter secrets by tag.
.PARAMETER VaultName
    SecretManagement vault name (when using SM backend).
.EXAMPLE
    Show-VaultSecrets
.EXAMPLE
    Show-VaultSecrets -Tag 'github'
#>
function Show-VaultSecrets {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [string]$Tag,

        [Parameter()]
        [string]$VaultName = 'ProfileVault'
    )

    Write-Host "`n  Vault Secrets" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 60)" -ForegroundColor $script:Theme.Muted

    if ($script:UseSecretManagement) {
        $secrets = Get-SecretInfo -Vault $VaultName -ErrorAction SilentlyContinue
        if ($null -eq $secrets -or $secrets.Count -eq 0) {
            Write-Host '  (empty vault)' -ForegroundColor $Global:Theme.Muted
            return
        }
        foreach ($s in $secrets) {
            $tags = if ($s.Metadata -and $s.Metadata.ContainsKey('Tags')) { $s.Metadata['Tags'] } else { '' }
            if ($Tag -and $tags -notmatch [regex]::Escape($Tag)) { continue }
            Write-Host "  $($s.Name.PadRight(30))" -ForegroundColor $script:Theme.Accent -NoNewline
            Write-Host " $($s.Type.ToString().PadRight(15))" -ForegroundColor $script:Theme.Text -NoNewline
            Write-Host " $tags" -ForegroundColor $script:Theme.Muted
        }
    }
    else {
        if ($script:VaultStore.Count -eq 0) {
            Write-Host '  (empty vault)' -ForegroundColor $Global:Theme.Muted
            return
        }

        foreach ($key in ($script:VaultStore.Keys | Sort-Object)) {
            $entry = $script:VaultStore[$key]
            $entryTags = if ($entry.ContainsKey('Tags')) { $entry['Tags'] -join ', ' } else { '' }
            if ($Tag -and $entryTags -notmatch [regex]::Escape($Tag)) { continue }

            $typeName = if ($entry.ContainsKey('Type')) { $entry['Type'] } else { 'Unknown' }
            $updated = if ($entry.ContainsKey('UpdatedAt')) {
                ([datetime]$entry['UpdatedAt']).ToLocalTime().ToString('yyyy-MM-dd')
            }
            else { '' }

            Write-Host "  $($key.PadRight(30))" -ForegroundColor $script:Theme.Accent -NoNewline
            Write-Host " $($typeName.PadRight(12))" -ForegroundColor $script:Theme.Text -NoNewline
            Write-Host " $($updated.PadRight(12))" -ForegroundColor $script:Theme.Muted -NoNewline
            Write-Host " $entryTags" -ForegroundColor $script:Theme.Muted
        }
    }
    Write-Host ''
}

#endregion

#region ── Session Token Management ───────────────────────────────────────────

<#
.SYNOPSIS
    Stores a session token with automatic expiration.
.DESCRIPTION
    Saves a token that expires after a specified duration. Useful for
    API tokens, OAuth access tokens, and temporary credentials.
.PARAMETER Name
    The token identifier.
.PARAMETER Token
    The token value.
.PARAMETER ExpiresInMinutes
    Minutes until the token expires. Default is 60.
.EXAMPLE
    Set-SessionToken -Name 'AzureAccess' -Token 'eyJ...' -ExpiresInMinutes 30
#>
function Set-SessionToken {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [string]$Token,

        [Parameter()]
        [ValidateRange(1, 1440)]
        [int]$ExpiresInMinutes = 60
    )

    if (-not $PSCmdlet.ShouldProcess($Name, 'Store session token')) {
        return
    }

    $secToken = ConvertTo-SecureString -String $Token -AsPlainText -Force
    $script:TokenCache[$Name] = @{
        Token     = $secToken
        ExpiresAt = [datetime]::UtcNow.AddMinutes($ExpiresInMinutes).ToString('o')
        CreatedAt = [datetime]::UtcNow.ToString('o')
    }

    Save-TokenCache
    Write-Host "  Token '$Name' cached (expires in ${ExpiresInMinutes}m)." -ForegroundColor $script:Theme.Success
}

<#
.SYNOPSIS
    Retrieves a session token if not expired.
.DESCRIPTION
    Returns the token value if it exists and has not expired. Returns
    $null and warns if the token has expired.
.PARAMETER Name
    The token identifier.
.EXAMPLE
    $token = Get-SessionToken -Name 'AzureAccess'
#>
function Get-SessionToken {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    if (-not $script:TokenCache.ContainsKey($Name)) {
        Write-Warning -Message "Token '$Name' not found."
        return $null
    }

    $entry = $script:TokenCache[$Name]
    $expiry = [datetime]::Parse($entry['ExpiresAt'])

    if ([datetime]::UtcNow -gt $expiry) {
        Write-Warning -Message "Token '$Name' has expired."
        $script:TokenCache.Remove($Name)
        Save-TokenCache
        return $null
    }

    $minutesRemaining = [math]::Floor(($expiry - [datetime]::UtcNow).TotalMinutes)
    Write-Host "  Token '$Name' valid ($($minutesRemaining)m remaining)." -ForegroundColor $script:Theme.Muted
    return [System.Net.NetworkCredential]::new('', $entry['Token']).Password
}

<#
.SYNOPSIS
    Lists all session tokens and their expiry status.
.EXAMPLE
    Show-SessionTokens
#>
function Show-SessionTokens {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host "`n  Session Tokens" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 60)" -ForegroundColor $script:Theme.Muted

    if ($script:TokenCache.Count -eq 0) {
        Write-Host '  (no active tokens)' -ForegroundColor $Global:Theme.Muted
        return
    }

    $now = [datetime]::UtcNow
    foreach ($key in ($script:TokenCache.Keys | Sort-Object)) {
        $entry = $script:TokenCache[$key]
        $expiry = [datetime]::Parse($entry['ExpiresAt'])
        $isExpired = $now -gt $expiry

        $statusIcon = if ($isExpired) { '✗' } else { '✓' }
        $statusColor = if ($isExpired) { $Global:Theme.Error } else { $Global:Theme.Success }

        $timeDisplay = if ($isExpired) {
            'EXPIRED'
        }
        else {
            $rem = $expiry - $now
            "$([math]::Floor($rem.TotalMinutes))m left"
        }

        Write-Host "  $statusIcon " -ForegroundColor $statusColor -NoNewline
        Write-Host "$($key.PadRight(28))" -ForegroundColor $script:Theme.Accent -NoNewline
        Write-Host " $timeDisplay" -ForegroundColor $statusColor
    }
    Write-Host ''
}

<#
.SYNOPSIS
    Removes expired tokens from the cache.
.EXAMPLE
    Clear-ExpiredTokens
#>
function Clear-ExpiredTokens {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param()

    $now = [datetime]::UtcNow
    $expired = @($script:TokenCache.Keys | Where-Object -FilterScript {
        [datetime]::Parse($script:TokenCache[$_]['ExpiresAt']) -lt $now
    })

    if ($expired.Count -eq 0) {
        Write-Host '  No expired tokens.' -ForegroundColor $Global:Theme.Muted
        return
    }

    if (-not $PSCmdlet.ShouldProcess("$($expired.Count) expired tokens", 'Remove')) {
        return
    }

    foreach ($key in $expired) {
        $script:TokenCache.Remove($key)
    }

    Save-TokenCache
    Write-Host "  Cleared $($expired.Count) expired token(s)." -ForegroundColor $script:Theme.Success
}

#endregion

#region ── SSH Key Agent Helpers ───────────────────────────────────────────────

<#
.SYNOPSIS
    Lists SSH keys loaded in the agent.
.DESCRIPTION
    Displays currently loaded SSH keys from ssh-agent with fingerprints.
.EXAMPLE
    Get-SSHAgentKeys
#>
function Get-SSHAgentKeys {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host "`n  SSH Agent Keys" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 60)" -ForegroundColor $script:Theme.Muted

    $sshAdd = Get-Command -Name 'ssh-add' -ErrorAction SilentlyContinue
    if ($null -eq $sshAdd) {
        Write-Host '  ssh-add not found. Install OpenSSH.' -ForegroundColor $Global:Theme.Warning
        return
    }

    try {
        $output = & ssh-add -l 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host '  No keys loaded (or agent not running).' -ForegroundColor $Global:Theme.Muted
            Write-Host '  Run: Start-SSHAgent' -ForegroundColor $Global:Theme.Info
            return
        }

        foreach ($line in $output) {
            if ($line -match '^\d+\s+(\S+)\s+(.+)\s+\((\w+)\)$') {
                $fingerprint = $Matches[1]
                $keyPath = $Matches[2]
                $keyType = $Matches[3]
                Write-Host "  $keyType " -ForegroundColor $script:Theme.Accent -NoNewline
                Write-Host "$fingerprint " -ForegroundColor $script:Theme.Text -NoNewline
                Write-Host "$keyPath" -ForegroundColor $script:Theme.Muted
            }
            else {
                Write-Host "  $line" -ForegroundColor $script:Theme.Text
            }
        }
    }
    catch {
        Write-Warning -Message "SSH agent error: $($_.Exception.Message)"
    }
    Write-Host ''
}

<#
.SYNOPSIS
    Starts the SSH agent service and adds default keys.
.DESCRIPTION
    Ensures the ssh-agent service is running and adds keys from
    ~/.ssh/ (id_rsa, id_ed25519, id_ecdsa).
.PARAMETER KeyPaths
    Specific key file paths to add. If not specified, adds default keys.
.EXAMPLE
    Start-SSHAgent
.EXAMPLE
    Start-SSHAgent -KeyPaths '~/.ssh/work_key'
#>
function Start-SSHAgent {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [string[]]$KeyPaths
    )

    if (-not $PSCmdlet.ShouldProcess('ssh-agent', 'Start and load keys')) {
        return
    }

    # Ensure ssh-agent service is running on Windows
    $agentService = Get-Service -Name 'ssh-agent' -ErrorAction SilentlyContinue
    if ($null -ne $agentService -and $agentService.Status -ne 'Running') {
        try {
            Start-Service -Name 'ssh-agent' -ErrorAction Stop
            Write-Host '  ssh-agent service started.' -ForegroundColor $script:Theme.Success
        }
        catch {
            Write-Warning -Message "Cannot start ssh-agent: $($_.Exception.Message)"
            Write-Host '  Try: Set-Service ssh-agent -StartupType Automatic' -ForegroundColor $script:Theme.Info
            return
        }
    }

    $sshDir = Join-Path -Path $env:USERPROFILE -ChildPath '.ssh'
    if ($null -eq $KeyPaths -or $KeyPaths.Count -eq 0) {
        $defaultKeys = @('id_ed25519', 'id_ecdsa', 'id_rsa')
        $KeyPaths = @()
        foreach ($keyName in $defaultKeys) {
            $keyFile = Join-Path -Path $sshDir -ChildPath $keyName
            if (Test-Path -Path $keyFile) {
                $KeyPaths += $keyFile
            }
        }
    }

    if ($KeyPaths.Count -eq 0) {
        Write-Host '  No SSH keys found to add.' -ForegroundColor $Global:Theme.Warning
        return
    }

    foreach ($keyFile in $KeyPaths) {
        if (Test-Path -Path $keyFile) {
            try {
                & ssh-add $keyFile 2>&1 | Out-Null
                $keyName = Split-Path -Path $keyFile -Leaf
                Write-Host "  Added: $keyName" -ForegroundColor $script:Theme.Success
            }
            catch {
                Write-Warning -Message "Failed to add $keyFile"
            }
        }
        else {
            Write-Warning -Message "Key not found: $keyFile"
        }
    }
}

<#
.SYNOPSIS
    Generates a new SSH key pair.
.DESCRIPTION
    Creates an Ed25519 SSH key pair with an optional comment. Prompts
    for passphrase interactively.
.PARAMETER Name
    The key filename (stored in ~/.ssh/).
.PARAMETER Comment
    The key comment (typically an email address).
.PARAMETER Type
    The key type. Default is ed25519.
.EXAMPLE
    New-SSHKey -Name 'github_work' -Comment 'work@example.com'
#>
function New-SSHKey {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Position = 1)]
        [string]$Comment = "$env:USERNAME@$env:COMPUTERNAME",

        [Parameter()]
        [ValidateSet('ed25519', 'ecdsa', 'rsa')]
        [string]$Type = 'ed25519'
    )

    $sshDir = Join-Path -Path $env:USERPROFILE -ChildPath '.ssh'
    $keyPath = Join-Path -Path $sshDir -ChildPath $Name

    if (-not $PSCmdlet.ShouldProcess($keyPath, 'Generate SSH key')) {
        return
    }

    if (Test-Path -Path $keyPath) {
        Write-Warning -Message "Key '$keyPath' already exists. Use a different name."
        return
    }

    if (-not (Test-Path -Path $sshDir)) {
        $null = New-Item -Path $sshDir -ItemType Directory -Force
    }

    $sshKeygen = Get-Command -Name 'ssh-keygen' -ErrorAction SilentlyContinue
    if ($null -eq $sshKeygen) {
        Write-Warning -Message 'ssh-keygen not found. Install OpenSSH.'
        return
    }

    $sshArgs = @('-t', $Type, '-C', $Comment, '-f', $keyPath)
    if ($Type -eq 'rsa') {
        $sshArgs += @('-b', '4096')
    }

    & ssh-keygen @sshArgs
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n  Key generated: $keyPath" -ForegroundColor $script:Theme.Success
        Write-Host "  Public key:    ${keyPath}.pub" -ForegroundColor $script:Theme.Info

        $pubKey = Get-Content -Path "${keyPath}.pub" -Raw
        Write-Host "`n  Public key (for clipboard):" -ForegroundColor $script:Theme.Accent
        Write-Host "  $($pubKey.Trim())" -ForegroundColor $script:Theme.Text

        if (Get-Command -Name 'Set-Clipboard' -ErrorAction SilentlyContinue) {
            Set-Clipboard -Value $pubKey.Trim()
            Write-Host "`n  Public key copied to clipboard." -ForegroundColor $script:Theme.Success
        }
    }
}

#endregion

#region ── Quick Credential Helpers ───────────────────────────────────────────

<#
.SYNOPSIS
    Quick shortcut to copy a secret to clipboard.
.DESCRIPTION
    Retrieves a secret and copies it to the clipboard without displaying
    it on screen. The clipboard is cleared after a configurable timeout.
.PARAMETER Name
    The secret name.
.PARAMETER ClearAfterSeconds
    Seconds before clearing clipboard. Default is 30.
.EXAMPLE
    Copy-VaultSecret -Name 'GitHubPAT'
#>
function Copy-VaultSecret {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [ValidateRange(5, 300)]
        [int]$ClearAfterSeconds = 30
    )

    $value = Get-VaultSecret -Name $Name
    if ($null -eq $value) { return }

    if (Get-Command -Name 'Set-Clipboard' -ErrorAction SilentlyContinue) {
        Set-Clipboard -Value $value
        Write-Host "  '$Name' copied to clipboard (clears in ${ClearAfterSeconds}s)." -ForegroundColor $script:Theme.Success

        $null = Register-ObjectEvent -InputObject ([System.Timers.Timer]::new($ClearAfterSeconds * 1000)) -EventName 'Elapsed' -Action {
            Set-Clipboard -Value ''
            $Sender.Stop()
            $Sender.Dispose()
            Unregister-Event -SourceIdentifier $EventSubscriber.SourceIdentifier
        } -MaxTriggerCount 1
    }
    else {
        Write-Warning -Message 'Set-Clipboard not available.'
    }
}

<#
.SYNOPSIS
    Imports secrets from a .env file into the vault.
.DESCRIPTION
    Reads KEY=VALUE pairs from a .env file and stores each as a vault
    secret. Lines starting with # are ignored.
.PARAMETER Path
    Path to the .env file.
.PARAMETER Tag
    Tag to apply to all imported secrets.
.EXAMPLE
    Import-VaultFromEnv -Path '.\.env.secrets' -Tag 'project'
#>
function Import-VaultFromEnv {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path -Path $_ })]
        [string]$Path,

        [Parameter()]
        [string]$Tag = 'imported'
    )

    $lines = Get-Content -Path $Path | Where-Object -FilterScript {
        $_ -match '^\s*[A-Za-z_][A-Za-z0-9_]*\s*=' -and $_ -notmatch '^\s*#'
    }

    $count = 0
    foreach ($line in $lines) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
            $key = $Matches[1]
            $val = $Matches[2].Trim().Trim('"').Trim("'")

            if ($PSCmdlet.ShouldProcess($key, 'Import secret')) {
                Set-VaultSecret -Name $key -Value $val -Tags @($Tag) -Confirm:$false
                $count++
            }
        }
    }

    Write-Host "  Imported $count secret(s) from $Path." -ForegroundColor $script:Theme.Success
}

#endregion

#region ── Aliases ─────────────────────────────────────────────────────────────

Set-Alias -Name 'sec'        -Value 'Get-VaultSecret'       -Scope Global -Force
Set-Alias -Name 'secset'     -Value 'Set-VaultSecret'       -Scope Global -Force
Set-Alias -Name 'secrm'      -Value 'Remove-VaultSecret'    -Scope Global -Force
Set-Alias -Name 'secls'      -Value 'Show-VaultSecrets'     -Scope Global -Force
Set-Alias -Name 'seccp'      -Value 'Copy-VaultSecret'      -Scope Global -Force
Set-Alias -Name 'token'      -Value 'Get-SessionToken'      -Scope Global -Force
Set-Alias -Name 'tokenset'   -Value 'Set-SessionToken'      -Scope Global -Force
Set-Alias -Name 'tokens'     -Value 'Show-SessionTokens'    -Scope Global -Force
Set-Alias -Name 'sshkeys'    -Value 'Get-SSHAgentKeys'      -Scope Global -Force
Set-Alias -Name 'sshadd'     -Value 'Start-SSHAgent'        -Scope Global -Force
Set-Alias -Name 'sshgen'     -Value 'New-SSHKey'            -Scope Global -Force

#endregion

#region ── Tab Completion ─────────────────────────────────────────────────────

$secretNameCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $names = if ($script:UseSecretManagement) {
        (Get-SecretInfo -Vault 'ProfileVault' -ErrorAction SilentlyContinue).Name
    }
    else {
        $script:VaultStore.Keys
    }

    $names | Where-Object -FilterScript { $_ -like "${wordToComplete}*" } | ForEach-Object -Process {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Register-ArgumentCompleter -CommandName 'Get-VaultSecret' -ParameterName 'Name' -ScriptBlock $secretNameCompleter
Register-ArgumentCompleter -CommandName 'Remove-VaultSecret' -ParameterName 'Name' -ScriptBlock $secretNameCompleter
Register-ArgumentCompleter -CommandName 'Copy-VaultSecret' -ParameterName 'Name' -ScriptBlock $secretNameCompleter

$tokenNameCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $script:TokenCache.Keys | Where-Object -FilterScript { $_ -like "${wordToComplete}*" } | ForEach-Object -Process {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Register-ArgumentCompleter -CommandName 'Get-SessionToken' -ParameterName 'Name' -ScriptBlock $tokenNameCompleter

#endregion

#region ── Initialize ─────────────────────────────────────────────────────────

Initialize-VaultBackend

#endregion

