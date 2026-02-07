# ==============================================================================
# 🤖 Automated Post-Sync Migration (Non-Interactive)
# ==============================================================================

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $scriptDir) { $scriptDir = $PSScriptRoot }

# Load Utils
. (Join-Path $scriptDir "..\sync\shared_utils.ps1")
. (Join-Path $scriptDir "database_utils.ps1")

Write-Stage "MIGRATE" "Starting Automated Migrations..."

try {
    # 1. Invoke Migrations using container name from JSON
    Invoke-Migrations -WebContainer $DB_CONFIG.WEB_CONTAINER_NAME
    
    Write-Host "[SUCCESS] Database is now up to date." -ForegroundColor Green
    exit 0
} catch {
    Write-Host "[ERROR] Migrations failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
