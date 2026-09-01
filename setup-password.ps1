[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$configPath = Join-Path $PSScriptRoot 'config.json'

function Read-Secret([string]$Prompt) {
    $secure = Read-Host $Prompt -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

$first = Read-Secret 'Введите новый пароль'
$second = Read-Secret 'Повторите пароль'

if ([string]::IsNullOrWhiteSpace($first)) { throw 'Пароль не может быть пустым.' }
if ($first -cne $second) { throw 'Пароли не совпадают.' }

$salt = [byte[]]::new(16)
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($salt) } finally { $rng.Dispose() }
$iterations = 210000
$derive = [Security.Cryptography.Rfc2898DeriveBytes]::new(
    $first, $salt, $iterations, [Security.Cryptography.HashAlgorithmName]::SHA256
)
try { $hash = $derive.GetBytes(32) } finally { $derive.Dispose() }

[ordered]@{
    version = 1
    iterations = $iterations
    salt = [Convert]::ToBase64String($salt)
    hash = [Convert]::ToBase64String($hash)
    captureProtection = $false
    title = 'КОМПЬЮТЕР ЗАБЛОКИРОВАН'
    subtitle = 'Введите пароль, чтобы продолжить'
} | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8

Write-Host "`nПароль сохранён. Теперь запустите start.bat" -ForegroundColor Green
Read-Host 'Нажмите Enter для выхода'


