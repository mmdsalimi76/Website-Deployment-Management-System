DATABASE SCRIPTS TOOLKIT
========================

This folder contains scripts for managing the PostgreSQL database on the remote VPS.

CORE SCRIPTS:
-------------
- database_manager.ps1  : Interactive UI for database operations (Backup, Restore, Migrate).
- database_manager.bat  : One-click launcher for the manager.
- auto_backup.ps1       : Non-interactive script for automated safety backups before deployments.
- auto_migrate.ps1      : Triggers Django migrations remotely.
- database_utils.ps1    : Internal utility library for MD5 integrity and container probing.

CONFIGURATION:
--------------
- db_config.json        : Central configuration for container names and critical services.

SAFETY FEATURES:
----------------
- MD5 Handshake: All backups are verified using MD5 checksums after transfer.
- Container Probing: Scripts verify the database container is running before attempting operations.
- Versioned Backups: Backups are stored with timestamps on both local and remote machines.

WORKFLOW INTEGRATION:
---------------------
The auto_backup.ps1 script is automatically triggered by the selective_patch.ps1 script 
to ensure a safety point exists before any code changes are applied.
