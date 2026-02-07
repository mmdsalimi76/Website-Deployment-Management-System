# ==============================================================================
# 🧠 Sync Orchestrator (The Communicator)
# ==============================================================================
# Purpose: Orchestrates the sync flow and reports progress to the Master Script.
# ==============================================================================

$ErrorActionPreference = "Stop"

# --- Load Utilities & Config ---
$scriptPath = $PSScriptRoot
if (-not $scriptPath) { $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $scriptPath) { $scriptPath = Get-Location }

$utilsPath = Join-Path $scriptPath "shared_utils.ps1"
if (Test-Path $utilsPath) {
    . $utilsPath
} else {
    throw "Could not find shared_utils.ps1 at $utilsPath"
}

# --- Cleanup Logic ---
trap { 
    Cleanup-Processes
    Write-Host "`n❌ ORCHESTRATOR FAILED!" -ForegroundColor Red
    Write-Host "Press any key to close..." -ForegroundColor Gray
    $null = [Console]::ReadKey($true)
    exit 1 
}

function Start-SyncOrchestration {
    Write-Header "SYNC ORCHESTRATION STARTING"
    
    # STEP 1: Pre-Flight
    Write-Stage "PRE-FLIGHT" "Initiating remote environment probe..."
    try {
        Invoke-PreFlight
        Write-Stage "PRE-FLIGHT" "SUCCESS: VPS is ready and dependencies verified."
    } catch {
        Write-Stage "PRE-FLIGHT" "FAILED: $($_.Exception.Message)"
        exit 1
    }

    # STEP 2: Full Sync
    Write-Stage "SYNC" "Starting atomic directory synchronization..."
    try {
        # Call full_sync.ps1
        & (Join-Path $scriptPath "full_sync.ps1")
        Write-Stage "SYNC" "SUCCESS: Directory mirror complete."
    } catch {
        Write-Stage "SYNC" "FAILED: $($_.Exception.Message)"
        exit 1
    }

    # STEP 3: Hand-off
    Write-Stage "READY" "Sync cycle complete. Handing off to Master Script for Build/Restart."
    Write-Host "`n✨ SYNC_ORCHESTRATOR_FINISHED" -ForegroundColor Green
}

# Execute
Start-SyncOrchestration
