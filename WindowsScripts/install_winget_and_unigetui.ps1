if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    Exit
}

Set-Location $PSScriptRoot

# --- FIX: Force TLS 1.2 for PowerShell Gallery Connection ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "--- Starting Optimization Check ---" -ForegroundColor Cyan

# 1. Smart Check: NuGet Provider
$nuGet = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue
if ($null -eq $nuGet -or [version]$nuGet.Version -lt [version]"2.8.5.201") {
    Write-Host "Installing/Updating NuGet provider..." -ForegroundColor Yellow
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "NuGet provider is up to date ($($nuGet.Version))." -ForegroundColor Green
}

Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted

# 2. Smart Check: Microsoft.WinGet.Client Module
$wingetModule = Get-Module -ListAvailable -Name Microsoft.WinGet.Client
if ($null -eq $wingetModule) {
    Write-Host "Installing WinGet PowerShell module..." -ForegroundColor Yellow
    Install-Module -Name Microsoft.WinGet.Client -Force -Confirm:$false -Scope CurrentUser
} else {
    Write-Host "WinGet module is already installed." -ForegroundColor Green
}

# 3. Attempt WinGet Repair (only if version is old or missing)
try {
    # This command is fast if already current, but we wrap it to be safe
    Repair-WinGetPackageManager -Force -Latest -ErrorAction SilentlyContinue
} catch {}

# 4. Check if UniGetUI is already installed
$checkUI = winget list --id MartiCliment.UniGetUI -e --accept-source-agreements
if ($null -eq $checkUI -or $checkUI.Count -lt 3) {
    Write-Host "UniGetUI not found. Installing..." -ForegroundColor Cyan
    winget install MartiCliment.UniGetUI --accept-package-agreements --accept-source-agreements --override "/NoRunOnStartup /NoAutoStart /VERYSILENT /CURRENTUSER"
} else {
    Write-Host "UniGetUI is already installed. Skipping installation..." -ForegroundColor Green
}

Write-Host "`n--- Setup Complete ---" -ForegroundColor Green
Read-Host "Press Enter to exit"