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

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
internal class MMDeviceEnumerator { }

[ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
internal interface IMMDeviceEnumerator {
    [PreserveSig] int EnumAudioEndpoints(int dataFlow, uint stateMask, out IntPtr devices);
    [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
}

[ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("D666063F-1587-4E43-81F1-B948E807363F")]
internal interface IMMDevice {
    [PreserveSig] int Activate(ref Guid iid, uint context, IntPtr activationParams,
        [MarshalAs(UnmanagedType.IUnknown)] out object instance);
}

[ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064")]
internal interface IAudioMeterInformation {
    [PreserveSig] int GetPeakValue(out float peak);
}

public static class ScreenVeilAudio {
    public static bool IsAudioPlaying() {
        object enumeratorObject = null;
        IMMDevice device = null;
        object meterObject = null;
        try {
            enumeratorObject = new MMDeviceEnumerator();
            IMMDeviceEnumerator enumerator = (IMMDeviceEnumerator)enumeratorObject;
            if (enumerator.GetDefaultAudioEndpoint(0, 1, out device) != 0 || device == null) return false;
            Guid iid = new Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064");
            if (device.Activate(ref iid, 23, IntPtr.Zero, out meterObject) != 0 || meterObject == null) return false;
            float peak;
            if (((IAudioMeterInformation)meterObject).GetPeakValue(out peak) != 0) return false;
            return peak > 0.0005f;
        } catch {
            return false;
        } finally {
            if (meterObject != null && Marshal.IsComObject(meterObject)) Marshal.FinalReleaseComObject(meterObject);
            if (device != null && Marshal.IsComObject(device)) Marshal.FinalReleaseComObject(device);
            if (enumeratorObject != null && Marshal.IsComObject(enumeratorObject)) Marshal.FinalReleaseComObject(enumeratorObject);
        }
    }
}
'@

$createdNew = $false
$mutex = [Threading.Mutex]::new($true, 'Local\ScreenVeilIdleWatcher', [ref]$createdNew)
if (-not $createdNew) { exit 0 }

try {
    $threshold = [uint64]$IdleMinutes * 60 * 1000
    $warningDurationSeconds = 30
    $warningThreshold = $threshold - ([uint64]$warningDurationSeconds * 1000)
    $armed = $true
    $lastMediaUtc = [DateTime]::MinValue
    $mediaWasActive = $false
    Write-WatcherLog "Наблюдатель запущен; таймер: $IdleMinutes мин."

    while ($true) {
        $idle = [uint64][ScreenVeilIdle]::GetIdleMilliseconds()
        $audioNow = [ScreenVeilAudio]::IsAudioPlaying()
        if ($audioNow) {
            $lastMediaUtc = [DateTime]::UtcNow
        }

        $sinceMedia = if ($lastMediaUtc -eq [DateTime]::MinValue) {
            [uint64]::MaxValue
        } else {
            [uint64]([DateTime]::UtcNow - $lastMediaUtc).TotalMilliseconds
        }
        # Запас покрывает короткие тихие сцены, но после настоящей паузы быстро отпускает таймер.
        $mediaActive = $sinceMedia -lt 30000
        if ($mediaActive -and -not $mediaWasActive) {
            Write-WatcherLog 'Автоблокировка приостановлена: обнаружено воспроизведение звука.'
        } elseif (-not $mediaActive -and $mediaWasActive) {
            Write-WatcherLog 'Воспроизведение остановлено; отсчёт бездействия начат заново.'
        }
        $mediaWasActive = $mediaActive
        $effectiveIdle = [Math]::Min($idle, $sinceMedia)

        if (-not $armed) {
            # После закрытия заставки ждём реального ввода, чтобы не запустить её снова мгновенно.
            if ($idle -lt 5000) { $armed = $true }
        } elseif (-not $mediaActive -and $effectiveIdle -ge $warningThreshold -and (Test-Path -LiteralPath $configPath)) {
            try {
                if (Test-Path -LiteralPath $lockExecutable) {
                    Write-WatcherLog "Показано предупреждение за $warningDurationSeconds сек. до блокировки."
                    $warning = Start-Process -FilePath $lockExecutable `
                        -ArgumentList @('--warning', $warningDurationSeconds) -PassThru
                    $warning.WaitForExit()
                    if ($warning.ExitCode -eq 2) {
                        Write-WatcherLog 'Автоблокировка отменена активностью пользователя.'
                        continue
                    }
                } else {
                    Start-Sleep -Seconds $warningDurationSeconds
                }
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


