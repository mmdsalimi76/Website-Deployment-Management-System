@echo off
pushd "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "sync_orchestrator.ps1"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] The orchestrator encountered a fatal error.
    pause
)
popd
