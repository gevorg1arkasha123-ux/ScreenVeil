[CmdletBinding()]
param(
    [switch]$DiagnosticsOnly
)

$ErrorActionPreference = 'Stop'
$configPath = Join-Path $PSScriptRoot 'config.json'
if (-not (Test-Path -LiteralPath $configPath)) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show('Сначала запустите setup-password.bat и задайте пароль.', 'ScreenVeil') | Out-Null
    exit 1
}

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$captureProtectionEnabled = $config.PSObject.Properties.Name -contains 'captureProtection' -and [bool]$config.captureProtection

# Не допускаем двух наложенных друг на друга окон блокировки.
$lockMutexCreated = $false
$lockMutex = [Threading.Mutex]::new($true, 'Local\ScreenVeilLockWindow', [ref]$lockMutexCreated)
if (-not $lockMutexCreated) { exit 0 }

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ScreenVeilNative {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] private static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] public static extern bool SetWindowDisplayAffinity(IntPtr hwnd, uint affinity);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(
        IntPtr hwnd, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, IntPtr processId);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint attach, uint attachTo, bool value);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool BringWindowToTop(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern IntPtr SetFocus(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hwnd, int command);
    public static void EnableBestDpiAwareness() {
        try {
            // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
            if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return;
        } catch (EntryPointNotFoundException) { }
        SetProcessDPIAware();
    }

    public static bool ForceForeground(IntPtr hwnd) {
        IntPtr foreground = GetForegroundWindow();
        uint currentThread = GetCurrentThreadId();
        uint foregroundThread = foreground == IntPtr.Zero
            ? 0 : GetWindowThreadProcessId(foreground, IntPtr.Zero);
        bool attached = foregroundThread != 0 && foregroundThread != currentThread
            && AttachThreadInput(currentThread, foregroundThread, true);
        try {
            ShowWindow(hwnd, 5); // SW_SHOW
            BringWindowToTop(hwnd);
            bool result = SetForegroundWindow(hwnd);
            SetFocus(hwnd);
            return result;
        } finally {
            if (attached) AttachThreadInput(currentThread, foregroundThread, false);
        }
    }
}
'@

# PowerShell 5.1 по умолчанию виртуализирует координаты при масштабе 125/150%.
# DPI-aware режим и SetWindowPos ниже используют реальные пиксели каждого монитора.
[ScreenVeilNative]::EnableBestDpiAwareness()
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing, System.Windows.Forms

foreach ($property in @('iterations', 'salt', 'hash', 'title', 'subtitle')) {
    if ($null -eq $config.$property) {
        [System.Windows.MessageBox]::Show('Файл config.json повреждён. Задайте пароль заново.', 'ScreenVeil') | Out-Null
        exit 1
    }
}

function Test-Password([string]$Password) {
    $salt = [Convert]::FromBase64String([string]$config.salt)
    $expected = [Convert]::FromBase64String([string]$config.hash)
    $derive = [Security.Cryptography.Rfc2898DeriveBytes]::new(
        $Password, $salt, [int]$config.iterations, [Security.Cryptography.HashAlgorithmName]::SHA256
    )
    try { $actual = $derive.GetBytes($expected.Length) } finally { $derive.Dispose() }
    if ($actual.Length -ne $expected.Length) { return $false }
    $difference = 0
    for ($index = 0; $index -lt $actual.Length; $index++) {
        $difference = $difference -bor ($actual[$index] -bxor $expected[$index])
    }
    $difference -eq 0
}

function Get-ScreenSnapshot([System.Drawing.Rectangle]$Bounds) {
    $bitmap = [System.Drawing.Bitmap]::new($Bounds.Width, $Bounds.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $stream = $null
    try {
        $graphics.CopyFromScreen($Bounds.Left, $Bounds.Top, 0, 0, $bitmap.Size)
        $stream = [IO.MemoryStream]::new()
        $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        $stream.Position = 0
        $image = [Windows.Media.Imaging.BitmapImage]::new()
        $image.BeginInit()
        $image.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $image.StreamSource = $stream
        $image.EndInit()
        $image.Freeze()
        return $image
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
        if ($stream) { $stream.Dispose() }
    }
}

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" ResizeMode="NoResize" ShowInTaskbar="False"
        Topmost="True" Background="#10141C" AllowsTransparency="False"
        UseLayoutRounding="True" SnapsToDevicePixels="True"
        TextOptions.TextFormattingMode="Display" TextOptions.TextRenderingMode="ClearType">
  <Grid>
    <Image Name="Backdrop" Stretch="Fill" SnapsToDevicePixels="True"
           RenderOptions.BitmapScalingMode="HighQuality">
      <Image.Effect><BlurEffect Radius="18" KernelType="Gaussian"/></Image.Effect>
    </Image>
    <Border Background="#99070A10"/>
    <Border Name="LockPanel" Width="470" Padding="42,38" CornerRadius="24"
            Background="#E61A1F2A" BorderBrush="#35FFFFFF" BorderThickness="1"
            HorizontalAlignment="Center" VerticalAlignment="Center">
      <Border.Effect><DropShadowEffect BlurRadius="45" ShadowDepth="0" Opacity="0.65"/></Border.Effect>
      <StackPanel>
        <Border Width="66" Height="66" CornerRadius="33" Background="#252D3A"
                HorizontalAlignment="Center" Margin="0,0,0,22">
          <Viewbox Width="30" Height="30" HorizontalAlignment="Center" VerticalAlignment="Center">
            <Canvas Width="24" Height="24">
              <Path Stroke="#EAF2FF" StrokeThickness="2.2" StrokeStartLineCap="Round"
                    StrokeEndLineCap="Round" Data="M7,10 L7,7 C7,3.7 9,2 12,2 C15,2 17,3.7 17,7 L17,10"/>
              <Path Fill="#4D6BFE" Stroke="#BFD0FF" StrokeThickness="1.2"
                    Data="M5,9 L19,9 C20.1,9 21,9.9 21,11 L21,21 C21,22.1 20.1,23 19,23 L5,23 C3.9,23 3,22.1 3,21 L3,11 C3,9.9 3.9,9 5,9 Z"/>
              <Ellipse Fill="White" Width="3" Height="3" Canvas.Left="10.5" Canvas.Top="14"/>
              <Rectangle Fill="White" Width="2" Height="4" Canvas.Left="11" Canvas.Top="16"/>
            </Canvas>
          </Viewbox>
        </Border>
        <TextBlock Name="Title" Foreground="White" FontFamily="Segoe UI Semibold" FontSize="23"
                   TextAlignment="Center"/>
        <TextBlock Name="Subtitle" Foreground="#AEB8C8" FontFamily="Segoe UI" FontSize="14"
                   TextAlignment="Center" Margin="0,8,0,26"/>
        <PasswordBox Name="Password" Height="50" FontSize="20" Padding="15,9" Focusable="True"
                     Foreground="White" Background="#202735" BorderBrush="#46536A"
                     BorderThickness="1" CaretBrush="White"/>
        <TextBlock Name="Error" Text="Неверный пароль" Foreground="#FF7185" FontSize="13"
                   TextAlignment="Center" Margin="0,10,0,0" Visibility="Collapsed"/>
        <Button Name="Unlock" Content="РАЗБЛОКИРОВАТЬ" Height="48" Margin="0,18,0,0"
                Foreground="White" Background="#4D6BFE" BorderThickness="0"
                FontFamily="Segoe UI Semibold" FontSize="13" Cursor="Hand"/>
        <TextBlock Text="Работа программ продолжается в фоне" Foreground="#778296"
                   TextAlignment="Center" FontSize="12" Margin="0,20,0,0"/>
      </StackPanel>
    </Border>
  </Grid>
</Window>
'@

$screens = [System.Windows.Forms.Screen]::AllScreens
$windows = [Collections.Generic.List[Windows.Window]]::new()
$primaryWindow = $null

foreach ($screen in $screens) {
    $reader = [Xml.XmlNodeReader]::new([xml]$xaml)
    $currentWindow = [Windows.Markup.XamlReader]::Load($reader)
    $reader.Dispose()
    $currentWindow.FindName('Backdrop').Source = Get-ScreenSnapshot $screen.Bounds
    $currentWindow.FindName('Title').Text = [string]$config.title
    $currentWindow.FindName('Subtitle').Text = [string]$config.subtitle

    if ($screen.Primary) {
        $primaryWindow = $currentWindow
    } else {
        $currentWindow.FindName('LockPanel').Visibility = 'Collapsed'
    }

    $targetBounds = $screen.Bounds
    $currentWindow.Add_SourceInitialized({
        param($sender, $event)
        $handle = [Windows.Interop.WindowInteropHelper]::new($sender).Handle
        # WDA_MONITOR несовместим с AnyDesk: включается только в явном anti-screenshot режиме.
        $affinity = if ($captureProtectionEnabled) { 0x00000001 } else { 0x00000000 }
        [ScreenVeilNative]::SetWindowDisplayAffinity($handle, $affinity) | Out-Null
        [ScreenVeilNative]::SetWindowPos(
            $handle, [IntPtr](-1), $targetBounds.Left, $targetBounds.Top,
            $targetBounds.Width, $targetBounds.Height, 0x0040
        ) | Out-Null
    }.GetNewClosure())
    $windows.Add($currentWindow)
}

if (-not $primaryWindow) { throw 'Не удалось определить основной монитор.' }

$passwordBox = $primaryWindow.FindName('Password')
$errorText = $primaryWindow.FindName('Error')
$unlockButton = $primaryWindow.FindName('Unlock')
$script:unlocked = $false
$focusTimer = [Windows.Threading.DispatcherTimer]::new()
$focusTimer.Interval = [TimeSpan]::FromMilliseconds(150)
$script:focusAttempts = 0

$forcePasswordFocus = {
    $handle = [Windows.Interop.WindowInteropHelper]::new($primaryWindow).Handle
    [ScreenVeilNative]::ForceForeground($handle) | Out-Null
    $primaryWindow.Activate() | Out-Null
    [Windows.Input.FocusManager]::SetFocusedElement($primaryWindow, $passwordBox)
    [Windows.Input.Keyboard]::Focus($passwordBox) | Out-Null
    $passwordBox.Focus() | Out-Null
}

$focusTimer.Add_Tick({
    $script:focusAttempts++
    & $forcePasswordFocus
    if ($passwordBox.IsKeyboardFocusWithin -or $script:focusAttempts -ge 20) {
        $focusTimer.Stop()
    }
})

$unlock = {
    if (Test-Password $passwordBox.Password) {
        $script:unlocked = $true
        foreach ($item in $windows) { $item.Close() }
    } else {
        $errorText.Visibility = 'Visible'
        $passwordBox.Clear()
        $passwordBox.Focus() | Out-Null
    }
}

$unlockButton.Add_Click($unlock)
$passwordBox.Add_KeyDown({
    param($sender, $event)
    if ($event.Key -eq [Windows.Input.Key]::Enter) { & $unlock; $event.Handled = $true }
    elseif ($event.Key -eq [Windows.Input.Key]::Escape) { $event.Handled = $true }
})
$passwordBox.Add_PasswordChanged({ $errorText.Visibility = 'Collapsed' })
foreach ($item in $windows) {
    $item.Add_Closing({ param($sender, $event) if (-not $script:unlocked) { $event.Cancel = $true } })
    $item.Add_PreviewKeyDown({
        param($sender, $event)
        $modifiers = [Windows.Input.Keyboard]::Modifiers
        $blocked =
            ($event.Key -in @('LWin', 'RWin')) -or
            ($event.Key -eq 'F4' -and $modifiers.HasFlag([Windows.Input.ModifierKeys]::Alt)) -or
            ($event.Key -eq 'Tab' -and $modifiers.HasFlag([Windows.Input.ModifierKeys]::Alt)) -or
            ($event.Key -eq 'Escape' -and $modifiers.HasFlag([Windows.Input.ModifierKeys]::Control)) -or
            ($event.Key -eq 'D' -and $modifiers.HasFlag([Windows.Input.ModifierKeys]::Windows))
        if ($blocked) {
            $event.Handled = $true
        }
    })
}
$primaryWindow.Add_Activated({
    [Windows.Input.Keyboard]::Focus($passwordBox) | Out-Null
    $passwordBox.Focus() | Out-Null
})
$primaryWindow.Add_Deactivated({ & $forcePasswordFocus })
$primaryWindow.Add_ContentRendered({
    & $forcePasswordFocus
    $script:focusAttempts = 0
    $focusTimer.Start()
})

if ($DiagnosticsOnly) {
    $lockMutex.ReleaseMutex()
    $lockMutex.Dispose()
    exit 0
}

foreach ($item in $windows) { if ($item -ne $primaryWindow) { $item.Show() } }
try {
    [void]$primaryWindow.ShowDialog()
} finally {
    $focusTimer.Stop()
    $lockMutex.ReleaseMutex()
    $lockMutex.Dispose()
}

