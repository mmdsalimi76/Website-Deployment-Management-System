# VPS Management Menu
# Purpose: Interactive menu for VPS terminal and log access.

$ErrorActionPreference = "Stop"

# --- Setup Paths ---
$vpsMgmtDir = $PSScriptRoot
$syncDir = Join-Path (Split-Path -Parent $vpsMgmtDir) "sync"
$utilsPath = Join-Path $syncDir "shared_utils.ps1"

if (Test-Path $utilsPath) {
    . "$utilsPath"
}

$paths = @{
    "Access" = Join-Path $vpsMgmtDir "access_vps.ps1"
    "Logs"   = Join-Path $vpsMgmtDir "view_logs.ps1"
}

function Write-MenuHeader ($text) {
    Write-Host "`n==================================================" -ForegroundColor Cyan
    Write-Host "  $text" -ForegroundColor White
    Write-Host "==================================================" -ForegroundColor Cyan
}

while ($true) {
    Clear-Host
    Write-MenuHeader "VPS MANAGEMENT & MONITORING"
    
    if ($VPS_IP) {
        Write-Host " Target VPS : $VPS_IP ($VPS_USER)" -ForegroundColor Gray
        Write-Host " ------------------------------------------------"
    }
    
    Write-Host " [1]  Open VPS Terminal (SSH)"
    Write-Host " [2]  View Service Logs (Streaming)"
    Write-Host " ------------------------------------------------"
    Write-Host " [b]  Back to Master Menu"
    
    $choice = Read-Host "`nSelect an option"
    
    switch ($choice) {
        "1" { 
            try { & $paths.Access } 
            catch [System.Management.Automation.PipelineStoppedException] { 
                Write-Host "`n[BACK] Returning to VPS menu..." -ForegroundColor Cyan
            }
            catch { Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red }
        }
        "2" { 
            try { & $paths.Logs } 
            catch [System.Management.Automation.PipelineStoppedException] { 
                Write-Host "`n[BACK] Returning to VPS menu..." -ForegroundColor Cyan
            }
            catch { Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red }
        }
        "b" { return }
    }
    
    if ($choice -ne "b") {
        Write-Host "`nReturn to VPS menu..." -ForegroundColor Gray
        Start-Sleep -Seconds 1
    }
}
