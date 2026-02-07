<#
.SYNOPSIS
    Builds and starts containers using the configured docker-compose file.
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
    Write-Stage "BUILD" "Initiating remote build using $COMPOSE_FILE..."
    
    # We try 'docker compose' (v2) first, then fallback to 'docker-compose' (v1)
    $remoteCmd = "cd $REMOTE_PROD_DIR && (docker compose -f $COMPOSE_FILE up -d --build || docker-compose -f $COMPOSE_FILE up -d --build)"
    
    Invoke-RemoteCommand -Command $remoteCmd
    
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose build failed on the remote server."
    }

    Write-Stage "SUCCESS" "Containers are building/starting in the background."
}
catch {
    Write-Error "Build process failed: $($_.Exception.Message)"
    exit 1
}
