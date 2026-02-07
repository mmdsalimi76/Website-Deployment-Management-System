================================================================================
          WEBSITE SYSTEM CONTROL CENTER - DOCUMENTATION & GUIDE
================================================================================

[ PURPOSE ]
This toolkit is a professional-grade deployment and management system designed
for modern web applications (specifically Django/Docker/Postgres) hosted on 
Linux VPS, but managed from a Windows development environment.

It bridges the gap between Windows (Dev) and Linux (Prod) using secure PuTTY-based 
tunnels (plink/pscp) and advanced synchronization tools (rsync/unzip).

[ TARGET ENVIRONMENT ]
- Local: Windows 10/11 (PowerShell 5.1+)
- Remote: Linux VPS (Ubuntu/Debian recommended)
- Stack: Docker, Docker Compose, PostgreSQL

--------------------------------------------------------------------------------
[ CORE MODULES & FLOWS ]
--------------------------------------------------------------------------------

1. END-TO-END PRODUCTION SYNC (Full Pipeline)
   ------------------------------------------
   - Purpose: Performs a complete project-wide synchronization.
   - Flow:
     a. Pre-flight checks (Connectivity, VPS tool availability).
     b. Local Archive: Zips the project (respecting sync_ignore.json).
     c. Transfer: Uses PSCP to move the zip to the VPS /tmp folder.
     d. Unzip: Remotely extracts files to the target APP_ROOT.
     e. Rsync Mirror: Uses rsync --delete to ensure the remote exactly matches
        local, while PROTECTING persistent data (media/logs) via ignore rules.
     f. Container Rebuild: Triggers docker-compose build and up -d.

2. CONFIGURATION MANAGER
   ---------------------
   - Purpose: Centralized GUI for managing all JSON-based configuration files.
   - Flow:
     a. Loads all variables from the /scripts subdirectories.
     b. Validates inputs (IP formats, path existence).
     c. Updates sync_ignore.json, global_config.json, etc.

3. SELECTIVE PATCHING (Rapid Hot-Swap)
   -----------------------------------
   - Purpose: Syncs specific changed files without a full deployment.
   - Flow:
     a. Identifies modified files (or manual selection).
     b. Transfers only those files via PSCP.
     c. Optionally restarts only the affected Docker service.

4. DATABASE OPERATIONS
   -------------------
   - Purpose: Secure remote DB management.
   - Flow:
     a. Backup: Executes pg_dump inside the remote Postgres container.
     b. Compression: Zips the dump on the VPS.
     c. Download: Pulls the backup to local Windows storage.
     d. Migrate: Runs remote 'python manage.py migrate' via plink.

5. DOCKER COMPOSE MANAGEMENT
   -------------------------
   - Purpose: Remote orchestration of container lifecycle.
   - Flow:
     a. Sends commands (Up, Down, Restart, Build) via plink.
     b. Reports real-time logs and status back to the Windows console.

6. INFRASTRUCTURE SIDELOADING
   --------------------------
   - Purpose: Transfers Docker Images directly (offline) to bypass Docker Hub restrictions for restricted countries.
   - Flow:
     a. Local Save: Saves a docker image to a .tar file.
     b. Transfer: Moves the .tar to the VPS.
     c. Remote Load: Executes 'docker load' on the VPS.

7. VPS MANAGEMENT
   -----------------
   - Purpose: Direct access to the remote machine.
   - Flow:
     a. Terminal: Launches a pre-authenticated SSH session via plink.
     b. Logs: Tails system or application logs directly to Windows console.

--------------------------------------------------------------------------------
[ SAFETY & PROTECTION ]
--------------------------------------------------------------------------------
- SYNC PROTECTION: The system uses sync_ignore.json to ensure that remote
  directories like 'media/', 'logs/', and '.env' are NEVER deleted or
  overwritten during a full sync.
- ATOMIC OPERATIONS: The deployment uses a temporary zip-then-rsync approach
  to ensure the application remains stable during the transfer process.
- VALIDATION: Every remote action starts with a health check to verify the
  target IP and required Linux tools (unzip, rsync, docker) are present.

--------------------------------------------------------------------------------
[ GETTING STARTED ]
--------------------------------------------------------------------------------
1. Open PowerShell and run AppLauncher.bat or master_interface.ps1.
2. Go to [2] Configuration Manager first.
3. Set your VPS IP, SSH Credentials, and APP_ROOT.
4. Run [7] Quick Status Check to verify connectivity.
================================================================================
