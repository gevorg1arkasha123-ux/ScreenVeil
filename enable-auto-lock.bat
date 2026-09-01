@echo off
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0enable-auto-lock.ps1" -IdleMinutes 15
if errorlevel 1 pause

