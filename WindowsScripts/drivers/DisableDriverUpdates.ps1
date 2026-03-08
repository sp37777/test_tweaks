if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    Exit
}

# 1. Force Registry Keys to stop Driver Searching
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" -Name "SearchOrderConfig" -Value 0
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" -Value 1

# 2. Apply Group Policy equivalent via Registry (The "Nuclear" option)
$GPOPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
if (!(Test-Path $GPOPath)) { New-Item -Path $GPOPath -Force }
Set-ItemProperty -Path $GPOPath -Name "ExcludeWUDriversInQualityUpdate" -Value 1

# 3. Disable through UpdatePolicy key (modern Win10 versions)
$PolicyStatePath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\PolicyState"
if (!(Test-Path $PolicyStatePath)) { New-Item -Path $PolicyStatePath -Force }
Set-ItemProperty -Path $PolicyStatePath -Name "ExcludeWUDrivers" -Value 1

# 4. Refresh Group Policy and UI
Write-Host "Applying policies and refreshing UI..." -ForegroundColor Cyan
gpupdate /force
Stop-Process -Name explorer -Force # Restarts Explorer to refresh icon/UI state
Write-Host "Driver updates are now blocked." -ForegroundColor Green
