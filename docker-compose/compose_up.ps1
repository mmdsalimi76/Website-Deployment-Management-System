<#
.SYNOPSIS
    Brings up the configured docker-compose services.
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
    Write-Stage "DOCKER" "Starting services using $COMPOSE_FILE..."
    # We try 'docker compose' (v2) first, then fallback to 'docker-compose' (v1)
    $remoteCmd = "cd $REMOTE_PROD_DIR && (docker compose -f $COMPOSE_FILE up -d || docker-compose -f $COMPOSE_FILE up -d)"
    Invoke-RemoteCommand -Command $remoteCmd
    Write-Host "[SUCCESS] Services are up." -ForegroundColor Green
}
catch {
    Write-Error "Failed to bring services up: $($_.Exception.Message)"
    exit 1
}
