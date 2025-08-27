# install.ps1
# Deploys a logon popup (WPF) and ensures it starts at every user logon

$AppRoot   = "C:\Program Files\Company\LogonNotice"
$Script    = Join-Path $AppRoot "LogonNotice.ps1"
$RegPath   = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$ValueName = "CompanyLogonNotice"
$AllUsersStartup = "$Env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"
$LnkPath   = Join-Path $AllUsersStartup "GEHealthcare Logon Notice.lnk"

# 1) Create program folder
New-Item -Path $AppRoot -ItemType Directory -Force | Out-Null

# 2) Write the popup script (STA, no elevation)
$popup = @'
# Relaunch as STA if needed (no elevation)
if ([Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
    Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile","-STA","-ExecutionPolicy","Bypass","-File","`"$PSCommandPath`"") -WindowStyle Hidden
    return
}

# WPF assemblies (not supported on Server Core)
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

[int]$countdownSeconds = 240   # 4 minutes
$titleText   = "GEHealthcare Notification"
$bodyText    = "You have tasks awaiting your attention. Please ensure all tasks are completed before the end of the day."
$detailText  = "This window will automatically close in 4 minutes."

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        WindowStyle="None"
        Topmost="True"
        ShowInTaskbar="True"
        Width="680" Height="360"
        Background="#FF0F172A">
    <Grid Margin="24">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock x:Name="Hdr" FontSize="26" FontWeight="Bold" Foreground="White" Margin="0,0,0,12"/>
        <StackPanel Grid.Row="1" Orientation="Vertical" Margin="0,0,0,12">
            <TextBlock x:Name="Msg"  TextWrapping="Wrap" Foreground="#FFDFE7F0" FontSize="16" />
            <TextBlock x:Name="Dtl"  TextWrapping="Wrap" Foreground="#FF9FB3C8" Margin="0,8,0,0"/>
        </StackPanel>

        <StackPanel Grid.Row="2" Orientation="Vertical">
            <ProgressBar x:Name="Bar" Minimum="0" Maximum="100" Height="14"/>
            <TextBlock x:Name="TimerText" HorizontalAlignment="Center" Margin="0,8,0,0" Foreground="#FFDFE7F0"/>
        </StackPanel>

        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,18,0,0">
            <Button x:Name="CloseBtn" Content="Close" IsEnabled="False" MinWidth="96" Height="34" Padding="12,4" />
        </StackPanel>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$window.FindName("Hdr").Text = $titleText
$window.FindName("Msg").Text = $bodyText
$window.FindName("Dtl").Text = $detailText

$bar      = $window.FindName("Bar")
$timerTxt = $window.FindName("TimerText")
$closeBtn = $window.FindName("CloseBtn")

$script:canClose = $false
$window.Add_Closing({ param($s,$e) if (-not $script:canClose) { $e.Cancel = $true } })
$window.Add_PreviewKeyDown({
    param($s,$e)
    if (-not $script:canClose) {
        if (($e.SystemKey -eq [System.Windows.Input.Key]::F4) -or ($e.Key -eq [System.Windows.Input.Key]::Escape)) { $e.Handled = $true }
    }
})

$sw = [Diagnostics.Stopwatch]::StartNew()
$dispatcherTimer = New-Object Windows.Threading.DispatcherTimer
$dispatcherTimer.Interval = [TimeSpan]::FromSeconds(0.2)
$dispatcherTimer.Add_Tick({
    $elapsed   = [int]$sw.Elapsed.TotalSeconds
    $remaining = [math]::Max($countdownSeconds - $elapsed, 0)
    $pct = [math]::Round(100 * ($elapsed / $countdownSeconds))
    if ($pct -gt 100) { $pct = 100 }
    $bar.Value = $pct
    $timerTxt.Text = "Please wait: $([TimeSpan]::FromSeconds($remaining).ToString('mm\:ss'))"
    if ($remaining -le 0) {
        $script:canClose = $true
        $closeBtn.IsEnabled = $true
        $timerTxt.Text = "You may close this window."
        $dispatcherTimer.Stop()
    }
})
$dispatcherTimer.Start()
$closeBtn.Add_Click({ $window.Close() })
$null = $window.ShowDialog()
'@

Set-Content -Path $Script -Value $popup -Encoding UTF8 -Force

# 3) Primary autorun: HKLM Run (forces STA)
$cmd = "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Script`""
New-ItemProperty -Path $RegPath -Name $ValueName -PropertyType String -Value $cmd -Force | Out-Null

# 4) Fallback autorun: All Users Startup shortcut (.lnk)
if (-not (Test-Path $AllUsersStartup)) {
    New-Item -Path $AllUsersStartup -ItemType Directory -Force | Out-Null
}
try {
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($LnkPath)
    $lnk.TargetPath = "powershell.exe"
    $lnk.Arguments  = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Script`""
    $lnk.WorkingDirectory = $AppRoot
    $lnk.IconLocation = "$Env:SystemRoot\System32\shell32.dll,70"
    $lnk.Save()
} catch { }

Write-Host "LogonNotice installed. (Run key + Startup shortcut created)"
exit 0
