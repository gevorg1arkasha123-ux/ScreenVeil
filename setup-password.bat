@echo off
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-password.ps1"
if errorlevel 1 (
  echo.
  echo Setup failed. The error is shown above.
  pause
)
