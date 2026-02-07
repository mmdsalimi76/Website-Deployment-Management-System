# ==============================================================================
# 🗄️ Database Utilities (Core Logic)
# ==============================================================================

# Note: This utility script assumes DB_CONFIG is already loaded via shared_utils.ps1

function Get-DBConfig { return $DB_CONFIG }

function Test-ContainerExists {
    param([string]$ContainerName)
    $res = plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" "docker inspect -f '{{.State.Running}}' $ContainerName 2>/dev/null"
    return ($res -eq "true")
}

function Get-FileMD5Local {
    param([string]$FilePath)
    return (Get-FileHash $FilePath -Algorithm MD5).Hash.ToLower()
}

function Get-FileMD5Remote {
    param([string]$RemotePath)
    $res = plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" "md5sum $RemotePath 2>/dev/null"
    if ($res -match "^([a-f0-9]+)\s+") {
        return $matches[1]
    }
    return $null
}

function Invoke-RemoteBackup {
    param(
        [string]$ContainerName = $DB_CONFIG.DB_CONTAINER_NAME,
        [string]$DbName = $DB_CONFIG.DB_NAME,
        [string]$User = $DB_CONFIG.DB_USER
    )

    if (-not (Test-ContainerExists $ContainerName)) {
        Write-Host "[WARN] Container $ContainerName not found or not running. Skipping backup (First deploy?)" -ForegroundColor Yellow
        return $null
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $filename = "backup_$($DbName)_$($timestamp).sql.gz"
    $remotePath = "$($DB_CONFIG.BACKUP_DIR_REMOTE)/$filename"

    Write-Header "DATABASE BACKUP"
    Write-Stage "REMOTE" "Creating backup on VPS: $filename"

    plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" "mkdir -p $($DB_CONFIG.BACKUP_DIR_REMOTE)"

    # Execute pg_dump and compress (using set -o pipefail to catch pg_dump errors)
    $backupCmd = "docker exec $ContainerName bash -c 'set -o pipefail; pg_dump -U $User $DbName | gzip' > $remotePath"
    plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" $backupCmd

    # Check if file exists and has size > 0
    $checkCmd = "if [ -s $remotePath ]; then echo 'SUCCESS'; else echo 'EMPTY'; fi"
    $checkRes = plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" $checkCmd

    if ($LASTEXITCODE -eq 0 -and $checkRes -match "SUCCESS") {
        Write-Host "[OK] Backup created successfully at $remotePath" -ForegroundColor Green
        return $filename
    } else {
        Write-Host "[ERROR] Backup failed or file is empty! Check database connectivity and user permissions." -ForegroundColor Red
        # Cleanup empty file if exists
        plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" "rm -f $remotePath"
        return $null
    }
}

function Pull-BackupToLocal {
    param([string]$Filename)
    if (-not $Filename) { return $false }

    $remotePath = "$($DB_CONFIG.BACKUP_DIR_REMOTE)/$Filename"
    $localDir = $DB_CONFIG.BACKUP_DIR_LOCAL
    # If it's a relative path, resolve it relative to the scripts root
    if ($localDir.StartsWith("./") -or -not (Split-Path $localDir -IsAbsolute)) { 
        $localDir = Join-Path (Split-Path -Parent $PSScriptRoot) ($localDir.TrimStart("./")) 
    }
    
    if (-not (Test-Path $localDir)) { New-Item -ItemType Directory -Path $localDir | Out-Null }
    $localPath = Join-Path $localDir $Filename

    Write-Stage "LOCAL" "Pulling backup with Integrity Handshake..."
    pscp -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP):$remotePath" "$localPath"

    if ($LASTEXITCODE -eq 0) {
        $remoteHash = Get-FileMD5Remote $remotePath
        $localHash = Get-FileMD5Local $localPath
        
        if ($remoteHash -eq $localHash) {
            Write-Host "[OK] Integrity Verified (MD5: $localHash)" -ForegroundColor Green
            return $true
        } else {
            Write-Host "[ERROR] Integrity Mismatch! Remote: $remoteHash vs Local: $localHash" -ForegroundColor Red
            return $false
        }
    }
    return $false
}

function Restore-RemoteDatabase {
    param(
        [string]$Filename,
        [string]$ContainerName = $DB_CONFIG.DB_CONTAINER_NAME,
        [string]$DbName = $DB_CONFIG.DB_NAME,
        [string]$User = $DB_CONFIG.DB_USER
    )

    if (-not $Filename) { return $false }
    if (-not (Test-ContainerExists $ContainerName)) {
        Write-Host "[ERROR] Cannot restore: Container $ContainerName not found." -ForegroundColor Red
        return $false
    }

    Write-Header "DATABASE ROLLBACK"
    $remotePath = "$($DB_CONFIG.BACKUP_DIR_REMOTE)/$Filename"
    
    $restoreCmd = "gunzip -c $remotePath | docker exec -i $ContainerName psql -U $User -d $DbName"
    plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" $restoreCmd

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Database restored successfully." -ForegroundColor Green
        return $true
    }
    return $false
}

function Invoke-Migrations {
    param([string]$WebContainer = $DB_CONFIG.WEB_CONTAINER_NAME)

    if (-not (Test-ContainerExists $WebContainer)) {
        Write-Host "[ERROR] Migration failed: Container $WebContainer not found." -ForegroundColor Red
        return
    }

    Write-Header "DATABASE MIGRATIONS"
    Write-Stage "REMOTE" "Running migrations on $WebContainer..."
    plink -batch -pw $VPS_PW "$($VPS_USER)@$($VPS_IP)" "docker exec $WebContainer python manage.py migrate"

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Migrations completed successfully." -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Migrations failed!" -ForegroundColor Red
    }
}
