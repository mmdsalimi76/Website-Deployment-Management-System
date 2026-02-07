# Docker Compose Management Menu
# Purpose: Interactive menu for Docker lifecycle operations.

$ErrorActionPreference = "Stop"

# --- Setup Paths ---
$dockerDir = $PSScriptRoot
$syncDir = Join-Path (Split-Path -Parent $dockerDir) "sync"
$utilsPath = Join-Path $syncDir "shared_utils.ps1"

if (Test-Path $utilsPath) {
    . "$utilsPath"
}

$paths = @{
    "Up"     = Join-Path $dockerDir "compose_up.ps1"
    "Down"   = Join-Path $dockerDir "compose_down.ps1"
    "Build"  = Join-Path $dockerDir "build_containers.ps1"
    "Status" = Join-Path $dockerDir "check_status.ps1"
    "Health" = Join-Path $dockerDir "health_check.ps1"
}

function Write-MenuHeader ($text) {
    Write-Host "`n==================================================" -ForegroundColor Yellow
    Write-Host "  $text" -ForegroundColor White
    Write-Host "==================================================" -ForegroundColor Yellow
}

while ($true) {
    Clear-Host
    Write-MenuHeader "DOCKER COMPOSE MANAGEMENT"
    
    # Load Config for Display
    if ($DOCKER_CONFIG) {
        Write-Host " Project Root : $($DOCKER_CONFIG.REMOTE_PROJECT_ROOT)" -ForegroundColor Gray
        Write-Host " Compose File : $($DOCKER_CONFIG.COMPOSE_FILE)" -ForegroundColor Gray
        Write-Host " ------------------------------------------------"
    }
    
    Write-Host " [1]  Docker Compose UP (Start Services)"
    Write-Host " [2]  Docker Compose DOWN (Stop Services)"
    Write-Host " [3]  Rebuild Containers (Remote Build)"
    Write-Host " [4]  Check Service Status (ps)"
    Write-Host " [5]  Run Health Checks"
    Write-Host " ------------------------------------------------"
    Write-Host " [b]  Back to Master Menu"
    
    $choice = Read-Host "`nSelect an option"
    
    switch ($choice) {
        "1" { 
            Write-Stage "DOCKER" "Triggering Compose UP..."
            & $paths.Up 
        }
        "2" { 
            Write-Stage "DOCKER" "Triggering Compose DOWN..."
            & $paths.Down 
        }
        "3" { 
            Write-Stage "DOCKER" "Triggering remote container build..."
            & $paths.Build 
        }
        "4" { 
            Write-Stage "DOCKER" "Fetching container status..."
            & $paths.Status 
        }
        "5" { 
            Write-Stage "DOCKER" "Running health checks..."
            & $paths.Health 
        }
        "b" { return }
    }
    
    if ($choice -ne "b") {
        Write-Host "`nOperation completed. Press any key to return to menu..." -ForegroundColor Gray
        $null = [Console]::ReadKey($true)
    }
}
