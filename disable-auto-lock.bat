@echo off
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0disable-auto-lock.ps1"
if errorlevel 1 pause

