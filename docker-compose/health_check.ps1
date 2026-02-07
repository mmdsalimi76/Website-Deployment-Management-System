<#
.SYNOPSIS
    Performs health checks on containers for up to 2 minutes.
#>

$sharedUtilsPath = Join-Path $PSScriptRoot "..\\sync\\shared_utils.ps1"

# Load Utilities
if (Test-Path $sharedUtilsPath) { 
    . "$sharedUtilsPath" 
} else {
    Write-Error "Could not find shared_utils.ps1 at $sharedUtilsPath"
    exit 1
}

function Get-ContainerHealth ($ContainerName) {
    # Check if container exists first
    $exists = Invoke-RemoteCommand -Command "docker ps -a --filter name=^/$ContainerName$ --format '{{.Names}}'" -Quiet
    if (-not $exists) { return "NOT_FOUND" }

    # We use a conditional template to handle containers with and without defined healthchecks.
    $template = "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}"
    $command = "docker inspect --format='$template' $ContainerName"
    $status = Invoke-RemoteCommand -Command $command -Quiet
    return $status.Trim().Trim('"')
}

try {
    Write-Stage "HEALTH" "Starting health monitoring (Timeout: 2 minutes)..."
    
    $maxRetries = 12 # 12 * 10 seconds = 120 seconds
    $retryCount = 0
    $allHealthy = $false

    while (-not $allHealthy -and $retryCount -lt $maxRetries) {
        $allHealthy = $true
        $retryCount++
        Write-Host "`n[Check $retryCount/$maxRetries] Verifying services..." -ForegroundColor Yellow

        foreach ($container in $DB_CONFIG.CRITICAL_CONTAINERS) {
            $status = Get-ContainerHealth -ContainerName $container
            
            if ($status -eq "healthy") {
                Write-Host "  [HEALTHY] $container is verified healthy." -ForegroundColor Green
            } elseif ($status -eq "running") {
                Write-Host "  [RUNNING] $container is running (no healthcheck defined)." -ForegroundColor Green
            } elseif ($status -eq "starting" -or $status -eq "null" -or $status -eq "") {
                Write-Host "  [..] $container is initializing..." -ForegroundColor Cyan
                $allHealthy = $false
            } elseif ($status -eq "NOT_FOUND") {
                Write-Host "  [MISSING] $container does not exist yet." -ForegroundColor Red
                $allHealthy = $false
            } else {
                Write-Host "  [!!] $container status: $status" -ForegroundColor Red
                $allHealthy = $false
            }
        }

        if (-not $allHealthy) {
            if ($retryCount -lt $maxRetries) {
                Write-Host "Waiting 10s for stabilization..." -DarkGray
                Start-Sleep -Seconds 10
            }
        }
    }

    if ($allHealthy) {
        Write-Stage "SUCCESS" "All critical services are confirmed healthy."
        exit 0
    } else {
        Write-Error "Health check timed out. One or more services are not healthy."
        exit 1
    }
}
catch {
    Write-Error "Health check failed: $($_.Exception.Message)"
    exit 1
}
