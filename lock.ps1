[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$configPath = Join-Path $PSScriptRoot 'config.json'
if (-not (Test-Path -LiteralPath $configPath)) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show('Сначала запустите setup-password.bat и задайте пароль.', 'ScreenVeil') | Out-Null
    exit 1
}

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing, System.Windows.Forms

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

# Снимок всего виртуального рабочего стола. Он остаётся неподвижным под размытием,
# поэтому содержимое окон и уведомлений после запуска не просвечивает.
$bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bitmap = [System.Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
try {
    $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bitmap.Size)
    $stream = [IO.MemoryStream]::new()
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $stream.Position = 0
    $source = [Windows.Media.Imaging.BitmapImage]::new()
    $source.BeginInit()
    $source.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $source.StreamSource = $stream
    $source.EndInit()
    $source.Freeze()
} finally {
    $graphics.Dispose()
    $bitmap.Dispose()
    if ($stream) { $stream.Dispose() }
}

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" ResizeMode="NoResize" ShowInTaskbar="False"
        Topmost="True" Background="#10141C" AllowsTransparency="False">
  <Grid>
    <Image Name="Backdrop" Stretch="Fill">
      <Image.Effect><BlurEffect Radius="18" KernelType="Gaussian"/></Image.Effect>
    </Image>
    <Border Background="#99070A10"/>
    <Border Width="470" Padding="42,38" CornerRadius="24"
            Background="#E61A1F2A" BorderBrush="#35FFFFFF" BorderThickness="1"
            HorizontalAlignment="Center" VerticalAlignment="Center">
      <Border.Effect><DropShadowEffect BlurRadius="45" ShadowDepth="0" Opacity="0.65"/></Border.Effect>
      <StackPanel>
        <Border Width="66" Height="66" CornerRadius="33" Background="#252D3A"
                HorizontalAlignment="Center" Margin="0,0,0,22">
          <TextBlock Text="🔒" FontSize="28" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <TextBlock Name="Title" Foreground="White" FontFamily="Segoe UI Semibold" FontSize="23"
                   TextAlignment="Center"/>
        <TextBlock Name="Subtitle" Foreground="#AEB8C8" FontFamily="Segoe UI" FontSize="14"
                   TextAlignment="Center" Margin="0,8,0,26"/>
        <PasswordBox Name="Password" Height="50" FontSize="20" Padding="15,9"
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

$reader = [Xml.XmlNodeReader]::new([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$reader.Dispose()

$window.Left = $bounds.Left
$window.Top = $bounds.Top
$window.Width = $bounds.Width
$window.Height = $bounds.Height
$window.FindName('Backdrop').Source = $source
$window.FindName('Title').Text = [string]$config.title
$window.FindName('Subtitle').Text = [string]$config.subtitle
$passwordBox = $window.FindName('Password')
$errorText = $window.FindName('Error')
$unlockButton = $window.FindName('Unlock')
$script:unlocked = $false

$unlock = {
    if (Test-Password $passwordBox.Password) {
        $script:unlocked = $true
        $window.Close()
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
$window.Add_Closing({ param($sender, $event) if (-not $script:unlocked) { $event.Cancel = $true } })
$window.Add_PreviewKeyDown({
    param($sender, $event)
    if (($event.Key -eq 'F4' -and [Windows.Input.Keyboard]::Modifiers.HasFlag([Windows.Input.ModifierKeys]::Alt)) -or
        ($event.Key -eq 'Tab' -and [Windows.Input.Keyboard]::Modifiers.HasFlag([Windows.Input.ModifierKeys]::Alt))) {
        $event.Handled = $true
    }
})
$window.Add_Deactivated({ $window.Activate() | Out-Null; $passwordBox.Focus() | Out-Null })
$window.Add_ContentRendered({ $window.Activate() | Out-Null; $passwordBox.Focus() | Out-Null })

[void]$window.ShowDialog()

