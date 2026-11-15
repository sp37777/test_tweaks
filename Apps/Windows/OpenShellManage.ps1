# 1. Force TLS 1.2 and set User-Agent
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$headers = @{"User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}

$repo = "Open-Shell/Open-Shell-Menu"

# 2. Choice Prompt (Default is Download)
Write-Host "`n--- Open-Shell USB Manager (Versioned) ---" -ForegroundColor Cyan
Write-Host "What would you like to do?"
Write-Host "[D] Download latest to USB (Default)"
Write-Host "[I] Install/Update this PC from USB"
$choice = Read-Host "Choice [D/I]"
if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "D" }

# 3. Find existing installer on USB (partial match)
$existingFile = Get-ChildItem -Path $PSScriptRoot -Filter "OpenShellSetup*.exe" | Select-Object -First 1

# 4. GitHub Check
try {
    Write-Host "Checking GitHub..." -ForegroundColor Gray
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers $headers
    $latestTag = $release.tag_name
    $latestVersion = [version]($latestTag -replace 'v', '')
    
    $asset = $release.assets | Where-Object { $_.name -like "*.exe" } | Select-Object -First 1
    $downloadUrl = $asset.browser_download_url
    $githubFileName = $asset.name  # e.g., OpenShellSetup_4_4_191.exe
    $newLocalPath = Join-Path $PSScriptRoot $githubFileName

    # Version Comparison
    $needsDownload = $false
    if (-not $existingFile) {
        $needsDownload = $true
        Write-Host "No installer found on USB." -ForegroundColor Yellow
    } else {
        $localVersion = [version]$existingFile.VersionInfo.FileVersion
        Write-Host "Found on USB: $($existingFile.Name) (v$localVersion)" -ForegroundColor Gray
        
        if ($latestVersion -gt $localVersion) {
            $needsDownload = $true
            Write-Host "Update available: v$latestVersion" -ForegroundColor Yellow
        } else {
            Write-Host "USB is already up to date (v$localVersion)." -ForegroundColor Green
        }
    }

    if ($needsDownload -and $choice -eq "D") {
        # Clean up old version first if it exists
        if ($existingFile) { 
            Write-Host "Removing old version..." -ForegroundColor Gray
            Remove-Item $existingFile.FullName -Force 
        }
        
        Write-Host "Downloading $githubFileName..." -ForegroundColor Green
        Invoke-WebRequest -Uri $downloadUrl -OutFile $newLocalPath -Headers $headers
        $existingFile = Get-Item $newLocalPath # Update reference for install step
    }
} catch {
    Write-Warning "GitHub Access Failed. Will try to use local file if it exists."
}

# 5. Installation Logic
if ($choice -eq "I") {
    if (-not $existingFile) {
        Write-Error "Error: No installer found on USB and couldn't download a new one."
    } else {
        # Check PC Registry for current install
        $installed = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | 
                     Where-Object { $_.DisplayName -like "*Open-Shell*" }
        
        if ($installed -and ([version]$installed.DisplayVersion -ge $latestVersion)) {
            Write-Host "PC already has v$($installed.DisplayVersion). No install needed." -ForegroundColor Green
        } else {
            Write-Host "Installing $($existingFile.Name)..." -ForegroundColor Green
            Start-Process -FilePath $existingFile.FullName -ArgumentList "/qn", "ADDLOCAL=StartMenu" -Wait
            Write-Host "Done!" -ForegroundColor Cyan
        }
    }
}

Write-Host "`nFinished." -ForegroundColor Gray