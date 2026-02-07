# VPS Service Log Viewer
# Purpose: Streams logs from a specific Docker container on the VPS.

param(
    [Parameter(Mandatory=$false)]
    [string]$ServiceName
)

$ErrorActionPreference = "Stop"

# --- Load Utilities & Config ---
$vpsMgmtDir = $PSScriptRoot
$syncDir = Join-Path (Split-Path -Parent $vpsMgmtDir) "sync"
$utilsPath = Join-Path $syncDir "shared_utils.ps1"

if (Test-Path $utilsPath) {
    . "$utilsPath"
} else {
    throw "Could not find shared_utils.ps1 at $utilsPath"
}

# Interactive selection if ServiceName not provided
if (-not $ServiceName) {
    Write-Host "`n--- SERVICE LOG VIEWER ---" -ForegroundColor Cyan
    if (-not $VPS_CONFIG) {
        Write-Host "[ERROR] VPS configuration not loaded." -ForegroundColor Red
        return
    }
    $services = $VPS_CONFIG.SERVICES.PSObject.Properties
    $i = 1
    $serviceMap = @{}
    foreach ($prop in $services) {
        Write-Host " [$i] $($prop.Value) (Service: $($prop.Name))"
        $serviceMap[$i.ToString()] = $prop.Name
        $i++
    }
    
    $choice = Read-Host "`nSelect service to view logs"
    if ($serviceMap.ContainsKey($choice)) {
        $ServiceName = $serviceMap[$choice]
    } else {
        Write-Host "Invalid choice." -ForegroundColor Red
        return
    }
}

Write-Host ">>> STREAMING LOGS FOR: $ServiceName <<<" -ForegroundColor Cyan
Write-Host "(Press 'Q' or 'Ctrl+C' to stop streaming and return to menu)`n" -ForegroundColor Gray

# Execute hardcoded log command
$oldEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"

# We try 'docker compose' first, then 'docker-compose'
$remoteCmd = "cd $REMOTE_PROD_DIR && (docker compose -f $COMPOSE_FILE logs -f $ServiceName || docker-compose -f $COMPOSE_FILE logs -f $ServiceName)"

# Launch plink as a background process to handle input locally
$plinkProcess = Start-Process plink -ArgumentList "-ssh", "-pw", $VPS_PW, "$($VPS_USER)@$($VPS_IP)", "-t", "`"$remoteCmd`"" -NoNewWindow -PassThru

# Monitor process and wait for 'Q' or process exit
while (-not $plinkProcess.HasExited) {
    if ([console]::KeyAvailable) {
        $key = [console]::ReadKey($true)
        if ($key.Key -eq 'Q' -or ($key.Key -eq 'C' -and $key.Modifiers -eq 'Control')) {
            Write-Host "`n[INFO] Stopping log stream..." -ForegroundColor Yellow
            $plinkProcess | Stop-Process -Force -ErrorAction SilentlyContinue
            break
        }
    }
    Start-Sleep -Milliseconds 100
}

if ($plinkProcess.ExitCode -ne 0 -and $plinkProcess.ExitCode -ne 130 -and $plinkProcess.ExitCode -ne 1 -and $plinkProcess.ExitCode -ne $null) {
    Write-Host "`n[ERROR] Log streaming ended with exit code: $($plinkProcess.ExitCode)." -ForegroundColor Red
    Write-Host "Possible reasons:" -ForegroundColor Yellow
    Write-Host " - Service '$ServiceName' does not exist in $COMPOSE_FILE"
    Write-Host " - Docker Compose is not initialized in $REMOTE_PROD_DIR"
    Write-Host " - Connection was lost"
    Read-Host "`nPress Enter to return to menu"
}

$ErrorActionPreference = $oldEAP
