if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    Exit
}

# 1. Restore default Registry Values
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" -Name "SearchOrderConfig" -Value 1
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" -Value 0

# 2. Remove the GPO block
$GPOPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
if (Test-Path $GPOPath) {
    Remove-ItemProperty -Path $GPOPath -Name "ExcludeWUDriversInQualityUpdate" -ErrorAction SilentlyContinue
}

# 3. Remove modern UpdatePolicy block
$PolicyStatePath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\PolicyState"
if (Test-Path $PolicyStatePath) {
    Remove-ItemProperty -Path $PolicyStatePath -Name "ExcludeWUDrivers" -ErrorAction SilentlyContinue
}

# 4. Refresh Group Policy and UI
Write-Host "Reverting policies..." -ForegroundColor Cyan
gpupdate /force
Stop-Process -Name explorer -Force
Write-Host "Driver updates are now enabled." -ForegroundColor Green
