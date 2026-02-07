<#
.SYNOPSIS
    🚀 END-TO-END PRODUCTION PIPELINE
    The automated workflow for project-wide synchronization.
    
    Workflow:
    1. Pre-Flight (VPS Connectivity & Tools)
    2. Safety Backup (Database integrity secured local/remote)
    3. Production Sync (Atomic directory mirror)
    4. Build & Up (Docker Compose orchestration)
    5. Health Check (2-minute stabilization monitor)
    6. Migrations (Final database schema evolution)
#>

$ErrorActionPreference = "Stop"

# --- Setup Paths ---
$scriptRoot = $PSScriptRoot
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
$sharedUtilsPath = Join-Path $projectRoot "scripts\sync\shared_utils.ps1"

# Pillar Paths
$dbPillar = Join-Path $projectRoot "scripts\database"
$syncPillar = Join-Path $projectRoot "scripts\sync"
$dockerPillar = Join-Path $projectRoot "scripts\docker-compose"

# --- Load Shared Utils ---
if (Test-Path $sharedUtilsPath) { 
    . "$sharedUtilsPath" 
} else {
    Write-Error "Fatal: Could not find shared_utils.ps1 at $sharedUtilsPath"
    exit 1
}

function Write-MainHeader ($text) {
    Write-Host "`n" + ("=" * 60) -ForegroundColor Yellow
    Write-Host "  🚀 $text" -ForegroundColor White
    Write-Host ("=" * 60) + "`n" -ForegroundColor Yellow
}

try {
    Write-MainHeader "STARTING END-TO-END PRODUCTION PIPELINE"

    # --- PHASE -1: VALIDATION ---
    if (-not (Test-ConfigHealth)) {
        exit 1
    }

    # --- PHASE 0: PRE-FLIGHT ---
    Invoke-PreFlight

    # --- PHASE 1: SAFETY BACKUP ---
    Write-Header "PHASE 1: DATABASE SAFETY GATE"
    Write-Stage "DB" "Triggering automated safety backup..."
    & (Join-Path $dbPillar "auto_backup.ps1")
    if ($LASTEXITCODE -ne 0) { throw "Deployment halted: Database backup failed." }

    # --- PHASE 2: PRODUCTION SYNC ---
    Write-Header "PHASE 2: PRODUCTION SYNCHRONIZATION"
    Write-Stage "SYNC" "Mirroring project directory to VPS..."
    # We use the sync_orchestrator which handles pre-flight again (safe) and full_sync
    & (Join-Path $syncPillar "sync_orchestrator.ps1")
    if ($LASTEXITCODE -ne 0) { throw "Pipeline halted: Sync failed." }

    # --- PHASE 3: CONTAINER ORCHESTRATION ---
    Write-Header "PHASE 3: CONTAINER BUILD & UP"
    Write-Stage "DOCKER" "Initiating remote build and service start..."
    & (Join-Path $dockerPillar "build_containers.ps1")
    if ($LASTEXITCODE -ne 0) { throw "Deployment halted: Docker build/up failed." }

    # --- PHASE 4: HEALTH MONITORING ---
    Write-Header "PHASE 4: HEALTH VERIFICATION"
    Write-Stage "HEALTH" "Monitoring services for 2 minutes..."
    & (Join-Path $dockerPillar "health_check.ps1")
    if ($LASTEXITCODE -ne 0) { throw "Deployment halted: Services failed to reach healthy state." }

    # --- PHASE 5: DATABASE EVOLUTION ---
    Write-Header "PHASE 5: DATABASE MIGRATIONS"
    Write-Stage "MIGRATE" "Running Django migrations..."
    & (Join-Path $dbPillar "auto_migrate.ps1")
    if ($LASTEXITCODE -ne 0) { throw "Deployment halted: Migrations failed." }

    Write-MainHeader "PIPELINE SUCCESSFUL - SYSTEM IS ONLINE"
    
    # Final Status Table
    Write-Host "`nFinal Service Status:" -ForegroundColor Gray
    & (Join-Path $dockerPillar "check_status.ps1")

} catch {
    Write-Host "`n[FATAL ERROR] Deployment Aborted!" -ForegroundColor Red
    Write-Host "Reason: $($_.Exception.Message)" -ForegroundColor White
    exit 1
} finally {
    Cleanup-Processes
}
