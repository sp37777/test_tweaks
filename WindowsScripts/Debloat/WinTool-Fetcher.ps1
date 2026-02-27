# Setup
$ErrorActionPreference = "Stop"
$CurrentDir = $PSScriptRoot

function Get-Selection {
    param([string]$Prompt)
    Write-Host "`n$Prompt " -NoNewLine -ForegroundColor Cyan
    return [Console]::ReadKey($true).KeyChar.ToString().ToLower()
}

Write-Host "--- Windows Utility Master Updater ---" -ForegroundColor Magenta
Write-Host "1. Update Chris Titus WinUtil (Compiled .ps1)"
Write-Host "2. Update Win11Debloat (Source .zip)"
Write-Host "3. Update Winhance (Installer .exe + Versioned)"
Write-Host "4. Update ALL TOOLS"
Write-Host "Q. Quit"

$Choice = Get-Selection "Select an option (1-4, Q):"

if ($Choice -eq 'q') { exit }

# --- 1. Chris Titus WinUtil ---
if ($Choice -match '[14]') {
    try {
        Write-Host "`n`n[*] Fetching WinUtil..." -ForegroundColor Cyan
        $WUApi = "https://api.github.com/repos/ChrisTitusTech/winutil/releases/latest"
        $Release = Invoke-RestMethod -Uri $WUApi
        $Asset = $Release.assets | Where-Object { $_.name -eq "winutil.ps1" }
        $Dest = "$CurrentDir\winutil-$($Release.tag_name).ps1"
        Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $Dest
        Write-Host "[+] WinUtil Updated: $Dest" -ForegroundColor Green
        Write-Host "[+] SHA-256: $((Get-FileHash $Dest).Hash)"
    } catch { Write-Host "[-] WinUtil Failed: $($_.Exception.Message)" -ForegroundColor Red }
}

# --- 2. Win11Debloat ---
if ($Choice -match '[24]') {
    try {
        Write-Host "`n[*] Fetching Win11Debloat..." -ForegroundColor Cyan
        $W11Api = "https://api.github.com/repos/Raphire/Win11Debloat/releases/latest"
        $Release = Invoke-RestMethod -Uri $W11Api
        $ZipFile = "$CurrentDir\Win11Debloat-$($Release.tag_name).zip"
        Invoke-WebRequest -Uri $Release.zipball_url -OutFile $ZipFile
        Write-Host "[+] Win11Debloat Updated: $ZipFile" -ForegroundColor Green
        Write-Host "[+] SHA-256: $((Get-FileHash $ZipFile).Hash)"

        $UnzipChoice = Get-Selection "Unzip Win11Debloat now? (y/n):"
        if ($UnzipChoice -eq 'y') {
            $ExtractPath = "$CurrentDir\Win11Debloat-$($Release.tag_name)"
            if (Test-Path $ExtractPath) { Remove-Item $ExtractPath -Recurse -Force }
            Expand-Archive -Path $ZipFile -DestinationPath $ExtractPath
            Write-Host "`n[+] Extracted to: $ExtractPath" -ForegroundColor Green
        }
    } catch { Write-Host "[-] Win11Debloat Failed: $($_.Exception.Message)" -ForegroundColor Red }
}

# --- 3. Winhance ---
if ($Choice -match '[34]') {
    try {
        Write-Host "`n[*] Fetching Winhance..." -ForegroundColor Cyan
        $WinhanceApi = "https://api.github.com/repos/memstechtips/Winhance/releases/latest"
        $Release = Invoke-RestMethod -Uri $WinhanceApi
        $Version = $Release.tag_name
        # Find the installer in assets
        $Asset = $Release.assets | Where-Object { $_.name -like "*Installer.exe" } | Select-Object -First 1
        
        # Create versioned filename
        $Dest = "$CurrentDir\Winhance-$Version.exe"
        
        Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $Dest
        Write-Host "[+] Winhance Updated: $Dest" -ForegroundColor Green
        Write-Host "[+] SHA-256: $((Get-FileHash $Dest).Hash)"
    } catch { Write-Host "[-] Winhance Failed: $($_.Exception.Message)" -ForegroundColor Red }
}

Write-Host "`nAll tasks complete. Press any key to exit..." -ForegroundColor Gray
[Console]::ReadKey($true) | Out-Null