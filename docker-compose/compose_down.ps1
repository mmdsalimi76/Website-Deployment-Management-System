<#
.SYNOPSIS
    Brings down the configured docker-compose services.
#>

# Load Utilities & Config
$dockerDir = $PSScriptRoot
$sharedUtilsPath = Join-Path (Split-Path -Parent $dockerDir) "sync\shared_utils.ps1"

if (Test-Path $sharedUtilsPath) { 
    . "$sharedUtilsPath" 
} else {
    Write-Error "Could not find shared_utils.ps1 at $sharedUtilsPath"
    exit 1
}

try {
    Write-Stage "DOCKER" "Stopping services for $COMPOSE_FILE..."
    # We try 'docker compose' (v2) first, then fallback to 'docker-compose' (v1)
    $remoteCmd = "cd $REMOTE_PROD_DIR && (docker compose -f $COMPOSE_FILE down || docker-compose -f $COMPOSE_FILE down)"
    
    Invoke-RemoteCommand -Command $remoteCmd
    Write-Host "[SUCCESS] Services are stopped and removed." -ForegroundColor Green
}
catch {
    Write-Error "Failed to bring services down: $($_.Exception.Message)"
    exit 1
}
