<#
.SYNOPSIS
    Installs Demiton into Claude Desktop as an MCP connector.

.DESCRIPTION
    Adds the Demiton entry to claude_desktop_config.json so Claude Desktop
    can reach the Demiton AI infrastructure platform. Uses the mcp-remote
    bridge (Node.js) to handle the connection and OAuth flow.

    Run once, then quit and reopen Claude Desktop. The Demiton connector
    appears in the chat interface; the first message that uses Demiton
    opens your browser to log in.

.PARAMETER Staging
    Point at staging (https://api-staging.demiton.io/mcp) instead of
    production. Useful for testing only.

.PARAMETER Uninstall
    Remove the Demiton entry from claude_desktop_config.json. Leaves
    every other server in the config untouched.

.EXAMPLE
    iwr https://raw.githubusercontent.com/demitonapp/claude-desktop-installer/main/install.ps1 -UseBasicParsing | iex

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [switch]$Staging,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

# ---- Configuration ----------------------------------------------------------
$ServerName = 'demiton'
$ProdUrl    = 'https://api.demiton.io/mcp/'
$StagingUrl = 'https://api-staging.demiton.io/mcp/'

$TargetUrl = if ($Staging) { $StagingUrl } else { $ProdUrl }
$EnvLabel  = if ($Staging) { 'staging' }    else { 'production' }
$Mode      = if ($Uninstall) { 'uninstall' } else { 'install' }

# ---- Helpers ----------------------------------------------------------------
function Write-Info  { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok    { param([string]$Message) Write-Host $Message -ForegroundColor Green }
function Write-Warn  { param([string]$Message) Write-Host $Message -ForegroundColor Yellow }
function Write-Fail  { param([string]$Message) Write-Host "Error: $Message" -ForegroundColor Red; exit 1 }

# ---- Banner -----------------------------------------------------------------
Write-Host ''
Write-Host 'Demiton for Claude Desktop' -ForegroundColor White
Write-Host "Setting up the $EnvLabel connector on Windows" -ForegroundColor DarkGray
Write-Host ''

# ---- Node.js requirement ----------------------------------------------------
function Test-CommandExists {
    param([string]$Name)
    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Install-NodeJs {
    Write-Warn 'Node.js was not found. mcp-remote needs Node 18 or later to run.'

    if (Test-CommandExists 'winget') {
        Write-Info 'Installing Node.js via winget...'
        # --silent: no UI; --accept-source-agreements --accept-package-agreements: no prompts
        winget install -e --id OpenJS.NodeJS.LTS `
            --silent --accept-source-agreements --accept-package-agreements `
            --source winget
    }
    elseif (Test-CommandExists 'choco') {
        Write-Info 'Installing Node.js via Chocolatey...'
        choco install nodejs-lts -y
    }
    else {
        Write-Fail "Could not install Node.js automatically. Please install Node 18+ from https://nodejs.org/ and rerun this script."
    }

    # winget installs to a new PATH that the current session doesn't see.
    # Refresh PATH from the registry so subsequent commands find `node`.
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path', 'User')

    if (-not (Test-CommandExists 'node')) {
        Write-Fail "Node.js install reported success but 'node' is still not on PATH. Open a new PowerShell window and rerun this script."
    }
}

if ((Test-CommandExists 'node') -and (Test-CommandExists 'npx')) {
    $NodeVersion = & node --version 2>$null
    Write-Info "Node.js detected ($NodeVersion)"
} else {
    Install-NodeJs
    Write-Ok "Node.js installed: $(& node --version)"
}

# ---- Locate Claude Desktop config -------------------------------------------
$ConfigDir  = Join-Path $env:APPDATA 'Claude'
$ConfigFile = Join-Path $ConfigDir 'claude_desktop_config.json'

Write-Info "Updating Claude Desktop config at $ConfigFile"

if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}

# ---- Backup any existing config exactly once per run ------------------------
if (Test-Path $ConfigFile) {
    $Timestamp  = Get-Date -Format 'yyyyMMddHHmmss'
    $BackupFile = "$ConfigFile.demiton-backup-$Timestamp"
    Copy-Item -Path $ConfigFile -Destination $BackupFile
    Write-Host "  Existing config backed up to: $BackupFile" -ForegroundColor DarkGray
}

# ---- Merge entry -------------------------------------------------------------
# Load existing config or start fresh.
$Config = $null
if (Test-Path $ConfigFile) {
    $Raw = Get-Content -Path $ConfigFile -Raw -ErrorAction Stop
    if ($Raw.Trim().Length -gt 0) {
        try {
            $Config = $Raw | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Fail "The existing config file is not valid JSON: $($_.Exception.Message). Fix it manually or delete it, then rerun."
        }
    }
}

if ($null -eq $Config) {
    $Config = [PSCustomObject]@{}
}

# Ensure mcpServers exists as a hashtable so we can add/remove keys.
if (-not ($Config.PSObject.Properties.Name -contains 'mcpServers')) {
    $Config | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue ([PSCustomObject]@{})
}
$McpServers = $Config.mcpServers

if ($Mode -eq 'uninstall') {
    if ($McpServers.PSObject.Properties.Name -contains $ServerName) {
        $McpServers.PSObject.Properties.Remove($ServerName)
        $Config | ConvertTo-Json -Depth 32 | Set-Content -Path $ConfigFile -Encoding UTF8
        Write-Ok 'Demiton has been removed from Claude Desktop.'
    } else {
        Write-Host "No '$ServerName' entry found; nothing to remove."
    }
    Write-Host ''
    Write-Host 'Quit and reopen Claude Desktop for the change to take effect.'
    Write-Host ''
    exit 0
}

# Install / update Demiton entry, preserving every other key untouched.
$DemitonEntry = [PSCustomObject]@{
    command = 'npx'
    args    = @('-y', 'mcp-remote', $TargetUrl)
}

if ($McpServers.PSObject.Properties.Name -contains $ServerName) {
    $McpServers.PSObject.Properties.Remove($ServerName)
}
$McpServers | Add-Member -NotePropertyName $ServerName -NotePropertyValue $DemitonEntry

# Write back with stable 2-space-ish formatting (ConvertTo-Json defaults are fine).
$Json = $Config | ConvertTo-Json -Depth 32
Set-Content -Path $ConfigFile -Value $Json -Encoding UTF8

Write-Host "Wrote '$ServerName' entry pointing at $TargetUrl."

# ---- Final instructions -----------------------------------------------------
Write-Host ''
Write-Ok 'Demiton is installed.'
Write-Host ''
Write-Host 'Next steps:' -ForegroundColor White
Write-Host '  1. Quit Claude Desktop completely (right-click the tray icon -> Quit).'
Write-Host '  2. Reopen Claude Desktop.'
Write-Host '  3. Start a new chat and click the connector icon.'
Write-Host '  4. The first message that uses Demiton will open your browser to log in.'
Write-Host ''
Write-Host 'Need help? Email support@demiton.io' -ForegroundColor DarkGray
Write-Host ''
