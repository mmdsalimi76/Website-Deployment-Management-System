@echo off
SET SCRIPT_PATH=%~dp0check_status.ps1
powershell -ExecutionPolicy Bypass -File "%SCRIPT_PATH%"
pause
