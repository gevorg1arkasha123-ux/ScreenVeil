[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'ScreenVeil Auto Lock.lnk'
if (Test-Path -LiteralPath $shortcutPath) { Remove-Item -LiteralPath $shortcutPath -Force }

Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like '*ScreenVeil*watcher.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Write-Host 'Автоблокировка отключена.' -ForegroundColor Yellow
Read-Host 'Нажмите Enter для выхода'


