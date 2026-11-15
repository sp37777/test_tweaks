if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    Exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- CLEANUP EXISTING OFFICE (Prevent Arch Conflicts) ---
Function Uninstall-ExistingOffice {
    Write-Host "Checking for existing Office installations..." -ForegroundColor Yellow
    $keys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($key in $keys) {
        if (Test-Path $key) {
            Get-ChildItem $key | ForEach-Object {
                $product = Get-ItemProperty $_.PSPath
                if ($product.DisplayName -match "Microsoft Office" -and $product.UninstallString) {
                    Write-Host "Found: $($product.DisplayName). Attempting silent uninstall..." -ForegroundColor Gray
                    Start-Process msiexec.exe -ArgumentList "/x $($product.PSChildName) /qn /norestart" -Wait
                }
            }
        }
    }
}

# --- OS & ARCH DETECTION (Legacy Compatible) ---
try {
    # Use Get-WmiObject instead of Get-CimInstance for Win7 compatibility
    $osInfo = Get-WmiObject Win32_OperatingSystem
    $osVersion = $osInfo.Version
    $osMajor = [int]($osVersion.Split('.')[0])
    $osMinor = [int]($osVersion.Split('.')[1])
    
    # Win7 sometimes doesn't have 'OSArchitecture' property in WMI; fallback to environment
    $osArch = $osInfo.OSArchitecture
    if (!$osArch) { $osArch = $env:PROCESSOR_ARCHITECTURE }
} catch {
    # Absolute fallback if WMI is corrupted
    $osMajor = 6
    $osMinor = 1
    $osArch = "64-bit"
}

$officeArch = if ($osArch -match "64") { "64" } else { "32" }
$workDir = "C:\OfficeSetup"

# Determine Best Office Version for the OS
$channel = "PerpetualVL2024"
$prodID = "ProPlus2024Volume"
$osName = "Windows 10/11"

# Windows 7/8 detection logic
if ($osMajor -le 6) {
    if ($osMajor -eq 6 -and $osMinor -eq 3) { 
        $osName = "Windows 8.1"
    } else { 
        $osName = "Windows 7"
    }
    # Force Office 2016/2019 for legacy systems
    $channel = "MonthlyEnterprise" 
    $prodID = "ProPlusRetail"
}

if (!(Test-Path $workDir)) { New-Item -ItemType Directory -Path $workDir }
Set-Location $workDir

# Run cleanup before GUI
Uninstall-ExistingOffice

# --- GUI DEFINITION ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "Universal Office Installer ($officeArch-bit)"
$form.Size = New-Object System.Drawing.Size(400,480)
$form.StartPosition = "CenterScreen"

$label = New-Object System.Windows.Forms.Label
$label.Text = "Detected: $osName`nArchitecture: $osArch`nTargeting: $prodID ($channel)`n`nSelect apps to install:"
$label.Location = New-Object System.Drawing.Point(20,10)
$label.Size = New-Object System.Drawing.Size(350,80)
$form.Controls.Add($label)

$apps = @{
    "Word" = "Word"; "Excel" = "Excel"; "PowerPoint" = "PowerPoint";
    "Outlook" = "Outlook"; "OneNote" = "OneNote"; "Access" = "Access";
    "Publisher" = "Publisher"; "Teams" = "Teams"
}

$checkboxes = @{}
$yPos = 100
foreach ($appName in ($apps.Keys | Sort-Object)) {
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $appName
    $cb.Location = New-Object System.Drawing.Point(30, $yPos)
    $cb.Checked = if ($appName -match "Word|Excel|PowerPoint") { $true } else { $false }
    $form.Controls.Add($cb)
    $checkboxes[$appName] = $cb
    $yPos += 30
}

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = "Start Hardened Install"
$btnInstall.Location = New-Object System.Drawing.Point(100, 370)
$btnInstall.Size = New-Object System.Drawing.Size(180, 40)
$btnInstall.Add_Click({
    $script:selectedApps = @()
    foreach ($name in $apps.Keys) {
        if ($checkboxes[$name].Checked) { $script:selectedApps += $apps[$name] }
    }
    $form.Close()
})
$form.Controls.Add($btnInstall)

$form.ShowDialog() | Out-Null
if (!$script:selectedApps) { exit }

# --- DYNAMIC XML GENERATION ---
$allPossibleApps = @("Lync","Teams","OneDrive","OneNote","Outlook","Publisher","Access","Bing","Groove")
$excludes = ""
foreach ($appID in $allPossibleApps) {
    if ($appID -eq "OneDrive") { $excludes += "      <ExcludeApp ID=""$appID"" />`n"; continue }
    if ($script:selectedApps -notcontains $appID) {
        $excludes += "      <ExcludeApp ID=""$appID"" />`n"
    }
}

$offVer = "16.0"

$xmlContent = @"
<Configuration>
  <Add OfficeClientEdition="$officeArch" Channel="$channel">
    <Product ID="$prodID">
      <Language ID="uk-ua" />
$excludes    </Product>
  </Add>
  <Property Name="AUTOACTIVATE" Value="1" />
  <AppSettings>
    <User Key="software\microsoft\office\$offVer\common\general" Name="prefercloudsavelocations" Value="0" Type="REG_DWORD" />
    <User Key="software\microsoft\office\$offVer\common\privacy" Name="disconnectedstate" Value="1" Type="REG_DWORD" />
    <User Key="software\microsoft\office\$offVer\common\privacy" Name="enabletelemetry" Value="0" Type="REG_DWORD" />
    <User Key="software\microsoft\office\$offVer\common\privacy" Name="usercontentdisabled" Value="1" Type="REG_DWORD" />
    <User Key="software\microsoft\office\$offVer\common\privacy" Name="downloadcontentdisabled" Value="1" Type="REG_DWORD" />
    <User Key="software\microsoft\office\$offVer\common\privacy" Name="controllerconnectedservicesenabled" Value="2" Type="REG_DWORD" />
  </AppSettings>
  <Display Level="Full" AcceptEULA="TRUE" />
</Configuration>
"@

$xmlContent | Out-File -FilePath "$workDir\config.xml" -Encoding utf8

# TLS and Header Setup for older OS compatibility
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$headers = @{"User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}

# --- ODT DOWNLOAD ---
Write-Host "Downloading latest Setup Engine..." -ForegroundColor Cyan
$setupUrl = "https://officecdn.microsoft.com/pr/wsus/setup.exe"
Invoke-WebRequest -Uri $setupUrl -OutFile "$workDir\setup.exe" -Headers $headers

# --- INSTALLATION ---
Write-Host "Installing $prodID..." -ForegroundColor Yellow
Start-Process -FilePath "$workDir\setup.exe" -ArgumentList "/configure $workDir\config.xml" -Wait

# --- FINAL LOCKDOWN ---
Write-Host "Applying advanced telemetry lockdown..." -ForegroundColor Cyan

# Turn off scheduler tasks
Get-ScheduledTask -TaskPath "\Microsoft\Office\" -ErrorAction SilentlyContinue | Disable-ScheduledTask

$privacyPath = "Software\Microsoft\Office\$offVer\Common\Privacy"
$policyPath = "Software\Policies\Microsoft\Office\$offVer\Common\Privacy"

# Make registry paths if needed
$registryPaths = @("HKCU:\$privacyPath", "HKCU:\$policyPath")
foreach ($path in $registryPaths) {
    if (!(Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
}

# 1. Disable main telemetry
Set-ItemProperty -Path "HKCU:\$privacyPath" -Name "EnableLogging" -Value 0
Set-ItemProperty -Path "HKCU:\$privacyPath" -Name "TelemetryLevel" -Value 0

# 2. Disable "Optional Connected Experiences" (most important for confidence)
# It will turn off cloud fonts, translate, online-vocabularies etc.
Set-ItemProperty -Path "HKCU:\$policyPath" -Name "DisconnectedState" -Value 1
Set-ItemProperty -Path "HKCU:\$policyPath" -Name "EnableCustomerExperienceImprovementProgram" -Value 0

# 3. Turn off online templates and help download
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Office\$offVer\Common\General" -Name "ShownFirstRunOptin" -Value 1

# Turn off service controller via policy (highest priority)
Set-ItemProperty -Path "HKCU:\$policyPath" -Name "controllerconnectedservicesenabled" -Value 2

Write-Host "Done! Office installed and hardened for $osName." -ForegroundColor Green