[CmdletBinding()]
param(
    [ValidateRange(5, 300)]
    [int]$Seconds = 30
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ScreenVeilWarningIdle {
    [StructLayout(LayoutKind.Sequential)]
    private struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")]
    private static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
    public static uint GetLastInputTick() {
        LASTINPUTINFO info = new LASTINPUTINFO();
        info.cbSize = (uint)Marshal.SizeOf(info);
        return GetLastInputInfo(ref info) ? info.dwTime : 0;
    }
}
'@

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        WindowStyle="None" ResizeMode="NoResize" ShowInTaskbar="False"
        ShowActivated="False" Focusable="False" Topmost="True"
        AllowsTransparency="True" Background="Transparent"
        Width="390" Height="142" UseLayoutRounding="True" SnapsToDevicePixels="True">
  <Border Margin="10" Padding="20,17" CornerRadius="18"
          Background="#F01A202B" BorderBrush="#35FFFFFF" BorderThickness="1">
    <Border.Effect><DropShadowEffect BlurRadius="24" ShadowDepth="4" Opacity="0.5"/></Border.Effect>
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="48"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <Border Width="40" Height="40" CornerRadius="20" Background="#273247"
              VerticalAlignment="Top" HorizontalAlignment="Left">
        <TextBlock Text="⌛" FontSize="20" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <StackPanel Grid.Column="1" Margin="12,0,0,0">
        <TextBlock Text="Автоматическая блокировка" Foreground="White"
                   FontFamily="Segoe UI Semibold" FontSize="16"/>
        <TextBlock Name="Countdown" Foreground="#B9C5D8" FontFamily="Segoe UI"
                   FontSize="14" Margin="0,7,0,0"/>
        <TextBlock Text="Двигайте мышью или нажмите любую клавишу, чтобы отменить"
                   Foreground="#78869B" FontFamily="Segoe UI" FontSize="11"
                   TextWrapping="Wrap" Margin="0,8,0,0"/>
      </StackPanel>
    </Grid>
  </Border>
</Window>
'@

$reader = [Xml.XmlNodeReader]::new([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$reader.Dispose()
$workArea = [Windows.SystemParameters]::WorkArea
$window.Left = $workArea.Right - $window.Width - 18
$window.Top = $workArea.Bottom - $window.Height - 18
$countdown = $window.FindName('Countdown')
$initialInput = [ScreenVeilWarningIdle]::GetLastInputTick()
$started = [Diagnostics.Stopwatch]::StartNew()
$script:warningResult = 'LOCK'

$timer = [Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(200)
$timer.Add_Tick({
    if ([ScreenVeilWarningIdle]::GetLastInputTick() -ne $initialInput) {
        $script:warningResult = 'CANCELLED'
        $timer.Stop()
        $window.Close()
        return
    }
    $remaining = [Math]::Max(0, [Math]::Ceiling($Seconds - $started.Elapsed.TotalSeconds))
    $countdown.Text = "Экран заблокируется через $remaining сек."
    if ($remaining -le 0) { $timer.Stop(); $window.Close() }
})
$countdown.Text = "Экран заблокируется через $Seconds сек."
$timer.Start()
[void]$window.ShowDialog()
$timer.Stop()
$started.Stop()
Write-Output $script:warningResult

