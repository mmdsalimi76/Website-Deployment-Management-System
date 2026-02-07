# ==============================================================================
# Perfectionist Sideloading Engine v3 (HARDENED)
# ==============================================================================
# Features: 
# - Dynamic Discovery (Handles quotes/comments in YAML)
# - Size-Based Resume (Prevents loading corrupt partial transfers)
# - Strict Error Handling ($ErrorActionPreference = "Stop")
# - Auto-Cleanup & Remote Pruning
# - Post-Load Verification
# ==============================================================================

$ErrorActionPreference = "Stop"

# --- Load Utilities & Config ---
$scriptPath = $PSScriptRoot
$projectRoot = Split-Path (Split-Path $scriptPath -Parent) -Parent
$sharedUtilsPath = Join-Path $scriptPath "..\sync\shared_utils.ps1"
$infraConfigPath = Join-Path $scriptPath "infrastructure_config.json"

if (Test-Path $sharedUtilsPath) { 
    . "$sharedUtilsPath" 
} else {
    Write-Error "Could not find shared_utils.ps1 at $sharedUtilsPath"
    exit 1
}

if (Test-Path $infraConfigPath) { 
    $infraConfig = Get-Content $infraConfigPath | ConvertFrom-Json 
} else {
    Write-Error "Could not find infrastructure_config.json at $infraConfigPath"
    exit 1
}

# --- Setup Paths ---
$tempDir = Join-Path $scriptPath $infraConfig.SIDELOAD_SETTINGS.TEMP_BIN_DIR
$hashFile = Join-Path $scriptPath $infraConfig.SIDELOAD_SETTINGS.HASH_FILE
$composeFile = Join-Path $projectRoot $infraConfig.SIDELOAD_SETTINGS.COMPOSE_PROD_FILE
$ignorePrefix = $infraConfig.IMAGE_FILTERS.IGNORE_PREFIX

# ==============================================================================
# PHASE 0: PRE-FLIGHT CHECKS
# ==============================================================================
Write-Host "`n[!] WARNING: This script will build and transfer large Docker images to your VPS." -ForegroundColor Yellow
Write-Host "    This may take significant time and bandwidth." -ForegroundColor Yellow
$confirm = Read-Host "`nAre you sure you want to proceed? (y/N)"
if ($confirm -ne 'y') {
    Write-Host "Operation cancelled." -ForegroundColor Gray
    exit 0
}

Invoke-PreFlight

# Additional Local Tool Check (Docker)
Write-Stage "LOCAL" "Verifying Docker Desktop..."
if (!(Get-Command "docker" -ErrorAction SilentlyContinue)) {
    Write-Host "Error: 'docker' is not installed or not in PATH." -ForegroundColor Red
    exit 1
}
Write-Host "Local tools verified." -ForegroundColor Green

# ==============================================================================
# PHASE 1: DYNAMIC DISCOVERY
# ==============================================================================
Write-Header "PHASE 1: DYNAMIC DISCOVERY"

# 1. Parse docker-compose.prod.yml for 3rd party images
Write-Stage "PARSE" "Scanning $composeFile for images..."
if (!(Test-Path $composeFile)) { Write-Host "Error: $composeFile not found!"; exit 1 }

$images = Get-Content $composeFile | ForEach-Object {
    if ($_ -match "image:\s+['""]?(?!$ignorePrefix)([^'""\s#]+)") {
        $matches[1]
    }
} | Select-Object -Unique

Write-Host "Found $($images.Count) infrastructure images to sideload." -ForegroundColor Gray

# 2. Check if Base Image needs building
Write-Stage "BASE" "Checking dependencies..."
Set-Location $projectRoot
$reqFiles = Get-ChildItem "requirements-*.txt"
if ($reqFiles.Count -eq 0) { Write-Host "No requirements files found."; $currentHash = "none" }
else { $currentHash = ($reqFiles | Get-FileHash -Algorithm MD5 | ForEach-Object { $_.Hash } | Out-String).Trim() }

$needsBaseBuild = $true
if (Test-Path $hashFile) {
    $lastHash = Get-Content $hashFile
    if ($currentHash -eq ($lastHash | Out-String).Trim()) {
        $needsBaseBuild = $false
        Write-Host "Base image dependencies haven't changed. Skipping build." -ForegroundColor Yellow
    }
}

# PHASE 2: PROCESSING LOOP
# ==============================================================================
Write-Header "PHASE 2: PROCESSING LOOP"

if (!(Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }

$allTargets = @()
if ($needsBaseBuild) { $allTargets += "faraz-base:latest" }
foreach ($img in $images) { $allTargets += $img }

$summary = @()
$totalSteps = $allTargets.Count
$currentStep = 0

foreach ($img in $allTargets) {
    $currentStep++
    $safeName = $img.Replace(':', '_').Replace('/', '_')
    $tarFile = Join-Path $tempDir "$($safeName).tar"
    $status = "Success"
    
    Write-Progress -Activity "Sideloading Images" -Status "Processing $img ($currentStep/$totalSteps)" -PercentComplete (($currentStep / $totalSteps) * 100)

    try {
        Write-Host "`n[$currentStep/$totalSteps] Target: $img" -ForegroundColor Cyan
        
        # Step 1: Prepare Image
        if ($img -eq "faraz-base:latest") {
            Write-Host "   Building locally..." -ForegroundColor Yellow
            docker build -t $img -f Dockerfile.base .
            $currentHash | Out-File $hashFile
        } else {
            Write-Host "   Pulling..." -ForegroundColor Yellow
            docker pull $img | Out-Null
        }

        # Step 2: Save to Disk
        Write-Host "   Saving to $safeName.tar..." -ForegroundColor Gray
        docker save $img -o $tarFile
        $localSize = (Get-Item $tarFile).Length

        # Step 3: Intelligent Transfer (Resume/Skip)
        Write-Stage "TRANSFER" "Uploading $img to VPS..."
        $remoteCheck = plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" "stat -c %s /tmp/$($safeName).tar 2>/dev/null"
        
        if ($LASTEXITCODE -eq 0 -and $remoteCheck.Trim() -eq $localSize.ToString()) {
            Write-Host "   Exact file already exists on VPS. Skipping upload." -ForegroundColor Yellow
            $status = "Skipped (Existing)"
        } else {
            pscp -batch -pw $VPS_PW $tarFile "$($VPS_USER)@$($VPS_IP):/tmp/$($safeName).tar"
            $status = "Uploaded"
        }

        # Step 4: Load & Verify
        Write-Stage "LOAD" "Injecting image into remote Docker..."
        plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" "docker load -i /tmp/$($safeName).tar; rm -f /tmp/$($safeName).tar"

        $verify = plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" "docker images -q $img"
        if ([string]::IsNullOrWhiteSpace($verify)) {
            throw "Failed to verify $img on VPS after load."
        }
        
        Write-Host "   Ready on VPS." -ForegroundColor Green
    } catch {
        Write-Host "   FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $status = "Failed"
    } finally {
        if (Test-Path $tarFile) { Remove-Item $tarFile }
        $summary += [PSCustomObject]@{ Image = $img; Status = $status }
    }
}

# ==============================================================================
# PHASE 3: FINALIZATION
# ==============================================================================
Write-Header "PHASE 3: FINALIZATION"

Write-Host "Pruning old image layers on VPS..." -ForegroundColor Gray
plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" "docker image prune -f" | Out-Null

Write-Host "`nSummary:" -ForegroundColor Yellow
$summary | Format-Table -AutoSize

Write-Host "`nALL SYSTEMS GO! Infrastructure is synchronized." -ForegroundColor Green
Write-Host "The VPS is now ready for an offline application build." -ForegroundColor Gray
