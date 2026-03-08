if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    Exit
}

# Must be run as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Please run this script as Administrator!"
    exit
}

# --- 1. PROMPT FOR BLUETOOTH ---
$title = "Bluetooth Driver Block"
$message = "Do you want to block the Intel Bluetooth driver? `n(Select 'No' if you use Bluetooth mice, headphones, or controllers.)"
$options = [System.Management.Automation.Host.ChoiceDescription[]] @(
    New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Block Bluetooth"
    New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Allow Bluetooth"
)
$result = $host.ui.PromptForChoice($title, $message, $options, 1)

# --- 2. DEFINE HARDWARE BLOCKLIST ---
$BlockList = @(
    "PCI\VEN_8086&DEV_1C3A", "PCI\VEN_8086&DEV_8C3A", "PCI\VEN_8086&DEV_A13A", "PCI\VEN_8086&DEV_51E0", # MEI
    "PCI\VEN_8086&CC_0780", # Generic Intel Comm Class
    "PCI\VEN_8086&DEV_9D3E", "PCI\VEN_8086&DEV_A135", "PCI\VEN_8086&DEV_54FC", # Sensor Hub
    "PCI\VEN_8086&DEV_9D27", "PCI\VEN_8086&DEV_467E", # Telemetry/PMT
    "ACPI\INT3400", "ACPI\INT33D5", "ACPI\INT33D6"   # Dynamic Tuning / Virtual Buttons
)

if ($result -eq 0) {
    # Generic Bluetooth patterns
    $BlockList += "USB\VID_8087&PID_0026", "USB\VID_8087&PID_0032", "USB\VID_8087&PID_0A2B"
    Write-Host "[!] Bluetooth added to blocklist." -ForegroundColor Magenta
}

# --- 3. APPLY REGISTRY HARDWARE BLOCKS ---
$RegistryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions\DenyDeviceIDs"
if (!(Test-Path $RegistryPath)) { New-Item -Path $RegistryPath -Force | Out-Null }

$Count = 1
foreach ($ID in $BlockList) {
    New-ItemProperty -Path $RegistryPath -Name "$Count" -Value $ID -PropertyType String -Force | Out-Null
    $Count++
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions" -Name "DenyDeviceIDsRetroactive" -Value 1 -Force

# --- 4. DISABLE TELEMETRY & IDSA SERVICES ---
$ServicesToKill = @(
    "IntelCIP",                             # Computing Improvement Program
    "Intel(R) Computing Improvement Program", 
    "EnergyEstimationService",              # Power telemetry
    "DSAService",                           # Intel Driver & Support Assistant
    "DSAUpdateService"                      # Intel DSA Updater
)

Write-Host "`nStopping and disabling background services..." -ForegroundColor Cyan
foreach ($Svc in $ServicesToKill) {
    if (Get-Service $Svc -ErrorAction SilentlyContinue) {
        Stop-Service $Svc -Force -ErrorAction SilentlyContinue
        Set-Service $Svc -StartupType Disabled
        Write-Host "[X] Disabled: $Svc" -ForegroundColor Green
    }
}

# --- 5. REMOVE IDSA FROM AUTO-START ---
$RunPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
if (Get-ItemProperty -Path $RunPath -Name "Intel Driver & Support Assistant" -ErrorAction SilentlyContinue) {
    Remove-ItemProperty -Path $RunPath -Name "Intel Driver & Support Assistant" -Force
    Write-Host "[X] Removed IDSA from System Startup." -ForegroundColor Green
}

Write-Host "`nCleanup Complete! Your Intel drivers are now on a 'Need to Know' basis." -ForegroundColor Yellow