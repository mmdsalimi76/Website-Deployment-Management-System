@echo off
SETLOCAL
SET SCRIPT_PATH=%~dp0config_manager.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%"
ENDLOCAL
pause