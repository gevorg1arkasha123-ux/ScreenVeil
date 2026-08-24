[CmdletBinding()]
param(
    [ValidateRange(1, 1440)]
    [int]$IdleMinutes = 15
)

$ErrorActionPreference = 'Stop'
$startup = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startup 'ScreenVeil Auto Lock.lnk'
$watcherPath = Join-Path $PSScriptRoot 'watcher.ps1'

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = (Join-Path $PSHOME 'powershell.exe')
$shortcut.Arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -IdleMinutes {1}' -f $watcherPath, $IdleMinutes
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.IconLocation = (Join-Path $PSScriptRoot 'assets\screenveil.ico') + ',0'
$shortcut.Description = "ScreenVeil: блокировка после $IdleMinutes минут бездействия"
$shortcut.Save()

# Запускаем наблюдатель сразу; при следующих входах в Windows его запустит ярлык.
Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') `
    -ArgumentList @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"{0}"' -f $watcherPath), '-IdleMinutes', $IdleMinutes) `
    -WindowStyle Hidden

Write-Host "Автоблокировка включена: $IdleMinutes минут бездействия." -ForegroundColor Green
Read-Host 'Нажмите Enter для выхода'


