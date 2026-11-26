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

# 3. Repair WinGet and wait until it becomes available
try {
    Repair-WinGetPackageManager -Force -Latest -ErrorAction Stop

    $wingetReady = $false
    for ($i = 0; $i -lt 10; $i++) {
        winget --version *> $null
        if ($LASTEXITCODE -eq 0) {
            $wingetReady = $true
            break
        }
        Start-Sleep -Seconds 2
    }

    if (-not $wingetReady) {
        throw "WinGet is not responding after repair."
    }
} catch {
    Write-Host "WinGet repair/check failed: $_" -ForegroundColor Red
    throw
}

# 4. Check if UniGetUI is already installed
$packageId = "Devolutions.UniGetUI"

$checkUI = winget list --id $packageId --exact --accept-source-agreements --disable-interactivity 2>&1 | Out-String

# Look for the exact package ID in the results, not the number of output lines
if ($checkUI -match "(?im)^\s*.*\bDevolutions\.UniGetUI\b.*$") {
    Write-Host "UniGetUI is already installed. Skipping installation..." -ForegroundColor Green
} else {
    Write-Host "UniGetUI not found. Installing..." -ForegroundColor Cyan

    winget install --exact --id $packageId --source winget --accept-package-agreements --accept-source-agreements --override "/NoRunOnStartup /NoAutoStart /VERYSILENT /CURRENTUSER"

    if ($LASTEXITCODE -ne 0) {
        Write-Host "UniGetUI installation failed. Exit code: $LASTEXITCODE" -ForegroundColor Red
    }
}

Write-Host "`n--- Setup Complete ---" -ForegroundColor Green
Read-Host "Press Enter to exit"