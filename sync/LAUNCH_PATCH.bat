@echo off
pushd "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "selective_patch.ps1"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] The script encountered a fatal error.
    pause
)
popd
