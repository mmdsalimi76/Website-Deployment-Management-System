<#
.SYNOPSIS
    Displays the current status of Docker containers on the remote server.
#>

$sharedUtilsPath = Join-Path $PSScriptRoot "..\\sync\\shared_utils.ps1"

# Load Utilities
if (Test-Path $sharedUtilsPath) { 
    . "$sharedUtilsPath" 
} else {
    Write-Error "Could not find shared_utils.ps1 at $sharedUtilsPath"
    exit 1
}

try {
    Write-Stage "DOCKER" "Fetching remote container status..."
    $statusCmd = "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
    Invoke-RemoteCommand -Command $statusCmd
}
catch {
    Write-Error "Failed to fetch container status: $($_.Exception.Message)"
    exit 1
}
