if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    Exit
}

# 1. Detect Architecture
$is64Bit = [Environment]::Is64BitOperatingSystem

if ($is64Bit) {
    $arch = "64"
    $url = "https://bit.ly/npackdcl64-1_26_9" # Latest stable 64-bit MSI
    Write-Host "Detected 64-bit architecture." -ForegroundColor Cyan
} else {
    $arch = "32"
    $url = "https://bit.ly/npackdcl32-1_26_9" # Latest stable 32-bit MSI
    Write-Host "Detected 32-bit architecture." -ForegroundColor Cyan
}

# 2. Set Download Path
$tempPath = "$env:TEMP\NpackdInstaller.msi"

# 3. Download the Installer
Write-Host "Downloading Npackd ($($arch)-bit)..." -ForegroundColor Yellow
try {
    # Ensure TLS 1.2 for secure download on Win 8.1
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($url, $tempPath)
    Write-Host "Download complete." -ForegroundColor Green
} catch {
    Write-Host "Error: Failed to download the installer. Please check your internet connection." -ForegroundColor Red
    exit
}

# 4. Silent Installation
Write-Host "Installing Npackd silently..." -ForegroundColor Yellow
$installArgs = "/i `"$tempPath`" /qb- /norestart"

try {
    Start-Process msiexec.exe -ArgumentList $installArgs -Wait -NoNewWindow
    Write-Host "Npackd installation finished successfully!" -ForegroundColor Green
} catch {
    Write-Host "Error: Installation failed." -ForegroundColor Red
} finally {
    # Cleanup
    if (Test-Path $tempPath) { Remove-Item $tempPath }
}

# 5. Instructions
Write-Host "`nYou can now find 'Npackd' in your Start menu or run 'ncl help' in CMD/PowerShell." -ForegroundColor White
