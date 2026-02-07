<#
.SYNOPSIS
    Interactive Config Manager for the Website Deployment System.
    Allows easy modification of VPS settings, paths, and container names.
#>

$ErrorActionPreference = "Stop"

# --- Setup Paths ---
$scriptRoot = $PSScriptRoot
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)

# Config Files
$configs = @{
    "Global" = Join-Path $projectRoot "scripts\sync\global_config.json"
    "Database" = Join-Path $projectRoot "scripts\database\db_config.json"
    "Docker" = Join-Path $projectRoot "scripts\docker-compose\compose_config.json"
    "Infrastructure" = Join-Path $projectRoot "scripts\infrastructure\infrastructure_config.json"
    "VPSMgmt" = Join-Path $projectRoot "scripts\vps management\vps_config.json"
    "Ignore" = Join-Path $projectRoot "scripts\sync\sync_ignore.json"
}

function Load-Json ($path) {
    if (Test-Path $path) { return Get-Content $path | ConvertFrom-Json }
    return $null
}

function Save-Json ($path, $obj) {
    $obj | ConvertTo-Json -Depth 10 | Set-Content $path
}

function Show-SplitMenu {
    param($dbC, $infraC, $globalC, $dockerC, $vpsC, $ignoreC)

    $firstDeploy = if ($dbC) { $dbC.FIRST_DEPLOY } else { "ERROR" }
    $ignorePrefix = if ($infraC) { $infraC.IMAGE_FILTERS.IGNORE_PREFIX } else { "ERROR" }
    
    # Left Side Lines (Menu)
    $left = @(
        " 1. Edit Global Settings (VPS, Paths)",
        " 2. Edit Database Settings (Containers, Mode)",
        " 3. Edit Docker Settings (Compose File)",
        " 4. Edit Infrastructure Settings (Sideloading)",
        " 5. Edit VPS Management Settings (Logs, Services)",
        " 6. Edit Sync Ignore Patterns (JSON)",
        " ---------------------------------------",
        " f. Toggle [FIRST_DEPLOY]",
        " i. Change [IGNORE_PREFIX]",
        " ---------------------------------------",
        " q. Exit"
    )

    # Right Side Lines (Categorized Dashboard)
    $right = New-Object System.Collections.Generic.List[string]
    $null = $right.Add(" [VPS CONNECTION]")
    $null = $right.Add(" IP       : $($globalC.VPS_CONNECTION.IP)")
    $null = $right.Add(" User     : $($globalC.VPS_CONNECTION.USER)")
    $null = $right.Add(" Password : $($globalC.VPS_CONNECTION.PASSWORD)")
    $null = $right.Add(" ")
    $null = $right.Add(" [PATHS & DOCKER]")
    $null = $right.Add(" Compose  : $($dockerC.COMPOSE_FILE)")
    $null = $right.Add(" Remote   : $($dockerC.REMOTE_PROJECT_ROOT)")
    $null = $right.Add(" Local    : $($globalC.PROJECT_METADATA.LOCAL_ROOT)")
    $null = $right.Add(" ")
    $null = $right.Add(" [DATABASE SETTINGS]")
    $null = $right.Add(" Container: $($dbC.DB_CONTAINER_NAME)")
    $null = $right.Add(" DB Name  : $($dbC.DB_NAME)")
    $null = $right.Add(" DB User  : $($dbC.DB_USER)")
    $null = $right.Add(" ")
    $null = $right.Add(" [MANAGED SERVICES]")
    if ($vpsC.SERVICES) {
        foreach ($prop in $vpsC.SERVICES.PSObject.Properties) {
            $null = $right.Add(" $($prop.Name.PadRight(10)): $($prop.Value)")
        }
    } else {
        $null = $right.Add(" (None defined)")
    }
    $null = $right.Add(" ")
    $null = $right.Add(" [SYNC IGNORE SUMMARY]")
    if ($ignoreC) {
        foreach ($prop in $ignoreC.PSObject.Properties) {
            $count = if ($prop.Value -is [Array]) { $prop.Value.Count } else { 0 }
            $null = $right.Add(" $($prop.Name.PadRight(15)): $count patterns")
        }
    } else {
        $null = $right.Add(" (No ignore list found)")
    }
    $null = $right.Add(" ")
    $null = $right.Add(" [FLAGS & FILTERS]")
    $null = $right.Add(" 1stDeploy: $firstDeploy")
    $null = $right.Add(" IgnorePre: $ignorePrefix")

    Write-Host "==========================================================================================================" -ForegroundColor Yellow
    Write-Host "      WEBSITE CONFIGURATION MANAGER                                   SYSTEM DASHBOARD (LIVE)" -ForegroundColor White
    Write-Host "==========================================================================================================" -ForegroundColor Yellow

    $maxLines = [Math]::Max($left.Count, $right.Count)
    for ($i = 0; $i -lt $maxLines; $i++) {
        $lText = if ($i -lt $left.Count) { $left[$i] } else { "" }
        $rText = if ($i -lt $right.Count) { $right[$i] } else { "" }
        
        # Increased padding to 65 to move dashboard further right
        $lLine = $lText.PadRight(65)
        
        Write-Host "$lLine | " -NoNewline -ForegroundColor Yellow
        
        # Color code the right side categories
        if ($rText -match "\[.*\]") {
            Write-Host $rText -ForegroundColor Cyan
        } elseif ($rText -match "ERROR") {
            Write-Host $rText -ForegroundColor Red
        } else {
            Write-Host $rText -ForegroundColor Gray
        }
    }
    Write-Host "==========================================================================================================" -ForegroundColor Yellow
}

function Edit-GlobalConfig {
    $c = Load-Json $configs.Global
    Write-Host "`n--- GLOBAL CONFIG ---" -ForegroundColor Cyan
    Write-Host "1. VPS IP       : $($c.VPS_CONNECTION.IP)"
    Write-Host "2. VPS User     : $($c.VPS_CONNECTION.USER)"
    Write-Host "3. VPS Password : $($c.VPS_CONNECTION.PASSWORD)"
    Write-Host "4. Remote Root  : $($c.REMOTE_PATHS.PROD_DIR)"
    Write-Host "5. Local Root   : $($c.PROJECT_METADATA.LOCAL_ROOT)"
    Write-Host "b. Back"

    $opt = Read-Host "`nSelect field to edit"
    switch ($opt) {
        "1" { $c.VPS_CONNECTION.IP = Read-Host "Enter new IP"; Save-Json $configs.Global $c }
        "2" { $c.VPS_CONNECTION.USER = Read-Host "Enter new User"; Save-Json $configs.Global $c }
        "3" { $c.VPS_CONNECTION.PASSWORD = Read-Host "Enter new Password"; Save-Json $configs.Global $c }
        "4" { $c.REMOTE_PATHS.PROD_DIR = Read-Host "Enter new Remote Root"; Save-Json $configs.Global $c }
        "5" { $c.PROJECT_METADATA.LOCAL_ROOT = Read-Host "Enter new Local Root"; Save-Json $configs.Global $c }
        "b" { return }
    }
}

function Edit-DatabaseConfig {
    $c = Load-Json $configs.Database
    Write-Host "`n--- DATABASE CONFIG ---" -ForegroundColor Cyan
    Write-Host "1. DB Container   : $($c.DB_CONTAINER_NAME)"
    Write-Host "2. Web Container  : $($c.WEB_CONTAINER_NAME)"
    Write-Host "3. [FLAG] First Deploy : $($c.FIRST_DEPLOY)"
    Write-Host "b. Back"

    $opt = Read-Host "`nSelect field to edit"
    switch ($opt) {
        "1" { $c.DB_CONTAINER_NAME = Read-Host "Enter Container Name"; Save-Json $configs.Database $c }
        "2" { $c.WEB_CONTAINER_NAME = Read-Host "Enter Web Container"; Save-Json $configs.Database $c }
        "3" { $c.FIRST_DEPLOY = ($c.FIRST_DEPLOY -eq $false); Save-Json $configs.Database $c }
        "b" { return }
    }
}

function Edit-DockerConfig {
    $c = Load-Json $configs.Docker
    Write-Host "`n--- DOCKER CONFIG ---" -ForegroundColor Cyan
    Write-Host "1. Compose File : $($c.COMPOSE_FILE)"
    Write-Host "2. Remote Root  : $($c.REMOTE_PROJECT_ROOT)"
    Write-Host "b. Back"

    $opt = Read-Host "`nSelect field to edit"
    switch ($opt) {
        "1" { $c.COMPOSE_FILE = Read-Host "Enter Compose Filename"; Save-Json $configs.Docker $c }
        "2" { $c.REMOTE_PROJECT_ROOT = Read-Host "Enter Remote Project Root"; Save-Json $configs.Docker $c }
        "b" { return }
    }
}

function Edit-InfrastructureConfig {
    $c = Load-Json $configs.Infrastructure
    Write-Host "`n--- INFRASTRUCTURE CONFIG ---" -ForegroundColor Cyan
    Write-Host "1. Temp Bin Dir : $($c.SIDELOAD_SETTINGS.TEMP_BIN_DIR)"
    Write-Host "2. Hash File    : $($c.SIDELOAD_SETTINGS.HASH_FILE)"
    Write-Host "3. Prod Compose : $($c.SIDELOAD_SETTINGS.COMPOSE_PROD_FILE)"
    Write-Host "4. [FLAG] Ignore Prefix: $($c.IMAGE_FILTERS.IGNORE_PREFIX)"
    Write-Host "b. Back"

    $opt = Read-Host "`nSelect field to edit"
    switch ($opt) {
        "1" { $c.SIDELOAD_SETTINGS.TEMP_BIN_DIR = Read-Host "Enter Temp Bin Dir"; Save-Json $configs.Infrastructure $c }
        "2" { $c.SIDELOAD_SETTINGS.HASH_FILE = Read-Host "Enter Hash Filename"; Save-Json $configs.Infrastructure $c }
        "3" { $c.SIDELOAD_SETTINGS.COMPOSE_PROD_FILE = Read-Host "Enter Prod Compose File"; Save-Json $configs.Infrastructure $c }
        "4" { $c.IMAGE_FILTERS.IGNORE_PREFIX = Read-Host "Enter Ignore Prefix"; Save-Json $configs.Infrastructure $c }
        "b" { return }
    }
}

function Edit-VPSMgmtConfig {
    $c = Load-Json $configs.VPSMgmt
    $g = Load-Json $configs.Global
    
    $serviceCount = 0
    if ($c.SERVICES) {
        $serviceCount = $c.SERVICES.PSObject.Properties.Count
    }

    Write-Host "`n--- VPS & SERVICE SETTINGS ---" -ForegroundColor Cyan
    Write-Host "1. VPS IP        : $($g.VPS_CONNECTION.IP)"
    Write-Host "2. SSH User      : $($g.VPS_CONNECTION.USER)"
    Write-Host "3. SSH Password  : $($g.VPS_CONNECTION.PASSWORD)"
    Write-Host "4. Managed Services: ($serviceCount defined)"
    Write-Host "b. Back"

    $opt = Read-Host "`nSelect field to edit"
    switch ($opt) {
        "1" { $g.VPS_CONNECTION.IP = Read-Host "Enter new IP"; Save-Json $configs.Global $g }
        "2" { $g.VPS_CONNECTION.USER = Read-Host "Enter new User"; Save-Json $configs.Global $g }
        "3" { $g.VPS_CONNECTION.PASSWORD = Read-Host "Enter new Password"; Save-Json $configs.Global $g }
        "4" { 
            Write-Host "`n--- Current Services ---"
            $props = $c.SERVICES.PSObject.Properties
            foreach ($p in $props) { Write-Host "$($p.Name): $($p.Value)" }
            Write-Host "------------------------"
            Write-Host "[+] To add/update: Enter 'KEY=VALUE' (e.g. REDIS=redis_container)"
            Write-Host "[-] To remove: Enter 'KEY' only"
            $input = Read-Host "`nService entry"
            if ($input -match "=") {
                $parts = $input -split "="
                $c.SERVICES | Add-Member -MemberType NoteProperty -Name $parts[0].Trim() -Value $parts[1].Trim() -Force
            } elseif ($input) {
                $c.SERVICES.PSObject.Properties.Remove($input.Trim())
            }
            Save-Json $configs.VPSMgmt $c
        }
        "b" { return }
    }
}

function Edit-IgnoreConfig {
    $c = Load-Json $configs.Ignore
    if (-not $c) { Write-Host "[ERROR] Ignore file not found." -ForegroundColor Red; return }

    while ($true) {
        Write-Host "`n--- SYNC IGNORE SETTINGS ---" -ForegroundColor Cyan
        $props = $c.PSObject.Properties
        $i = 1
        $map = @{}
        foreach ($p in $props) {
            Write-Host "$i. $($p.Name) ($($p.Value.Count) patterns)"
            $map[$i] = $p.Name
            $i++
        }
        Write-Host "b. Back"

        $opt = Read-Host "`nSelect category to edit"
        if ($opt -eq "b") { break }
        if ($map.ContainsKey([int]$opt)) {
            $cat = $map[[int]$opt]
            Write-Host "`n--- Patterns in $cat ---"
            $patterns = $c.$cat
            for ($j=0; $j -lt $patterns.Count; $j++) {
                Write-Host "$($j+1). $($patterns[$j])"
            }
            Write-Host "------------------------"
            Write-Host "[+] To add: Enter 'pattern'"
            Write-Host "[-] To remove: Enter '-number' (e.g. -2)"
            $input = Read-Host "`nAction"
            
            if ($input.StartsWith("-")) {
                $remIdx = [int]($input.Substring(1)) - 1
                if ($remIdx -ge 0 -and $remIdx -lt $patterns.Count) {
                    $newPatterns = New-Object System.Collections.Generic.List[string]($patterns)
                    $newPatterns.RemoveAt($remIdx)
                    $c.$cat = $newPatterns.ToArray()
                }
            } elseif ($input) {
                $newPatterns = New-Object System.Collections.Generic.List[string]($patterns)
                $newPatterns.Add($input.Trim())
                $c.$cat = $newPatterns.ToArray()
            }
            Save-Json $configs.Ignore $c
        }
    }
}

# --- Main Loop ---
while ($true) {
    # Load all configs for the dashboard
    $dbC = Load-Json $configs.Database
    $infraC = Load-Json $configs.Infrastructure
    $globalC = Load-Json $configs.Global
    $dockerC = Load-Json $configs.Docker
    $vpsC = Load-Json $configs.VPSMgmt
    $ignoreC = Load-Json $configs.Ignore

    Clear-Host
    Show-SplitMenu -dbC $dbC -infraC $infraC -globalC $globalC -dockerC $dockerC -vpsC $vpsC -ignoreC $ignoreC

    $choice = Read-Host "`nSelect an option"
    switch ($choice) {
        "1" { Edit-GlobalConfig }
        "2" { Edit-DatabaseConfig }
        "3" { Edit-DockerConfig }
        "4" { Edit-InfrastructureConfig }
        "5" { Edit-VPSMgmtConfig }
        "6" { Edit-IgnoreConfig }
        "f" { 
            if ($dbC) { 
                $dbC.FIRST_DEPLOY = -not $dbC.FIRST_DEPLOY
                Save-Json $configs.Database $dbC
            }
        }
        "i" { 
            if ($infraC) { 
                $infraC.IMAGE_FILTERS.IGNORE_PREFIX = Read-Host "Enter new Ignore Prefix"
                Save-Json $configs.Infrastructure $infraC
            }
        }
        "q" { exit }
    }
}
