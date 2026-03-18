Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Management

# --- Hardware Fingerprint (must match C# HardwareFingerprint.Generate exactly) ---
function Get-WmiValue($class, $prop) {
    try {
        $obj = Get-CimInstance -ClassName $class -ErrorAction Stop | Select-Object -First 1
        $raw = $obj.$prop
        if ($null -eq $raw) { return "UNKNOWN" }
        $val = "$raw".Trim()
        if ($val -and $val -ne "To Be Filled By O.E.M." -and $val -ne "Default string" -and $val -ne "None") { return $val }
    } catch {}
    return "UNKNOWN"
}

function Get-HardwareFingerprint {
    $cpuId = Get-WmiValue "Win32_Processor" "ProcessorId"
    $boardSerial = Get-WmiValue "Win32_BaseBoard" "SerialNumber"
    $biosSerial = Get-WmiValue "Win32_BIOS" "SerialNumber"
    $raw = "CPU:${cpuId}|MB:${boardSerial}|BIOS:${biosSerial}"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($raw))
    $sha.Dispose()
    return ([BitConverter]::ToString($hash) -replace '-','')
}

# --- PC Specs ---
function Get-CpuInfo { return Get-WmiValue "Win32_Processor" "Name" }

function Get-GpuInfo {
    try {
        $gpu = Get-CimInstance Win32_VideoController -ErrorAction Stop | Select-Object -First 1
        $name = "$($gpu.Name)".Trim()
        if (-not $name) { return "UNKNOWN" }
        $vram = 0
        try {
            $pnpId = $gpu.PNPDeviceID
            if ($pnpId) {
                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$pnpId"
                $driver = (Get-ItemProperty -Path $regPath -ErrorAction Stop).Driver
                if ($driver) {
                    $videoPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$driver"
                    $qwMem = (Get-ItemProperty -Path $videoPath -ErrorAction Stop).'HardwareInformation.qwMemorySize'
                    if ($qwMem -is [long]) { $vram = [uint64]$qwMem }
                    elseif ($qwMem -is [byte[]] -and $qwMem.Length -ge 8) { $vram = [BitConverter]::ToUInt64($qwMem, 0) }
                }
            }
        } catch {}
        if ($vram -gt 0) { return "$name ($([math]::Floor($vram / 1073741824)) GB)" }
        return $name
    } catch {}
    return "UNKNOWN"
}

function Get-RamInfo {
    try {
        $totalBytes = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory
        $totalGB = [math]::Round($totalBytes / 1073741824)
        $sticks = Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop
        $first = $sticks | Select-Object -First 1
        $mfr = "$($first.Manufacturer)".Trim()
        $part = "$($first.PartNumber)".Trim()
        $speed = ($sticks | ForEach-Object { $_.Speed } | Measure-Object -Maximum).Maximum
        $configSpeed = ($sticks | ForEach-Object { $_.ConfiguredClockSpeed } | Measure-Object -Maximum).Maximum
        $actualSpeed = if ($configSpeed -gt 0) { $configSpeed } else { $speed }
        $stickCount = @($sticks).Count
        $slots = @($sticks | ForEach-Object { "$($_.DeviceLocator)".Trim() } | Where-Object { $_ })
        $sb = "${totalGB} GB"
        if ($actualSpeed -gt 0) { $sb += " @ ${actualSpeed} MHz" }
        $sb += " (${stickCount}x"
        if ($stickCount -gt 0) { $sb += " $([math]::Round(($totalBytes / $stickCount) / 1073741824)) GB" }
        $sb += ")"
        $extra = @()
        if ($mfr -and $mfr -ne "Unknown") { $extra += $mfr }
        if ($part -and $part -ne "Unknown") { $extra += $part }
        if ($extra.Count -gt 0) { $sb += " - $($extra -join ' ')" }
        if ($slots.Count -gt 0) { $sb += "`nSlots: $($slots -join ', ')" }
        return $sb
    } catch {}
    return "UNKNOWN"
}

function Get-MotherboardInfo {
    try {
        $mb = Get-CimInstance Win32_BaseBoard -ErrorAction Stop | Select-Object -First 1
        $mfr = "$($mb.Manufacturer)".Trim()
        $prod = "$($mb.Product)".Trim()
        $bad = @("To Be Filled By O.E.M.", "Default string", "")
        $hasMfr = $mfr -notin $bad
        $hasProd = $prod -notin $bad
        if ($hasMfr -and $hasProd) { return "$mfr $prod" }
        if ($hasProd) { return $prod }
        if ($hasMfr) { return $mfr }
    } catch {}
    return "UNKNOWN"
}

function Get-BiosInfo {
    try {
        $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop | Select-Object -First 1
        $name = "$($bios.Name)".Trim()
        $ver = "$($bios.SMBIOSBIOSVersion)".Trim()
        $date = $bios.ReleaseDate
        $parts = @()
        if ($ver) { $parts += $ver }
        elseif ($name) { $parts += $name }
        if ($date) { $parts += $date.ToString("yyyy-MM-dd") }
        if ($parts.Count -gt 0) { return $parts -join " " }
    } catch {}
    return "UNKNOWN"
}

function Get-WindowsInfo {
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop | Select-Object -First 1
        $caption = "$($os.Caption)".Trim()
        $build = "$($os.BuildNumber)".Trim()
        if ($caption -and $build) { return "$caption (Build $build)" }
        if ($caption) { return $caption }
    } catch {}
    return "UNKNOWN"
}

# --- Localization ---
$isFrench = (Get-Culture).TwoLetterISOLanguageName -eq "fr"
if ($isFrench) {
    $str = @{
        Title         = "GEPC Installation"
        Fingerprint   = "EMPREINTE MATERIELLE"
        Specs         = "SPECIFICATIONS DU PC"
        CopyAll       = "TOUT COPIER"
        Copied        = "COPIE !"
        Collecting    = "Collecte..."
        Motherboard   = "Carte mere"
        Discord       = "Rejoindre Discord"
        DiscordDm     = "Envoyer les infos a MapleSyrupJunkie"
        AnyDesk       = "Telecharger AnyDesk"
        AnyDeskUrl    = "https://anydesk.com/fr/downloads"
        Step1         = "1. Rejoignez le discord, copiez ces infos et envoyez-les a MapleSyrupJunkie"
        Step2         = "2. Telecharger et installer AnyDesk (requis pour l'assistance a distance)"
        Step3         = "3. Assurez-vous que Windows est a jour (Installer via Windows Update)"
        Step4         = "4. Ayez une cle USB a disposition, pas besoin de beaucoup d'espace (possiblement requis pour les mises a jour/reglages du BIOS)"
        Step5         = "5. Discord fonctionnel sur votre telephone (la video sera requise pour le reglage du BIOS)"
        Close         = "Fermer"
    }
} else {
    $str = @{
        Title         = "GEPC Setup"
        Fingerprint   = "HARDWARE FINGERPRINT"
        Specs         = "PC SPECIFICATIONS"
        CopyAll       = "COPY ALL"
        Copied        = "COPIED!"
        Collecting    = "Collecting..."
        Motherboard   = "Motherboard"
        Discord       = "Join Discord"
        DiscordDm     = "Send info to MapleSyrupJunkie"
        AnyDesk       = "Download AnyDesk"
        AnyDeskUrl    = "https://anydesk.com/en/downloads"
        Step1         = "1. Make sure to join the discord and copy this info and send it to me (MapleSyrupJunkie)"
        Step2         = "2. Download and install AnyDesk (required for remote assistance)"
        Step3         = "3. Make sure windows is up to date (Install from Windows Updates)"
        Step4         = "4. Have a USB thumb drive at your disposal, does not need a lot of space (might be required for bios updates/settings)"
        Step5         = "5. Discord ready and functional on your mobile phone (video will be required for BIOS tuning)"
        Close         = "Close"
    }
}

# --- WPF Window ---
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="GEPC Setup" Width="520" SizeToContent="Height"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent">
    <Border Background="#1a1a1a" CornerRadius="12" BorderBrush="#333" BorderThickness="1" Margin="8">
        <Border.Effect>
            <DropShadowEffect BlurRadius="12" ShadowDepth="2" Opacity="0.5"/>
        </Border.Effect>
        <Grid Margin="24,16,24,20">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="16"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="16"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="16"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="12"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="10"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="10"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="12"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="12"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="12"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <StackPanel Grid.Row="0" HorizontalAlignment="Center">
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Height="2" Margin="0,0,0,6">
                    <Border Background="#e74c3c" Width="55"/>
                    <Border Background="#f1c40f" Width="55"/>
                    <Border Background="#3498db" Width="55"/>
                    <Border Background="#ecf0f1" Width="55"/>
                </StackPanel>
                <TextBlock Text="GEPCPERFORMANCE" FontSize="20" FontWeight="Bold"
                           Foreground="#e0e0e0" HorizontalAlignment="Center" FontFamily="Segoe UI"/>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Height="2" Margin="0,6,0,4">
                    <Border Background="#e74c3c" Width="55"/>
                    <Border Background="#f1c40f" Width="55"/>
                    <Border Background="#3498db" Width="55"/>
                    <Border Background="#ecf0f1" Width="55"/>
                </StackPanel>
                <TextBlock Text="SETUP" FontSize="11" FontWeight="SemiBold" Foreground="#666"
                           HorizontalAlignment="Center" Margin="0,2,0,0"/>
            </StackPanel>

            <StackPanel Grid.Row="2">
                <TextBlock Name="lblFingerprint" Text="HARDWARE FINGERPRINT" FontSize="10" FontWeight="SemiBold"
                           Foreground="#888" Margin="0,0,0,6"/>
                <TextBox Name="txtFingerprint" IsReadOnly="True"
                         FontFamily="Consolas" FontSize="12"
                         Background="#111" Foreground="#e0e0e0"
                         BorderBrush="#333" BorderThickness="1"
                         Padding="8,6" TextWrapping="Wrap" Text="Collecting..."/>
            </StackPanel>

            <StackPanel Grid.Row="4">
                <TextBlock Name="lblSpecs" Text="PC SPECIFICATIONS" FontSize="10" FontWeight="SemiBold"
                           Foreground="#888" Margin="0,0,0,6"/>
                <Border Background="#111" BorderBrush="#333" BorderThickness="1"
                        CornerRadius="4" Padding="10,8">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="110"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <TextBlock Grid.Row="0" Grid.Column="0" Text="CPU" Foreground="#888" FontSize="11" Margin="0,2"/>
                        <TextBlock Grid.Row="0" Grid.Column="1" Name="txtCpu" Foreground="#e0e0e0" FontSize="11" Margin="0,2" TextWrapping="Wrap" Text="..."/>
                        <TextBlock Grid.Row="1" Grid.Column="0" Text="GPU" Foreground="#888" FontSize="11" Margin="0,2"/>
                        <TextBlock Grid.Row="1" Grid.Column="1" Name="txtGpu" Foreground="#e0e0e0" FontSize="11" Margin="0,2" TextWrapping="Wrap" Text="..."/>
                        <TextBlock Grid.Row="2" Grid.Column="0" Text="RAM" Foreground="#888" FontSize="11" Margin="0,2"/>
                        <TextBlock Grid.Row="2" Grid.Column="1" Name="txtRam" Foreground="#e0e0e0" FontSize="11" Margin="0,2" TextWrapping="Wrap" Text="..."/>
                        <TextBlock Grid.Row="3" Grid.Column="0" Name="lblMotherboard" Text="Motherboard" Foreground="#888" FontSize="11" Margin="0,2"/>
                        <TextBlock Grid.Row="3" Grid.Column="1" Name="txtMotherboard" Foreground="#e0e0e0" FontSize="11" Margin="0,2" TextWrapping="Wrap" Text="..."/>
                        <TextBlock Grid.Row="4" Grid.Column="0" Text="BIOS" Foreground="#888" FontSize="11" Margin="0,2"/>
                        <TextBlock Grid.Row="4" Grid.Column="1" Name="txtBios" Foreground="#e0e0e0" FontSize="11" Margin="0,2" TextWrapping="Wrap" Text="..."/>
                        <TextBlock Grid.Row="5" Grid.Column="0" Text="Windows" Foreground="#888" FontSize="11" Margin="0,2"/>
                        <TextBlock Grid.Row="5" Grid.Column="1" Name="txtWindows" Foreground="#e0e0e0" FontSize="11" Margin="0,2" TextWrapping="Wrap" Text="..."/>
                    </Grid>
                </Border>
            </StackPanel>

            <Button Grid.Row="6" Name="btnCopyAll" Content="COPY ALL"
                    Height="34" Width="160" HorizontalAlignment="Center"
                    Background="#c5a33e" Foreground="#1a1a1a"
                    FontWeight="Bold" FontSize="12" BorderThickness="0" Cursor="Hand"/>

            <StackPanel Grid.Row="8" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
            <Button Name="btnDiscord" Height="32"
                    Background="#5865F2" Foreground="White" BorderThickness="0" Cursor="Hand"
                    Padding="14,0">
                <StackPanel Orientation="Horizontal">
                    <Canvas Width="18" Height="14" Margin="0,0,8,0">
                        <Path Fill="White" Data="M15.25 2.7A14.5 14.5 0 0 0 11.6 1.5a.05.05 0 0 0-.06.03 10 10 0 0 0-.44.9 13.4 13.4 0 0 0-4.02 0 9.2 9.2 0 0 0-.45-.9.05.05 0 0 0-.05-.03c-1.3.22-2.53.6-3.66 1.2a.05.05 0 0 0-.02.02C.44 6.18-.27 9.55.08 12.88a.06.06 0 0 0 .02.04 14.6 14.6 0 0 0 4.4 2.22.05.05 0 0 0 .06-.02c.34-.46.64-.95.9-1.46a.05.05 0 0 0-.03-.07 9.6 9.6 0 0 1-1.37-.66.05.05 0 0 1 0-.09c.09-.07.18-.14.27-.21a.05.05 0 0 1 .05-.01c2.88 1.32 6 1.32 8.85 0a.05.05 0 0 1 .05 0c.09.08.18.15.28.22a.05.05 0 0 1 0 .09c-.44.25-.9.47-1.38.65a.05.05 0 0 0-.03.07c.27.52.57 1 .9 1.47a.05.05 0 0 0 .06.02 14.5 14.5 0 0 0 4.42-2.22.05.05 0 0 0 .02-.04c.42-4.33-.7-8.1-2.96-11.43a.04.04 0 0 0-.02-.02zM5.68 10.8c-.99 0-1.8-.91-1.8-2.03s.8-2.03 1.8-2.03c1.01 0 1.82.92 1.8 2.03 0 1.12-.8 2.03-1.8 2.03zm6.65 0c-.99 0-1.8-.91-1.8-2.03s.8-2.03 1.8-2.03c1.01 0 1.82.92 1.8 2.03 0 1.12-.79 2.03-1.8 2.03z"/>
                    </Canvas>
                    <TextBlock Name="txtDiscordBtn" Text="Join Discord" FontWeight="SemiBold" FontSize="12" VerticalAlignment="Center"/>
                </StackPanel>
            </Button>
            <TextBlock Name="txtDiscordDm" Text="Send info to MapleSyrupJunkie" Foreground="#888" FontSize="11"
                       VerticalAlignment="Center" Margin="10,0,0,0"/>
            </StackPanel>

            <Button Grid.Row="10" Name="btnAnyDesk" Height="32" HorizontalAlignment="Center"
                    Background="#ef443b" Foreground="White" BorderThickness="0" Cursor="Hand"
                    Padding="14,0">
                <TextBlock Name="txtAnyDeskBtn" Text="Download AnyDesk" FontWeight="SemiBold" FontSize="12" VerticalAlignment="Center"/>
            </Button>

            <StackPanel Grid.Row="12" Margin="0,0,0,4">
                <TextBlock Name="txtStep1" Foreground="#aaa" FontSize="11" TextWrapping="Wrap" Margin="0,2"
                           Text="1. Make sure to join the discord and copy this info and send it to me (MapleSyrupJunkie)"/>
                <TextBlock Name="txtStep2" Foreground="#aaa" FontSize="11" TextWrapping="Wrap" Margin="0,2"
                           Text="2. Make sure windows is up to date (Install from Windows Updates)"/>
                <TextBlock Name="txtStep3" Foreground="#aaa" FontSize="11" TextWrapping="Wrap" Margin="0,2"
                           Text="3. Have a USB thumb drive at your disposal (might be required for bios updates/settings)"/>
                <TextBlock Name="txtStep4" Foreground="#aaa" FontSize="11" TextWrapping="Wrap" Margin="0,2"
                           Text="4. Have a USB thumb drive at your disposal, does not need a lot of space (might be required for bios updates/settings)"/>
                <TextBlock Name="txtStep5" Foreground="#aaa" FontSize="11" TextWrapping="Wrap" Margin="0,2"
                           Text="5. Discord ready and functional on your mobile phone (video will be required for BIOS tuning)"/>
            </StackPanel>

            <WrapPanel Grid.Row="14" HorizontalAlignment="Center">
                <TextBlock Margin="8,0"><Hyperlink Name="lnkWeb" Foreground="#c5a33e">gepcperformance.com</Hyperlink></TextBlock>
                <TextBlock Foreground="#444" Text="|"/>
                <TextBlock Margin="8,0"><Hyperlink Name="lnkTwitch" Foreground="#c5a33e">Twitch</Hyperlink></TextBlock>
                <TextBlock Foreground="#444" Text="|"/>
                <TextBlock Margin="8,0"><Hyperlink Name="lnkYoutube" Foreground="#c5a33e">YouTube</Hyperlink></TextBlock>
                <TextBlock Foreground="#444" Text="|"/>
                <TextBlock Margin="8,0"><Hyperlink Name="lnkEmail" Foreground="#c5a33e">gepcperformance@gmail.com</Hyperlink></TextBlock>
            </WrapPanel>

            <Button Grid.Row="16" Content="Close" Width="80" Height="28"
                    HorizontalAlignment="Center" Name="btnClose"
                    Background="#333" Foreground="#aaa" BorderThickness="0" Cursor="Hand"/>
        </Grid>
    </Border>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Get controls
$txtFingerprint = $window.FindName("txtFingerprint")
$txtCpu = $window.FindName("txtCpu")
$txtGpu = $window.FindName("txtGpu")
$txtRam = $window.FindName("txtRam")
$txtMotherboard = $window.FindName("txtMotherboard")
$txtBios = $window.FindName("txtBios")
$txtWindows = $window.FindName("txtWindows")
$btnCopyAll = $window.FindName("btnCopyAll")
$btnClose = $window.FindName("btnClose")
$lblFingerprint = $window.FindName("lblFingerprint")
$lblSpecs = $window.FindName("lblSpecs")
$lblMotherboard = $window.FindName("lblMotherboard")

# Apply localization
$window.Title = $str.Title
$lblFingerprint.Text = $str.Fingerprint
$lblSpecs.Text = $str.Specs
$lblMotherboard.Text = $str.Motherboard
$btnCopyAll.Content = $str.CopyAll
$txtFingerprint.Text = $str.Collecting
$window.FindName("txtDiscordBtn").Text = $str.Discord
$window.FindName("txtDiscordDm").Text = $str.DiscordDm
$btnClose.Content = $str.Close
$window.FindName("txtAnyDeskBtn").Text = $str.AnyDesk
$window.FindName("txtStep1").Text = $str.Step1
$window.FindName("txtStep2").Text = $str.Step2
$window.FindName("txtStep3").Text = $str.Step3
$window.FindName("txtStep4").Text = $str.Step4
$window.FindName("txtStep5").Text = $str.Step5

# Drag support
$window.Add_MouseLeftButtonDown({ $window.DragMove() })

# Close button
$btnClose.Add_Click({ $window.Close() })

# Hyperlinks
$links = @{
    "lnkWeb"     = "https://gepcperformance.com"
    "lnkTwitch"  = "https://twitch.tv/maplesyrupjunkie"
    "lnkYoutube" = "https://www.youtube.com/maplesyrupjunkie"
    "lnkEmail"   = "mailto:gepcperformance@gmail.com"
}
foreach ($name in $links.Keys) {
    $hl = $window.FindName($name)
    $uri = $links[$name]
    $hl.Add_Click({ Start-Process $uri }.GetNewClosure())
}

$btnDiscord = $window.FindName("btnDiscord")
$btnDiscord.Add_Click({ Start-Process "https://discord.gg/jRG6xsCHtJ" })

$btnAnyDesk = $window.FindName("btnAnyDesk")
$anyDeskUrl = $str.AnyDeskUrl
$btnAnyDesk.Add_Click({ Start-Process $anyDeskUrl }.GetNewClosure())

# Copy All button
$btnCopyAll.Add_Click({
    $text = "Fingerprint: $($txtFingerprint.Text)`nCPU: $($txtCpu.Text)`nGPU: $($txtGpu.Text)`nRAM: $($txtRam.Text)`nMotherboard: $($txtMotherboard.Text)`nBIOS: $($txtBios.Text)`nWindows: $($txtWindows.Text)"
    [System.Windows.Clipboard]::SetText($text)
    $btnCopyAll.Content = $str.Copied
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(2)
    $timer.Add_Tick({ $btnCopyAll.Content = $str.CopyAll; $timer.Stop() })
    $timer.Start()
})

# Collect info after window loads
$window.Add_Loaded({
    $txtFingerprint.Text = Get-HardwareFingerprint
    $txtCpu.Text = Get-CpuInfo
    $txtGpu.Text = Get-GpuInfo
    $txtRam.Text = Get-RamInfo
    $txtMotherboard.Text = Get-MotherboardInfo
    $txtBios.Text = Get-BiosInfo
    $txtWindows.Text = Get-WindowsInfo
})

$window.ShowDialog() | Out-Null
