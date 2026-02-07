@echo off
title MASTER DEPLOY - WEBSITE
SET SCRIPT_PATH=%~dp0deploy_master.ps1
powershell -ExecutionPolicy Bypass -File "%SCRIPT_PATH%"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Deployment failed! Check the logs above.
) else (
    echo.
    echo [SUCCESS] Deployment completed successfully.
)
pause
