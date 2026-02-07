# ==============================================================================
# 🗄️ Database Manager (The Safety Pillar)
# ==============================================================================
# Purpose: Handles flexible DB backups, pulls, and migrations on the air-gapped VPS.
# Location: scripts/database/database_manager.ps1
# ==============================================================================

$ErrorActionPreference = "Stop"

# --- Load Utilities & Config ---
$currentScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $currentScriptDir) { $currentScriptDir = $PSScriptRoot }

# 1. Load Shared Sync Utils
$syncUtilsPath = Join-Path $currentScriptDir "..\sync\shared_utils.ps1"
if (Test-Path $syncUtilsPath) { . "$syncUtilsPath" } else {
    Write-Host "[ERROR] Could not find shared_utils.ps1 at $syncUtilsPath" -ForegroundColor Red
    exit 1
}

# 2. Load Core DB Utils
# Note: shared_utils.ps1 might have overwritten $scriptDir, so we use our local $currentScriptDir
$dbUtilsPath = Join-Path $currentScriptDir "database_utils.ps1"
if (Test-Path $dbUtilsPath) { . "$dbUtilsPath" } else {
    Write-Host "[ERROR] Could not find database_utils.ps1 at $dbUtilsPath" -ForegroundColor Red
    exit 1
}

# --- Interactive Menu ---

while ($true) {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "       DATABASE MANAGEMENT TOOL         " -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Cyan
    if ($DB_CONFIG) {
        Write-Host " [Current DB Container: $($DB_CONFIG.DB_CONTAINER_NAME)]" -ForegroundColor Gray
        Write-Host " [First Deploy Mode:    $($DB_CONFIG.FIRST_DEPLOY)]" -ForegroundColor Gray
    }
    Write-Host "----------------------------------------"
    Write-Host " 1. Create Remote Backup"
    Write-Host " 2. Create Backup & Pull to Local (MD5 Handshake)"
    Write-Host " 3. Run Database Migrations"
    Write-Host " 4. Restore/Rollback from Backup"
    Write-Host " 5. Toggle FIRST_DEPLOY Flag"
    Write-Host "----------------------------------------"
    Write-Host " q. Exit"
    Write-Host "========================================" -ForegroundColor Cyan
    
    $choice = Read-Host "`nSelect an option"
    
    switch ($choice) {
        "1" { 
            Write-Stage "DB_OPS" "Starting manual remote backup..."
            Invoke-RemoteBackup
            Write-Host "`nPress any key..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "2" { 
            Write-Stage "DB_OPS" "Starting remote backup & local pull..."
            $file = Invoke-RemoteBackup
            if ($file) { Pull-BackupToLocal $file }
            Write-Host "`nPress any key..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "3" { 
            Write-Stage "DB_OPS" "Triggering remote database migrations..."
            Invoke-Migrations
            Write-Host "`nPress any key..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "4" {
            # List remote backups first
            Write-Stage "DB_OPS" "Fetching available backups for restore..."
            $remoteDir = $DB_CONFIG.BACKUP_DIR_REMOTE
            $backups = plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" "ls $remoteDir/*.sql.gz" 2>$null
            
            if (-not $backups) {
                Write-Host "[WARN] No backups found on VPS in $remoteDir" -ForegroundColor Yellow
            } else {
                $backupList = $backups | ForEach-Object { Split-Path $_ -Leaf }
                Write-Host "`nSelect a backup to restore:" -ForegroundColor Cyan
                for ($i=0; $i -lt $backupList.Count; $i++) {
                    Write-Host " $($i + 1). $($backupList[$i])"
                }
                $idx = Read-Host "`nEnter number (or 'c' to cancel)"
                if ($idx -match '^\d+$' -and [int]$idx -le $backupList.Count) {
                    $selected = $backupList[[int]$idx - 1]
                    Write-Stage "DB_OPS" "Restoring database from $selected..."
                    Restore-RemoteDatabase $selected
                }
            }
            Write-Host "`nPress any key..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "5" {
            $DB_CONFIG.FIRST_DEPLOY = -not $DB_CONFIG.FIRST_DEPLOY
            Write-Stage "CONFIG" "Updating FIRST_DEPLOY to $($DB_CONFIG.FIRST_DEPLOY)..."
            $DB_CONFIG | ConvertTo-Json | Set-Content (Join-Path $currentScriptDir "db_config.json")
            Write-Host "[OK] FIRST_DEPLOY set to $($DB_CONFIG.FIRST_DEPLOY)" -ForegroundColor Green
            Write-Host "`nPress any key..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "q" { exit }
    }
}
