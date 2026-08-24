[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$compiler = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$automation = Get-ChildItem "$env:WINDIR\Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation" `
    -Recurse -Filter System.Management.Automation.dll | Select-Object -First 1 -ExpandProperty FullName

if (-not (Test-Path -LiteralPath $compiler)) { throw 'Не найден 64-битный компилятор .NET Framework.' }
if (-not $automation) { throw 'Не найдена System.Management.Automation.dll.' }

& $compiler /nologo /target:winexe /platform:x64 /optimize+ `
    "/win32manifest:$PSScriptRoot\launcher\ScreenVeil.manifest" `
    "/reference:$automation" /reference:System.Windows.Forms.dll /reference:System.Core.dll `
    "/out:$PSScriptRoot\ScreenVeil.exe" "$PSScriptRoot\launcher\ScreenVeilLauncher.cs"

if ($LASTEXITCODE -ne 0) { throw "Компиляция завершилась с кодом $LASTEXITCODE." }
Write-Host 'ScreenVeil.exe успешно собран.' -ForegroundColor Green


