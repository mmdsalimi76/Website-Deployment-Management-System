@echo off
SET SCRIPT_PATH=%~dp0compose_down.ps1
powershell -ExecutionPolicy Bypass -File "%SCRIPT_PATH%"
pause
