==============================================================================
WEBSITE DEPLOYMENT SYSTEM (AIR-GAPPED SYNC)
==============================================================================

This folder contains the synchronization tools for deploying the website 
from a local Windows machine to an air-gapped Linux VPS.

------------------------------------------------------------------------------
SCRIPTS OVERVIEW
------------------------------------------------------------------------------

1. LAUNCH_PATCH.bat
   - The primary entry point for the Selective Patch tool.
   - Prevents the PowerShell window from closing immediately on error.
   - Recommended way to run the patch tool.

2. full_sync.ps1 (The Atomic Hammer)
   - Performs a complete mirroring of the local project to the VPS.
   - Uses an atomic swap: zips -> uploads -> extracts to stage -> rsync to prod.
   - Best for first-time deployments or major structural changes.

3. selective_patch.ps1 (The Surgical Scalpel)
   - Allows you to pick specific files/folders to update.
   - Only transfers and replaces the selected files.
   - Prompts for a dynamic Docker container rebuild after patching.

4. shared_utils.ps1
   - Central logic for both scripts.
   - Handles VPS configuration, ignore patterns, and Pre-Flight checks.

------------------------------------------------------------------------------
KEY FEATURES
------------------------------------------------------------------------------

- Air-Gap Resilience: Automatically detects missing 'rsync' or 'unzip' on the 
  VPS and sideloads static binaries from the 'binaries/' folder.
- Dynamic Rebuilds: Queries the VPS for active services and lets you choose 
  which ones to restart after a patch.
- Filter-on-the-fly: Respects the '.syncignore' file to exclude large or 
  unnecessary files (like node_modules, .git, etc.) without creating temp folders.
- Integrity First: Uses MD5 hashing to verify that uploads were 100% successful.

------------------------------------------------------------------------------
USAGE NOTES
------------------------------------------------------------------------------

- Prerequisites: None. This is a portable application; all tools are in scripts/bin/.
- Configuration: Managed via the 'Config Manager' in the master interface.
- Ignore List: Edit '.syncignore' in the scripts/sync/ folder to exclude files.

==============================================================================
Designed for PowerShell 5.1 Compatibility.
==============================================================================
