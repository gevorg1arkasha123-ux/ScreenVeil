[CmdletBinding()]
param(
    [ValidateRange(1, 1440)]
    [int]$IdleMinutes = 15
)

$ErrorActionPreference = 'Stop'
$lockScript = Join-Path $PSScriptRoot 'lock.ps1'
$lockExecutable = Join-Path $PSScriptRoot 'ScreenVeil.exe'
$configPath = Join-Path $PSScriptRoot 'config.json'
$logDirectory = Join-Path $env:LOCALAPPDATA 'ScreenVeil'
$logPath = Join-Path $logDirectory 'watcher.log'

function Write-WatcherLog([string]$Message) {
    if (-not (Test-Path -LiteralPath $logDirectory)) {
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    }
    $line = '{0:u} {1}' -f [DateTime]::Now, $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ScreenVeilIdle {
    [StructLayout(LayoutKind.Sequential)]
    private struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    [DllImport("user32.dll")]
    private static extern bool GetLastInputInfo(ref LASTINPUTINFO info);

    public static uint GetIdleMilliseconds() {
        LASTINPUTINFO info = new LASTINPUTINFO();
        info.cbSize = (uint)Marshal.SizeOf(info);
        if (!GetLastInputInfo(ref info)) return 0;
        return unchecked((uint)Environment.TickCount - info.dwTime);
    }
}
'@

$createdNew = $false
$mutex = [Threading.Mutex]::new($true, 'Local\ScreenVeilIdleWatcher', [ref]$createdNew)
if (-not $createdNew) { exit 0 }

try {
    $threshold = [uint64]$IdleMinutes * 60 * 1000
    $armed = $true
    Write-WatcherLog "Наблюдатель запущен; таймер: $IdleMinutes мин."

    while ($true) {
        $idle = [uint64][ScreenVeilIdle]::GetIdleMilliseconds()

        if (-not $armed) {
            # После закрытия заставки ждём реального ввода, чтобы не запустить её снова мгновенно.
            if ($idle -lt 5000) { $armed = $true }
        } elseif ($idle -ge $threshold -and (Test-Path -LiteralPath $configPath)) {
            try {
                if (Test-Path -LiteralPath $lockExecutable) {
                    $process = Start-Process -FilePath $lockExecutable -WindowStyle Hidden -PassThru
                } else {
                    $arguments = @(
                        '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA',
                        '-WindowStyle', 'Hidden', '-File', ('"{0}"' -f $lockScript)
                    )
                    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden -PassThru
                }
                $armed = $false
                Write-WatcherLog 'Запущена автоматическая блокировка.'
                $process.WaitForExit()
                if ($process.ExitCode -ne 0) { Write-WatcherLog "Блокировка завершилась с кодом $($process.ExitCode)." }
            } catch {
                Write-WatcherLog "Ошибка запуска блокировки: $($_.Exception.Message)"
                $armed = $false
            }
        }

        Start-Sleep -Seconds 2
    }
} finally {
    Write-WatcherLog 'Наблюдатель остановлен.'
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}


