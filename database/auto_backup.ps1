# ==============================================================================
# 🤖 Automated Pre-Deploy Backup (Non-Interactive)
# ==============================================================================

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $scriptDir) { $scriptDir = $PSScriptRoot }

# Load Utils
. (Join-Path $scriptDir "..\sync\shared_utils.ps1")
. (Join-Path $scriptDir "database_utils.ps1")

Write-Stage "SAFETY" "Starting Automated Pre-Sync Backup..."

# Handle First Deploy
if ($DB_CONFIG.FIRST_DEPLOY) {
    Write-Host "[INFO] FIRST_DEPLOY flag is TRUE. Skipping backup safety check." -ForegroundColor Yellow
    exit 0
}

try {
    # 1. Trigger Remote Backup (Will handle container-not-found gracefully)
    $filename = Invoke-RemoteBackup
    if (-not $filename) { 
        Write-Host "[WARN] No backup created. If this is a first deploy, please set FIRST_DEPLOY to true in db_config.json." -ForegroundColor Yellow
        exit 0 
    }

    # 2. Pull to Local (Includes MD5 Handshake)
    $success = Pull-BackupToLocal $filename
    
    if ($success) {
        Write-Host "[SUCCESS] Backup secured and verified. Safe to proceed." -ForegroundColor Green
        exit 0
    } else {
        throw "Backup integrity verification failed."
    }
} catch {
    Write-Host "[FATAL] Pre-Deploy Backup failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
