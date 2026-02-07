# ==============================================================================
# 🔪 Selective Patch (The Surgical Scalpel)
# ==============================================================================
# Purpose: Allows picking specific files to sync and hot-patch on the VPS.
# ==============================================================================

# --- IMMEDIATE PERSISTENCE ARMOR ---
$ErrorActionPreference = "Stop"
trap { 
    Write-Host "`n[ERROR] SCRIPT CRASHED!" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor White
    Write-Host "`nPress any key to close..." -ForegroundColor Gray
    $null = [Console]::ReadKey($true)
    exit 1 
}

# --- Load Utilities & Config ---
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $scriptDir) { $scriptDir = $PSScriptRoot }
if (-not $scriptDir) { $scriptDir = Get-Location }

$utilsPath = Join-Path $scriptDir "shared_utils.ps1"

if (Test-Path $utilsPath) {
    # Dot-source using absolute quoted path
    . "$utilsPath"
} else {
    throw "Could not find shared_utils.ps1 at $utilsPath. Please ensure all scripts are in the same folder."
}

# Load Database Utilities
$dbUtilsPath = Join-Path (Split-Path -Parent $scriptDir) "database\database_utils.ps1"
if (Test-Path $dbUtilsPath) {
    . "$dbUtilsPath"
} else {
    Write-Host "[WARN] Database utilities not found at $dbUtilsPath. DB features disabled." -ForegroundColor Yellow
}

# Final Verification that functions loaded
if (-not (Get-Command Invoke-PreFlight -ErrorAction SilentlyContinue)) {
    throw "Fatal Error: shared_utils.ps1 was found but failed to load functions into scope. Check for syntax errors in shared_utils.ps1."
}

# ==============================================================================
# PHASE 0: PRE-FLIGHT (GATEKEEPER)
# ==============================================================================
# We do this FIRST before asking the user for any input or doing local work.
Invoke-PreFlight

# Automated safety backup
$autoBackupPath = Join-Path (Split-Path -Parent $scriptDir) "database\auto_backup.ps1"
if (Test-Path $autoBackupPath) {
    Write-Stage "SAFETY" "Triggering automated safety backup..."
    & $autoBackupPath
    if ($LASTEXITCODE -ne 0) {
        throw "Automated safety backup failed. Aborting patch for data safety."
    }
}

# Enable Long Path Support
$zipFile = Join-Path $tempDir "patch.zip"
$longZipFile = "\\?\$zipFile"

Write-Host "[START] Initializing Selective Patch Tool..." -ForegroundColor Cyan

# Ensure we are in the project root
Set-Location $projectRoot

# ==============================================================================
# PHASE 1: FILE SELECTION
# ==============================================================================
Write-Stage "PATCH" "Scanning project for eligible files..."

# Load .syncignore patterns
$ignoreRegex = Get-IgnoreRegex

# Get all files and filter them
$bs = [char]92
$allFiles = Get-ChildItem -Path $projectRoot -Recurse -File | Where-Object {
    $rel = $_.FullName.Substring($projectRoot.Length).TrimStart($bs)
    if ($ignoreRegex) {
        if ($rel -match $ignoreRegex) { return $false }
    }
    return $true
} | Select-Object -ExpandProperty FullName

# Use Out-GridView for selection
$selectedFullPaths = $allFiles | Out-GridView -Title "Select Files for Surgical Patch (Ctrl+Click for multiple)" -OutputMode Multiple

if (-not $selectedFullPaths) {
    Write-Host "[CANCEL] No files selected or operation cancelled. Exiting." -ForegroundColor Yellow
    Write-Host "Press any key to close..." -ForegroundColor Gray
    $null = [Console]::ReadKey($true)
    exit
}

# Convert back to relative paths for packaging
$selectedPaths = New-Object System.Collections.Generic.List[string]
foreach ($path in $selectedFullPaths) {
    $rel = $path.Substring($projectRoot.Length).TrimStart($bs)
    $null = $selectedPaths.Add($rel)
}

Write-Host "[OK] Selected $($selectedPaths.Count) files for patching." -ForegroundColor Green

# ==============================================================================
# PHASE 1.5: SMART DB DETECTION & SAFETY
# ==============================================================================
# Note: Automated backup already handled in Phase 0. 
# This section remains to track if logic was changed for potential rollbacks.
$logicDetected = $selectedPaths | Where-Object { $_ -match "\.py$" -or $_ -match "/migrations/" }
$backupTaken = $null 

if ($logicDetected) {
    Write-Host "`n[ALERT] Logic/Model changes detected in selected files!" -ForegroundColor Yellow
    # We don't prompt for backup here anymore as auto_backup.ps1 handled it at the start.
    # We just flag that a backup was indeed available for rollback logic later.
    $backupTaken = "Pre-Patch-Automated-Backup"
}

# ==============================================================================
# PHASE 2: PACKAGING & TRANSFER
# ==============================================================================
Write-Stage "PATCH" "Packaging selected files (On-the-fly)..."

if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }
if (Test-Path $zipFile) { Remove-Item $zipFile }

# Use .NET ZipArchive for efficient packaging
Add-Type -AssemblyName System.IO.Compression
$stream = [System.IO.File]::Open($longZipFile, [System.IO.FileMode]::Create)
$archive = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)

$bs = [char]92
foreach ($relPath in $selectedPaths) {
    $fullPath = Join-Path $projectRoot $relPath
    # Zip entries MUST use forward slash
    $zipEntryPath = $relPath.Replace($bs, "/")
    $entry = $archive.CreateEntry($zipEntryPath)
    $entryStream = $entry.Open()
    try {
        $fileStream = [System.IO.File]::OpenRead($fullPath)
        $fileStream.CopyTo($entryStream)
        $fileStream.Close()
    } finally {
        $entryStream.Close()
    }
}
$archive.Dispose()
$stream.Close()

$localHash = (Get-FileHash $zipFile -Algorithm MD5).Hash.ToLower()

Write-Stage "PATCH" "Transferring surgical patch to VPS..."
plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" "mkdir -p $REMOTE_SYNC_DIR"
pscp -batch -pw $VPS_PW $zipFile "$($VPS_USER)@$($VPS_IP):$REMOTE_SYNC_DIR/patch.zip"
if ($LASTEXITCODE -ne 0) { throw "Failed to upload patch to VPS." }

Write-Host "[VERIFY] Verifying integrity..." -ForegroundColor Yellow
$remoteHashResult = plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" "md5sum $REMOTE_SYNC_DIR/patch.zip"
$remoteHash = ($remoteHashResult -split " ")[0].ToLower()

if ($localHash -ne $remoteHash) {
    throw "Integrity check failed for patch!"
}

# ==============================================================================
# PHASE 3: INJECTION & REBUILD
# ==============================================================================
Write-Stage "PATCH" "Injecting files and hardening..."

$cmd1 = "unzip -o $REMOTE_SYNC_DIR/patch.zip -d $REMOTE_PROD_DIR/"
$cmd2 = "rm $REMOTE_SYNC_DIR/patch.zip"
$cmd3 = "if [ -d $REMOTE_PROD_DIR/scripts ]; then find $REMOTE_PROD_DIR/scripts -type f -name '*.sh' -exec chmod +x {} +; fi"
$injectCmds = "$cmd1; $cmd2; $cmd3"

plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" $injectCmds
if ($LASTEXITCODE -ne 0) { throw "Injection or hardening failed on VPS." }

# --- User-Driven Rebuild ---
Write-Host "`n[QUERY] Fetching available services from VPS..." -ForegroundColor Gray
$fetchCmd = "cd $REMOTE_PROD_DIR; (docker compose -f $COMPOSE_FILE config --services || docker-compose -f $COMPOSE_FILE config --services)"
$availableServicesRaw = plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" $fetchCmd

$serviceDisplayList = New-Object System.Collections.Generic.List[string]
$null = $serviceDisplayList.Add("[ NONE - Skip Rebuild ]")

# Mapping for user-friendly display
$friendlyMap = @{}
if ($VPS_CONFIG.SERVICES) {
    foreach ($prop in $VPS_CONFIG.SERVICES.PSObject.Properties) {
        $friendlyMap[$prop.Name.ToLower()] = $prop.Value
    }
}

if ($availableServicesRaw) {
    foreach ($svc in $availableServicesRaw) {
        $svcName = $svc.Trim()
        if ($svcName) {
            $displayName = $svcName
            if ($friendlyMap.ContainsKey($svcName.ToLower())) {
                $displayName = "$svcName ($($friendlyMap[$svcName.ToLower()]))"
            }
            $null = $serviceDisplayList.Add($displayName)
        }
    }
}

Write-Host "`n[INFO] Select services that need a rebuild based on your patch..." -ForegroundColor Cyan
$selectedItems = $serviceDisplayList | Out-GridView -Title "Select Services to Rebuild (Ctrl+Click for multiple)" -OutputMode Multiple

if ($selectedItems -and -not ($selectedItems -contains "[ NONE - Skip Rebuild ]")) {
    # Extract original service names from the display names
    $selectedServices = @()
    foreach ($item in $selectedItems) {
        $originalName = ($item -split " ")[0]
        $selectedServices += $originalName
    }
    
    $containerList = $selectedServices -join " "
    Write-Stage "PATCH" "Rebuilding: $containerList"
    
    $remoteCmds = "cd $REMOTE_PROD_DIR; (docker compose -f $COMPOSE_FILE build $containerList && docker compose -f $COMPOSE_FILE up -d $containerList) || (docker-compose -f $COMPOSE_FILE build $containerList && docker-compose -f $COMPOSE_FILE up -d $containerList)"
    
    plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" $remoteCmds
    if ($LASTEXITCODE -ne 0) { 
        Write-Host "[ERROR] Container rebuild failed." -ForegroundColor Red
        if ($backupTaken) {
            $rollback = Read-Host "A safety backup exists ($backupTaken). Would you like to rollback the database? (y/n)"
            if ($rollback -eq 'y') {
                Restore-RemoteDatabase $backupTaken
            }
        }
        throw "Container rebuild failed." 
    }
} else {
    Write-Host "[SKIP] Skipping rebuild as requested." -ForegroundColor Yellow
}

# ==============================================================================
# PHASE 4: CLEANUP
# ==============================================================================
Write-Stage "PATCH" "Cleaning up..."
if (Test-Path $zipFile) { Remove-Item $zipFile }
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" "rm -rf `"$REMOTE_SYNC_DIR`""

Write-Host "`n[OK] SURGICAL PATCH COMPLETE!" -ForegroundColor Green
Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = [Console]::ReadKey($true)
