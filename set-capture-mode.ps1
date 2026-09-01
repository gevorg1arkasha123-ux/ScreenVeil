[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('remote', 'protected')]
    [string]$Mode
)

$ErrorActionPreference = 'Stop'
$configPath = Join-Path $PSScriptRoot 'config.json'
if (-not (Test-Path -LiteralPath $configPath)) { throw 'Сначала задайте пароль через setup-password.bat.' }

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$enabled = $Mode -eq 'protected'
if ($config.PSObject.Properties.Name -contains 'captureProtection') {
    $config.captureProtection = $enabled
} else {
    $config | Add-Member -NotePropertyName captureProtection -NotePropertyValue $enabled
}
$config | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8

if ($enabled) {
    Write-Host 'Anti-screenshot включён. AnyDesk может показывать чёрный экран.' -ForegroundColor Yellow
} else {
    Write-Host 'Remote Friendly включён. AnyDesk будет видеть окно ScreenVeil.' -ForegroundColor Green
}
Write-Host 'Изменение применяется при следующей блокировке.'
Read-Host 'Нажмите Enter для выхода'


