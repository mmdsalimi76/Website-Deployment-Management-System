# ==============================================================================
# 📦 Full Atomic Sync (The Atomic Hammer)
# ==============================================================================
# Purpose: Zips the entire project and performs an atomic swap on the VPS.
# ==============================================================================

$ErrorActionPreference = "Stop"

# --- Load Utilities & Config ---
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $scriptDir) { $scriptDir = $PSScriptRoot }
if (-not $scriptDir) { $scriptDir = Get-Location }

$utilsPath = Join-Path $scriptDir "shared_utils.ps1"
if (Test-Path $utilsPath) {
    . "$utilsPath"
} else {
    throw "Could not find shared_utils.ps1 at $utilsPath"
}

# Final Verification that functions loaded
if (-not (Get-Command Invoke-PreFlight -ErrorAction SilentlyContinue)) {
    throw "Fatal Error: shared_utils.ps1 was found but failed to load functions into scope."
}

# ==============================================================================
# PHASE 0: PRE-FLIGHT (GATEKEEPER)
# ==============================================================================
# We verify the VPS is alive and ready BEFORE we spend time zipping the project.
Invoke-PreFlight

# Enable Long Path Support for .NET
$longZipFile = "\\?\$zipFile"

# --- Cleanup Logic (Trap for Ctrl+C or Errors) ---
trap { Cleanup-Processes; exit 1 }

if (!(Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }
if (Test-Path $zipFile) { Remove-Item $zipFile }

# ==============================================================================
# PHASE 1: PACKAGING
# ==============================================================================
Write-Stage "SYNC" "Packaging project (Filtering on-the-fly)..."

# Load .syncignore patterns
$ignoreRegex = Get-IgnoreRegex

# Use .NET ZipArchive for true on-the-fly zipping (no temp copies)
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$stream = [System.IO.File]::Open($longZipFile, [System.IO.FileMode]::Create)
$archive = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)

$files = Get-ChildItem -Path $projectRoot -Recurse -File
if (-not $files) {
    Write-Host "[ERROR] No files found in $projectRoot!" -ForegroundColor Red
    Write-Host "Sync aborted to prevent wiping the remote production directory." -ForegroundColor Yellow
    exit 1
}

$bs = [char]92

foreach ($file in $files) {
    # Robust case-insensitive relative path calculation
    $relativePath = $file.FullName
    if ($relativePath.StartsWith($projectRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relativePath = $relativePath.Substring($projectRoot.Length).TrimStart($bs)
    }
    
    # Check against ignore list
    if ($ignoreRegex -and ($relativePath -match $ignoreRegex)) { continue }

    # Zip entries MUST use forward slash
    $zipEntryPath = $relativePath.Replace($bs, "/")
    $entry = $archive.CreateEntry($zipEntryPath)
    $entryStream = $entry.Open()
    try {
        $fileStream = [System.IO.File]::OpenRead($file.FullName)
        $fileStream.CopyTo($entryStream)
        $fileStream.Close()
    } catch {
        Write-Host "[WARN] Warning: Could not read $($file.Name). It might be locked by another process. Skipping." -ForegroundColor Yellow
    }
    $entryStream.Close()
}
$archive.Dispose()
$stream.Close()

$localHash = (Get-FileHash $zipFile -Algorithm MD5).Hash.ToLower()
Write-Host "[OK] Zip created: $((Get-Item $zipFile).Length / 1MB -as [int])MB (MD5: $localHash)" -ForegroundColor Green

# ==============================================================================
# PHASE 2: TRANSFER & STAGING
# ==============================================================================
Write-Stage "SYNC" "Uploading and verifying payload..."

Write-Host "[START] Preparing remote sync directory..." -ForegroundColor Gray
plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" "mkdir -p $REMOTE_STAGE_DIR; rm -rf $REMOTE_STAGE_DIR/*"
if ($LASTEXITCODE -ne 0) { throw "Failed to initialize remote staging directory." }

Write-Host "[UPLOAD] Uploading payload..." -ForegroundColor Yellow
pscp -batch -pw $VPS_PW $zipFile "$($VPS_USER)@$($VPS_IP):$REMOTE_SYNC_DIR/deploy.zip"
if ($LASTEXITCODE -ne 0) { throw "Failed to upload zip archive to VPS." }

Write-Host "[VERIFY] Verifying integrity..." -ForegroundColor Yellow
$remoteHashResult = plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" "md5sum $REMOTE_SYNC_DIR/deploy.zip"
$remoteHash = ($remoteHashResult -split " ")[0].ToLower()

if ($localHash -ne $remoteHash) {
    Write-Host "[ERROR] ERROR: Integrity check failed!" -ForegroundColor Red
    Write-Host "   Local MD5:  $localHash"
    Write-Host "   Remote MD5: $remoteHash"
    plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" "rm $REMOTE_SYNC_DIR/deploy.zip"
    exit 1
}
Write-Host "[OK] Integrity verified (Hashes match)." -ForegroundColor Green

Write-Host "[EXTRACT] Extracting on VPS..." -ForegroundColor Yellow
plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" "unzip -q -o $REMOTE_SYNC_DIR/deploy.zip -d $REMOTE_STAGE_DIR; rm $REMOTE_SYNC_DIR/deploy.zip"
if ($LASTEXITCODE -ne 0) { throw "Failed to extract zip on VPS." }

# ==============================================================================
# PHASE 3: SYNC
# ==============================================================================
Write-Stage "SYNC" "Performing atomic mirror to production..."

# Construct rsync exclude flags from ignore list to protect persistent remote files
$rsyncExcludes = ""
$ignoreList = New-Object System.Collections.Generic.List[string]
foreach ($prop in $IGNORE_CONFIG.PSObject.Properties) {
    if ($prop.Value -is [Array]) {
        foreach ($item in $prop.Value) {
            if ($item) { 
                $clean = $item.Trim().Replace("\", "/")
                $rsyncExcludes += " --exclude '$clean'"
            }
        }
    }
}

$cmd1 = "rsync -av --delete $rsyncExcludes $REMOTE_STAGE_DIR/ $REMOTE_PROD_DIR/"
$cmd2 = "if [ -d $REMOTE_PROD_DIR/scripts ]; then find $REMOTE_PROD_DIR/scripts -type f -name '*.sh' -exec chmod +x {} +; fi"
$syncCmds = "$cmd1; $cmd2"

plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" $syncCmds
if ($LASTEXITCODE -ne 0) { throw "Atomic rsync failed. Production directory might be inconsistent." }

# Verify critical files exist after sync
Write-Host "[VERIFY] Verifying critical files in $REMOTE_PROD_DIR..." -ForegroundColor Yellow
$checkFile = if ($COMPOSE_FILE) { $COMPOSE_FILE } else { "docker-compose.yml" }
$verifyCmd = "if [ ! -f $REMOTE_PROD_DIR/$checkFile ]; then echo 'MISSING_COMPOSE_FILE'; fi"
$verifyRes = plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" $verifyCmd
if ($verifyRes -match "MISSING_COMPOSE_FILE") {
    throw "Critical Error: $checkFile was not found in $REMOTE_PROD_DIR after sync. Sync failed to place files correctly."
}
Write-Host "[OK] Sync verified. $checkFile found." -ForegroundColor Green

# ==============================================================================
# PHASE 4: CLEANUP
# ==============================================================================
Write-Stage "SYNC" "Cleaning up..."
if (Test-Path $zipFile) { Remove-Item $zipFile }
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" "rm -rf `"$REMOTE_SYNC_DIR`""

Write-Host "`n[OK] SYNC WORKER FINISHED" -ForegroundColor Green
