[CmdletBinding()]
param(
    [ValidateRange(1, 1440)]
    [int]$IdleMinutes = 15
)

$ErrorActionPreference = 'Stop'
$lockScript = Join-Path $PSScriptRoot 'lock.ps1'
$configPath = Join-Path $PSScriptRoot 'config.json'

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

    while ($true) {
        $idle = [uint64][ScreenVeilIdle]::GetIdleMilliseconds()

        if (-not $armed) {
            # После закрытия заставки ждём реального ввода, чтобы не запустить её снова мгновенно.
            if ($idle -lt 5000) { $armed = $true }
        } elseif ($idle -ge $threshold -and (Test-Path -LiteralPath $configPath)) {
            $arguments = @(
                '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA',
                '-WindowStyle', 'Hidden', '-File', ('"{0}"' -f $lockScript)
            )
            $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden -PassThru
            $armed = $false
            $process.WaitForExit()
        }

        Start-Sleep -Seconds 2
    }
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}


