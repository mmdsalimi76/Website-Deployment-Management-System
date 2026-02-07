# VPS Terminal Access
# Purpose: Opens an interactive SSH shell on the VPS.

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

# Execute interactive shell
Write-Host ">>> CONNECTING TO VPS TERMINAL: $VPS_IP <<<" -ForegroundColor Cyan
Write-Host "(Type 'exit' to disconnect and return to menu)`n" -ForegroundColor Gray

# We use Start-Process to isolate the SSH session. 
# This prevents the parent PowerShell window from closing if the SSH session crashes or is interrupted.
$plinkProcess = Start-Process plink -ArgumentList "-ssh", "-pw", $VPS_PW, "$($VPS_USER)@$($VPS_IP)", "-t", "`"cd $REMOTE_PROD_DIR && bash`"" -NoNewWindow -PassThru -Wait

if ($plinkProcess.ExitCode -ne 0 -and $plinkProcess.ExitCode -ne 130 -and $plinkProcess.ExitCode -ne 1) {
    Write-Host "`n[INFO] SSH session ended (Code: $($plinkProcess.ExitCode))." -ForegroundColor Yellow
} else {
    Write-Host "`n[SUCCESS] SSH session closed." -ForegroundColor Green
}

Write-Host "Returning to menu..." -ForegroundColor Gray
Start-Sleep -Seconds 1
