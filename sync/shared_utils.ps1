# Shared Utilities for PowerShell 5.1
# This file is optimized for compatibility with the legacy PS 5.1 parser.

function Test-ConfigHealth {
    Write-Stage "VALIDATE" "Checking configuration integrity..."
    
    $requirements = @{
        "Global" = @("VPS_CONNECTION.IP", "VPS_CONNECTION.USER", "VPS_CONNECTION.PASSWORD", "REMOTE_PATHS.PROD_DIR")
        "Database" = @("DB_CONTAINER_NAME", "DB_NAME", "DB_USER")
        "Docker" = @("COMPOSE_FILE")
    }

    $missing = New-Object System.Collections.Generic.List[string]

    foreach ($key in $requirements.Keys) {
        $cfg = switch($key) {
            "Global" { $GLOBAL_CONFIG }
            "Database" { $DB_CONFIG }
            "Docker" { $DOCKER_CONFIG }
        }

        if (-not $cfg) {
            $null = $missing.Add("[$key] File missing or invalid JSON")
            continue
        }

        foreach ($path in $requirements[$key]) {
            $val = $cfg
            foreach ($part in $path.Split(".")) {
                if ($val.PSObject.Properties[$part]) {
                    $val = $val.$part
                } else {
                    $val = $null
                    break
                }
            }

            if (-not $val -or $val -eq "NOT SET" -or $val -eq "NONE") {
                $null = $missing.Add("[$key] Field '$path' is not configured")
            }
        }
    }

    if ($missing.Count -gt 0) {
        Write-Host "`n[!] CONFIGURATION ERRORS FOUND:" -ForegroundColor Red
        foreach ($m in $missing) { Write-Host "  - $m" -ForegroundColor White }
        Write-Host "`nPlease run Option [2] (Configuration Manager) to fix these before proceeding.`n" -ForegroundColor Yellow
        return $false
    }

    Write-Host "[OK] All required variables are set." -ForegroundColor Green
    return $true
}

function Invoke-RemoteCommand {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Command,
        [switch]$Quiet
    )
    
    if (-not $Quiet) {
        Write-Host "[REMOTE] Executing: $Command" -ForegroundColor Gray
    }

    $res = plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" $Command
    return $res
}

function Write-Header {
    param($text)
    Write-Host "`n>>> $text <<<" -ForegroundColor Cyan
    Write-Host ("-" * ($text.Length + 8)) -ForegroundColor Cyan
}

function Write-Stage {
    param($stage, $status)
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] [STAGE: $stage] -> $status" -ForegroundColor Magenta
}

function Cleanup-Processes {
    Get-Process pscp, plink -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Repair-RemoteTool {
    param($ToolName)
    $localFile = Join-Path $LOCAL_BIN_DIR $ToolName
    if (-not (Test-Path $localFile)) {
        Write-Host "[ERROR] Error: $ToolName not found in $LOCAL_BIN_DIR" -ForegroundColor Red
        return $false
    }
    Write-Host "[REPAIR] Sideloading $ToolName to VPS..." -ForegroundColor Yellow
    pscp -batch -pw $VPS_PW "$localFile" "$($VPS_USER)@$($VPS_IP):/tmp/$ToolName"
    plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" "mv /tmp/$ToolName /usr/local/bin/$ToolName; chmod +x /usr/local/bin/$ToolName"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] $ToolName installed successfully." -ForegroundColor Green
        return $true
    }
    return $false
}

# Environment Setup (Application Mode)
$scriptsRoot = $PSScriptRoot
# If we are in sync subfolder, the root is one level up
if ($scriptsRoot -match "sync$") {
    $scriptsRoot = Split-Path -Parent $scriptsRoot
}
$LOCAL_BIN_DIR = Join-Path $scriptsRoot "bin"

# Ensure local bin is in PATH for the session
$env:PATH = "$LOCAL_BIN_DIR;" + $env:PATH

function Load-ConfigJson ($path) {
    if (Test-Path $path) { 
        try {
            return Get-Content $path | ConvertFrom-Json 
        } catch {
            Write-Host "[ERROR] Failed to parse JSON at $path" -ForegroundColor Red
            return $null
        }
    }
    return $null
}

function Invoke-PreFlight {
    Write-Header "PHASE 0: PRE-FLIGHT (GATEKEEPER)"
    
    # 1. Local Tool Check (Prioritize local bin)
    Write-Stage "LOCAL" "Checking PuTTY tools..."
    foreach ($tool in @("plink", "pscp")) {
        $localTool = Join-Path $LOCAL_BIN_DIR "$tool.exe"
        if (Test-Path $localTool) {
            Set-Alias -Name $tool -Value $localTool -Scope Global
            Write-Host "[OK] Using portable $tool from bin folder." -ForegroundColor Gray
        } elseif (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            $p = "C:\Program Files\PuTTY\$tool.exe"
            if (Test-Path $p) { Set-Alias -Name $tool -Value $p -Scope Global }
            else { throw "Fatal: $tool not found in bin/ or System. Please install PuTTY or place in bin/." }
        }
    }

    # 2. Remote Requirement Probe
    Write-Stage "REMOTE" "Probing VPS at $VPS_IP..."
    
    # Constructing command with double quotes to avoid any single-quote parsing issues
    $cmdUnzip = "if ! command -v unzip >/dev/null; then echo MISSING_UNZIP; fi"
    $cmdRsync = "if ! command -v rsync >/dev/null; then echo MISSING_RSYNC; fi"
    $cmdDocker = "if ! command -v docker >/dev/null; then echo MISSING_DOCKER; fi"
    $cmdDir = "if [ ! -d $REMOTE_PROD_DIR ]; then echo MISSING_DIR; fi"
    $cmdSpace = "df -m /tmp | tail -1 | awk '{print `$4}'"
    
    $probeCmd = "$cmdUnzip; $cmdRsync; $cmdDocker; $cmdDir; $cmdSpace"
    
    try {
        $res = plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" $probeCmd
    } catch {
        throw "Fatal: Cannot connect to VPS. Check IP/Password/Network."
    }

    if (-not $res) { throw "Fatal: VPS returned no response. Connection might be hanging." }

    # 3. Handle Repairs or Fatal Errors
    if ($res -match "MISSING_DOCKER") { throw "Fatal: Docker is not installed on the VPS. Please install it manually first." }
    if ($res -match "MISSING_DIR") { 
        Write-Host "[WARN] Remote directory $REMOTE_PROD_DIR not found. Creating it..." -ForegroundColor Yellow
        plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" "mkdir -p $REMOTE_PROD_DIR"
    }

    if ($res -match "MISSING_UNZIP") { 
        Write-Stage "REPAIR" "unzip is missing on VPS."
        if (-not (Repair-RemoteTool "unzip")) { throw "Fatal: Failed to sideload unzip." } 
    }
    
    if ($res -match "MISSING_RSYNC") { 
        Write-Stage "REPAIR" "rsync is missing on VPS."
        if (-not (Repair-RemoteTool "rsync")) { throw "Fatal: Failed to sideload rsync." } 
    }
    
    # 4. Final Verification
    $freeSpace = $res | Select-Object -Last 1
    if ($freeSpace -match "^\d+$") {
        if ([int]$freeSpace -lt 500) { Write-Host "[WARN] Warning: Low disk space on VPS ($freeSpace MB)" -ForegroundColor Yellow }
        Write-Host "[OK] Pre-Flight Complete. VPS is ready ($freeSpace MB free)." -ForegroundColor Green
    } else {
        Write-Host "[OK] Pre-Flight Complete. VPS is ready." -ForegroundColor Green
    }
}

function Get-IgnoreRegex {
    if (-not (Test-Path $ignoreFile)) { return $null }
    
    $json = Get-Content $ignoreFile | ConvertFrom-Json
    $list = New-Object System.Collections.Generic.List[string]
    
    # Iterate through all categories in the JSON
    foreach ($prop in $json.PSObject.Properties) {
        if ($prop.Value -is [Array]) {
            foreach ($item in $prop.Value) {
                if ($item) { $null = $list.Add($item.Trim()) }
            }
        }
    }

    if ($list.Count -eq 0) { return $null }
    
    $reg = New-Object System.Collections.Generic.List[string]
    $bs = [char]92
    
    foreach ($i in $list) {
        $clean = $i.Replace("/", $bs)
        $escaped = [regex]::Escape($clean)
        $escaped = $escaped.Replace("\\\*\*", ".*")
        $escaped = $escaped.Replace("\*", "[^\\]*")
        $null = $reg.Add($escaped)
    }
    
    if ($reg.Count -gt 0) {
        return ($reg -join "|")
    }
    return $null
}

# Configuration Loading
$syncScriptDir = $PSScriptRoot
if (-not $syncScriptDir) { $syncScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $syncScriptDir) { $syncScriptDir = Get-Location }

# Paths to all config files
$scriptsRoot = if ($syncScriptDir -match "sync$") { Split-Path -Parent $syncScriptDir } else { $syncScriptDir }
$configFiles = @{
    "Global"   = Join-Path $syncScriptDir "global_config.json"
    "Docker"   = Join-Path $scriptsRoot "docker-compose\compose_config.json"
    "VPSMgmt"  = Join-Path $scriptsRoot "vps management\vps_config.json"
    "Database" = Join-Path $scriptsRoot "database\db_config.json"
    "Ignore"   = Join-Path $syncScriptDir "sync_ignore.json"
}

$GLOBAL_CONFIG = Load-ConfigJson $configFiles.Global
if (-not $GLOBAL_CONFIG) {
    Write-Host "`n[ERROR] Global configuration is missing!" -ForegroundColor Red
    Write-Host "Please ensure 'global_config.json' exists in the 'scripts/sync' folder." -ForegroundColor Yellow
    exit 1
}

# Load other configs for script-wide access
$DOCKER_CONFIG = Load-ConfigJson $configFiles.Docker
$VPS_CONFIG    = Load-ConfigJson $configFiles.VPSMgmt
$DB_CONFIG     = Load-ConfigJson $configFiles.Database
$IGNORE_CONFIG = Load-ConfigJson $configFiles.Ignore

# VPS Constants (mapped from JSON)
$VPS_IP = $GLOBAL_CONFIG.VPS_CONNECTION.IP
$VPS_USER = $GLOBAL_CONFIG.VPS_CONNECTION.USER
$VPS_PW = $GLOBAL_CONFIG.VPS_CONNECTION.PASSWORD
$REMOTE_PROD_DIR = $GLOBAL_CONFIG.REMOTE_PATHS.PROD_DIR
$REMOTE_SYNC_DIR = $GLOBAL_CONFIG.REMOTE_PATHS.SYNC_DIR
$REMOTE_STAGE_DIR = "$REMOTE_SYNC_DIR/stage"

# Docker Constants
$COMPOSE_FILE = if ($DOCKER_CONFIG) { $DOCKER_CONFIG.COMPOSE_FILE } else { "docker-compose.yml" }

# Project Root Detection
$projectRoot = $GLOBAL_CONFIG.PROJECT_METADATA.LOCAL_ROOT
if (-not (Test-Path $projectRoot)) {
    $projectRoot = Split-Path -Parent (Split-Path -Parent $syncScriptDir)
}

$tempDir = Join-Path $syncScriptDir "temp_directory"
$ignoreFile = $configFiles.Ignore
$zipFile = Join-Path $tempDir "deploy.zip"

# Database Configuration (Defaults)
$DB_SERVICE_NAME = if ($DB_CONFIG) { $DB_CONFIG.DB_CONTAINER_NAME } else { "db" }
$DB_NAME = if ($DB_CONFIG) { $DB_CONFIG.DB_NAME } else { "faraz_db" }
$DB_USER = if ($DB_CONFIG) { $DB_CONFIG.DB_USER } else { "postgres" }
$LOCAL_BACKUP_DIR = Join-Path (Split-Path -Parent $syncScriptDir) "database\backups"
$REMOTE_BACKUP_DIR = if ($DB_CONFIG) { $DB_CONFIG.BACKUP_DIR_REMOTE } else { "$REMOTE_PROD_DIR/backups" }
