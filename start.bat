@echo off
cd /d "%~dp0"
if exist "%~dp0ScreenVeil.exe" (
  "%~dp0ScreenVeil.exe"
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0lock.ps1"
)
if errorlevel 1 (
  powershell.exe -NoLogo -NoProfile -Command "Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show('ScreenVeil could not start. Run setup-password.bat again.', 'ScreenVeil error')"
)
