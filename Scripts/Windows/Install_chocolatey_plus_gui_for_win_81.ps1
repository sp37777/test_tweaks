if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    Exit
}

# 1. Check for .NET 4.8 (Release key 528040 or higher)
$dotNetRelease = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Release
$isNet48Installed = $dotNetRelease -ge 528040

# 2. Check if a reboot is pending
$rebootPending = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"

# Function to handle the restart prompt
function Prompt-Restart {
    $message = "A system restart is required to finish .NET installation. Restart now? (y/n)"
    $choice = Read-Host -Prompt "$message"
    
    if ($choice -eq "y") {
        Write-Host "Restarting system..." -ForegroundColor Cyan
        Restart-Computer
    } else {
        Write-Host "Critical: You must restart the computer before you can continue installing Chocolatey." -ForegroundColor Red
        exit
    }
}

if (-not $isNet48Installed) {
    Write-Host "--- .NET 4.8 is NOT installed. Starting installation... ---" -ForegroundColor Yellow
    # Triggering the installer
    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; 
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    
    Prompt-Restart
}

if ($rebootPending) {
    Write-Host "--- Found a pending reboot from a previous installation. ---" -ForegroundColor Yellow
    Prompt-Restart
}

# 3. If we passed the checks, install Chocolatey CLI
Write-Host "--- .NET 4.8 confirmed. Proceeding with Chocolatey install... ---" -ForegroundColor Green
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; 
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# 4. RELOAD ENVIRONMENT VARIABLES
# This allows the current session to "see" the 'choco' command immediately
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# 5. Install the GUI
Write-Host "--- Installing Chocolatey GUI... ---" -ForegroundColor Cyan
choco install chocolateygui -y

# 6. Launch Chocolatey GUI
Write-Host "--- Launching Chocolatey GUI... ---" -ForegroundColor Green
Start-Process "chocolateygui"