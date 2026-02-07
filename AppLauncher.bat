@echo off
SETLOCAL EnableDelayedExpansion

:: --- Website Application Launcher ---
:: Purpose: Sets up the portable environment and launches the Master Interface.

SET "APP_ROOT=%~dp0"
SET "BIN_DIR=%APP_ROOT%bin"

:: 1. Verify Binaries
if not exist "%BIN_DIR%\plink.exe" (
    echo [ERROR] Core binaries missing in %BIN_DIR%. 
    echo Please ensure plink.exe and pscp.exe are in the 'bin' folder.
    pause
    exit /b 1
)

:: 2. Set Local Path (Prioritize bundled tools)
SET "PATH=%BIN_DIR%;%PATH%"

:: 3. Launch Master Interface
echo Launching Website Control Center...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%APP_ROOT%master_interface.ps1"

ENDLOCAL
pause