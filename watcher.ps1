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
    [StructLayout(LayoutKind.Sequential)]
    private struct RECT {
        public int Left, Top, Right, Bottom;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct MONITORINFO {
        public uint cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }

    [DllImport("user32.dll")]
    private static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);
    [DllImport("user32.dll")] private static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);
    [DllImport("powrprof.dll")]
    private static extern uint CallNtPowerInformation(
        int informationLevel, IntPtr input, uint inputLength, out uint output, uint outputLength);

    public static uint GetIdleMilliseconds() {
        LASTINPUTINFO info = new LASTINPUTINFO();
        info.cbSize = (uint)Marshal.SizeOf(info);
        if (!GetLastInputInfo(ref info)) return 0;
        return unchecked((uint)Environment.TickCount - info.dwTime);
    }

    public static bool IsForegroundFullscreen() {
        IntPtr hwnd = GetForegroundWindow();
        if (hwnd == IntPtr.Zero) return false;
        RECT window;
        if (!GetWindowRect(hwnd, out window)) return false;
        IntPtr monitor = MonitorFromWindow(hwnd, 2); // MONITOR_DEFAULTTONEAREST
        MONITORINFO info = new MONITORINFO();
        info.cbSize = (uint)Marshal.SizeOf(info);
        if (!GetMonitorInfo(monitor, ref info)) return false;
        int windowWidth = window.Right - window.Left;
        int windowHeight = window.Bottom - window.Top;
        int monitorWidth = info.rcMonitor.Right - info.rcMonitor.Left;
        int monitorHeight = info.rcMonitor.Bottom - info.rcMonitor.Top;
        return windowWidth >= monitorWidth * 0.99 && windowHeight >= monitorHeight * 0.99;
    }

    public static bool IsDisplayRequired() {
        uint state;
        uint status = CallNtPowerInformation(16, IntPtr.Zero, 0, out state, 4); // SystemExecutionState
        return status == 0 && (state & 0x00000002) != 0; // ES_DISPLAY_REQUIRED
    }
}
'@

$createdNew = $false
$mutex = [Threading.Mutex]::new($true, 'Local\ScreenVeilIdleWatcher', [ref]$createdNew)
if (-not $createdNew) { exit 0 }

try {
    $threshold = [uint64]$IdleMinutes * 60 * 1000
    $armed = $true
    $lastMediaUtc = [DateTime]::MinValue
    $mediaWasActive = $false
    Write-WatcherLog "Наблюдатель запущен; таймер: $IdleMinutes мин."

    while ($true) {
        $idle = [uint64][ScreenVeilIdle]::GetIdleMilliseconds()
        $mediaActive = [ScreenVeilIdle]::IsForegroundFullscreen() -or [ScreenVeilIdle]::IsDisplayRequired()
        if ($mediaActive) {
            $lastMediaUtc = [DateTime]::UtcNow
            if (-not $mediaWasActive) { Write-WatcherLog 'Автоблокировка приостановлена: полноэкранное окно или активное видео.' }
        } elseif ($mediaWasActive) {
            Write-WatcherLog 'Видео завершено; отсчёт бездействия начат заново.'
        }
        $mediaWasActive = $mediaActive

        $sinceMedia = if ($lastMediaUtc -eq [DateTime]::MinValue) {
            [uint64]::MaxValue
        } else {
            [uint64]([DateTime]::UtcNow - $lastMediaUtc).TotalMilliseconds
        }
        $effectiveIdle = [Math]::Min($idle, $sinceMedia)

        if (-not $armed) {
            # После закрытия заставки ждём реального ввода, чтобы не запустить её снова мгновенно.
            if ($idle -lt 5000) { $armed = $true }
        } elseif (-not $mediaActive -and $effectiveIdle -ge $threshold -and (Test-Path -LiteralPath $configPath)) {
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


