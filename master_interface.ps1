<#
.SYNOPSIS
    WEBSITE MASTER INTERFACE
    The central hub for all deployment and management scripts.
#>

$ErrorActionPreference = "Stop"

# --- Setup Paths ---
$scriptsDir = $PSScriptRoot
if (-not $scriptsDir) { $scriptsDir = Get-Location }

# GLOBAL PROTECTION: Prevent Ctrl+C from killing the process
[console]::TreatControlCAsInput = $true

# Define Script Paths relative to the scripts root
$paths = @{
    "DeployMaster"    = Join-Path $scriptsDir "orchestration\deploy_master.ps1"
    "ConfigManager"   = Join-Path $scriptsDir "orchestration\config_manager.ps1"
    "PatchManager"    = Join-Path $scriptsDir "sync\selective_patch.ps1"
    "DBManager"       = Join-Path $scriptsDir "database\database_manager.ps1"
    "DockerManager"   = Join-Path $scriptsDir "docker-compose\compose_manager.ps1"
    "InfraSideload"   = Join-Path $scriptsDir "infrastructure\sideload_images.ps1"
    "DockerStatus"    = Join-Path $scriptsDir "docker-compose\check_status.ps1"
    "VPSManager"      = Join-Path $scriptsDir "vps management\vps_manager.ps1"
}

# Config File Paths for Flag Display
$configFiles = @{
    "Global" = Join-Path $scriptsDir "sync\global_config.json"
    "Database" = Join-Path $scriptsDir "database\db_config.json"
    "Docker" = Join-Path $scriptsDir "docker-compose\compose_config.json"
    "Infra" = Join-Path $scriptsDir "infrastructure\infrastructure_config.json"
}

function Get-ConfigFlags {
    $flags = @{
        "IP" = "NOT SET"
        "FIRST_DEPLOY" = "False"
        "COMPOSE" = "NOT SET"
        "IGNORE" = "NONE"
    }

    try {
        if (Test-Path $configFiles.Global) {
            $c = Get-Content $configFiles.Global | ConvertFrom-Json
            if ($c.VPS_CONNECTION.IP) { $flags.IP = $c.VPS_CONNECTION.IP }
        }
        if (Test-Path $configFiles.Database) {
            $c = Get-Content $configFiles.Database | ConvertFrom-Json
            $flags.FIRST_DEPLOY = $c.FIRST_DEPLOY.ToString()
        }
        if (Test-Path $configFiles.Docker) {
            $c = Get-Content $configFiles.Docker | ConvertFrom-Json
            if ($c.COMPOSE_FILE) { $flags.COMPOSE = $c.COMPOSE_FILE }
        }
        if (Test-Path $configFiles.Infra) {
            $c = Get-Content $configFiles.Infra | ConvertFrom-Json
            if ($c.IMAGE_FILTERS.IGNORE_PREFIX) { $flags.IGNORE = $c.IMAGE_FILTERS.IGNORE_PREFIX }
        }
    } catch {
        # Silent fail for flags
    }
    return $flags
}

function Show-MainSplitMenu {
    param($f, $scriptsDir)

    # Left Side Lines (Menu)
    $left = @(
        " [1]  END-TO-END PRODUCTION SYNC (Full Pipeline)",
        " [2]  Configuration Manager (VPS, Paths, JSON)",
        " [3]  Commit & Push (Selective Patch: Local -> VPS)",
        " [4]  Database Operations (Backup, Restore, Migrate)",
        " [5]  Docker Compose Management (Up, Down, Build)",
        " [6]  Infrastructure Sideloading (Docker Images)",
        " [7]  Quick Status Check (Remote Containers)",
        " [8]  VPS Management (Terminal & Logs)",
        " ------------------------------------------------",
        " [q]  Exit"
    )

    # Right Side Lines (Dashboard & Hints)
    $right = New-Object System.Collections.Generic.List[string]
    $null = $right.Add(" [CURRENT CONFIGURATION]")
    $null = $right.Add(" APP ROOT : $scriptsDir")
    $null = $right.Add(" VPS IP   : $($f.IP)")
    $null = $right.Add(" COMPOSE  : $($f.COMPOSE)")
    $null = $right.Add(" 1stDeploy: $($f.FIRST_DEPLOY)")
    $null = $right.Add(" IgnorePre: $($f.IGNORE)")
    $null = $right.Add(" ")
    $null = $right.Add(" [SYSTEM HINTS]")
    $null = $right.Add(" -> Use Option [2] first to set your VPS IP")
    $null = $right.Add(" -> Option [3] is best for daily code updates")
    $null = $right.Add(" -> Option [1] is for full project-wide sync")
    $null = $right.Add(" -> Use [7] to check if services are alive")
    $null = $right.Add(" ")
    $null = $right.Add(" [FUNCTION INFO]")
    $null = $right.Add(" Patching : Rapid hot-swapping of specific files")
    $null = $right.Add(" Sideload : Offline image transfer (Bypasses Docker Hub)")
    $null = $right.Add(" DB Ops   : Secure remote dumps & local verification")

    Write-Host "==========================================================================================================" -ForegroundColor Yellow
    Write-Host "      WEBSITE SYSTEM CONTROL CENTER                                   SYSTEM DASHBOARD (LIVE)" -ForegroundColor White
    Write-Host "==========================================================================================================" -ForegroundColor Yellow

    $maxLines = [Math]::Max($left.Count, $right.Count)
    for ($i = 0; $i -lt $maxLines; $i++) {
        $lText = if ($i -lt $left.Count) { $left[$i] } else { "" }
        $rText = if ($i -lt $right.Count) { $right[$i] } else { "" }
        
        # Consistent padding with config_manager.ps1
        $lLine = $lText.PadRight(55)
        
        Write-Host " $lLine | " -NoNewline -ForegroundColor Yellow
        
        # Color code the right side categories
        if ($rText -match "\[.*\]") {
            Write-Host $rText -ForegroundColor Cyan
        } elseif ($rText -match "->") {
            Write-Host $rText -ForegroundColor Gray
        } elseif ($rText -match ":") {
            $parts = $rText -split ":", 2
            Write-Host "$($parts[0]):" -NoNewline -ForegroundColor Gray
            Write-Host $parts[1] -ForegroundColor White
        } else {
            Write-Host $rText -ForegroundColor Gray
        }
    }
    Write-Host "==========================================================================================================" -ForegroundColor Yellow
    Write-Host " [!] PLEASE CONFIGURE VARIABLES (OPTION 2) BEFORE USE" -ForegroundColor Yellow
}

function Run-Script ($path) {
    if (Test-Path $path) {
        Write-Host "`n>>> RUNNING: $(Split-Path $path -Leaf)" -ForegroundColor Cyan
        Push-Location (Split-Path $path)
        try {
            # Execute script in a way that doesn't terminate the parent on error
            & $path
        } catch [System.Management.Automation.PipelineStoppedException] {
            Write-Host "`n[NOTICE] Operation interrupted by user." -ForegroundColor Yellow
            $Error.Clear()
        } catch {
            Write-Host "`n[ERROR] Script execution interrupted or failed: $($_.Exception.Message)" -ForegroundColor Red
        } finally {
            Pop-Location
        }
        Write-Host "`n>>> FINISHED: $(Split-Path $path -Leaf)" -ForegroundColor Cyan
        Write-Host "Press any key to return to menu..." -ForegroundColor Gray
        $null = [Console]::ReadKey($true)
    } else {
        Write-Host "[ERROR] Script not found: $path" -ForegroundColor Red
        Start-Sleep -Seconds 2
    }
}

while ($true) {
    Clear-Host
    $f = Get-ConfigFlags
    Show-MainSplitMenu -f $f -scriptsDir $scriptsDir
    
    $choice = Read-Host "`nSelect an option"
    
    switch ($choice) {
        "1" { Run-Script $paths.DeployMaster }
        "2" { Run-Script $paths.ConfigManager }
        "3" { Run-Script $paths.PatchManager }
        "4" { Run-Script $paths.DBManager }
        "5" { Run-Script $paths.DockerManager }
        "6" { Run-Script $paths.InfraSideload }
        "7" { Run-Script $paths.DockerStatus }
        "8" { Run-Script $paths.VPSManager }
        "q" { exit }
    }
}
