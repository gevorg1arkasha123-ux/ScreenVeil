@echo off
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0set-capture-mode.ps1" -Mode protected
if errorlevel 1 pause

