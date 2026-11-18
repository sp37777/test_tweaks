# Windows 8.1 Ultimate Deployment Script (Full Integration)
# Includes: UI, Performance, Privacy, Telemetry, and AppX Bloatware Removal

# --- PART 1: REMOVE BLOATWARE (APPX) ---
Write-Host "Removing AppX Bloatware (Keeping Store, Calculator, Photos)..." -ForegroundColor Cyan
# Remove from the current session
Get-AppxPackage -AllUsers | Where-Object {$_.Name -notmatch 'Store|Calculator|Photos'} | Remove-AppxPackage -ErrorAction SilentlyContinue
# Provisioning prevents them from ever coming back for new users
Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -notmatch 'Store|Calculator|Photos'} | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

# Use this to find the header in the SAME directory
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "Header.ps1")

# UI / Navigation 
Apply-UserTweak "Software\Microsoft\Windows\CurrentVersion\ImmersiveShell\EdgeUI" "DisableCharmsHint" 1 
Apply-UserTweak "Software\Microsoft\Windows\CurrentVersion\ImmersiveShell\EdgeUI" "DisableTRcorner" 1 
Apply-UserTweak "Software\Microsoft\Windows\CurrentVersion\ImmersiveShell\EdgeUI" "DisableTLcorner" 1 
Apply-UserTweak "Software\Policies\Microsoft\Windows\EdgeUI" "DisableHelpSticker" 1 
Apply-UserTweak "Software\Microsoft\Windows\CurrentVersion\Explorer\StartPage" "OpenDesktopRoot" 1 
Apply-UserTweak "Software\Microsoft\Windows\CurrentVersion\Explorer\Accent" "MotionAccentId_v1.00" 219

# Explorer / Performance 
Apply-UserTweak "Control Panel\Desktop" "MenuShowDelay" "50" "String" 
Apply-UserTweak "Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1 
Apply-UserTweak "SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.SecurityAndMaintenance" "Enabled" 0

# --- PART 4: SYSTEM-WIDE TWEAKS (HKLM) ---
Write-Host "Applying System-wide Tweaks & Policies..." -ForegroundColor Cyan

# Privacy, Telemetry & Updates
Apply-SystemTweak "SOFTWARE\Policies\Microsoft\MRT" "DontOfferThroughWUEx" 1
Apply-SystemTweak "SOFTWARE\Policies\Microsoft\SQMClient\Windows" "CEIPEnable" 0
Apply-SystemTweak "SOFTWARE\Policies\Microsoft\Edge" "HideFirstRunExperience" 1
Apply-SystemTweak "SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" "NoAutoRebootWithLoggedOnUsers" 1
Apply-SystemTweak "SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0
# Disable Location Services
Apply-SystemTweak "SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" "DisableLocation" 1
# Disable SmartScreen (Optional, but common in privacy tweaks)
Apply-SystemTweak "SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" "SmartScreenEnabled" "Off"

# Windows Defender Removal/Disabling
Apply-SystemTweak "SOFTWARE\Policies\Microsoft\Windows Defender" "DisableAntiSpyware" 1
Apply-SystemTweak "SOFTWARE\Policies\Microsoft\Windows Defender" "DisableRealtimeMonitoring" 1
# Remove Defender from Startup
Remove-SystemRegistryItem "SOFTWARE\Microsoft\Windows\CurrentVersion\Run" "Windows Defender"

# System Performance & Behavior
Apply-SystemTweak "SOFTWARE\Policies\Microsoft\Windows\Personalization" "NoLockScreen" 1
Apply-SystemTweak "SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "verbosestatus" 1
Apply-SystemTweak "SYSTEM\CurrentControlSet\Control" "WaitToKillServiceTimeout" "2000" -Type String
Apply-SystemTweak "SOFTWARE\Microsoft\PlayTo" "ShowNonCertifiedDevices" 1
Apply-SystemTweak "SOFTWARE\Microsoft\Windows\Windows Error Reporting" "Disabled" 1

if( Should-Apply 'DisableSuperfetch' ) {
    # Disable Superfetch (Prevents constant HDD thrashing)
    Stop-Service -Name "SysMain" -ErrorAction SilentlyContinue
    Set-Service -Name "SysMain" -StartupType Disabled
}

if( Should-Apply 'DisableScheduledDefrag' ) {
    # Bulletproof Defrag Disable
    $TaskPath = "\Microsoft\Windows\Defrag\ScheduledDefrag"
    try {
        if (Get-ScheduledTask -TaskName "ScheduledDefrag" -ErrorAction SilentlyContinue) {
            Disable-ScheduledTask -TaskName "ScheduledDefrag" -Confirm:$false
            Write-Host "Defrag disabled via PowerShell."
        } else {
            # Fallback to legacy command
            schtasks /change /tn $TaskPath /disable
            Write-Host "Defrag disabled via schtasks."
        }
    } catch {
        Write-Warning "Could not disable Defrag task, but continuing script..."
    }
}

# DISABLE OS UPGRADE
# 1. Disable "Get Windows 10" (GWX) tray icon and notifications
Apply-SystemTweak "SOFTWARE\Policies\Microsoft\Windows\Gwx" "DisableGwx" 1
# 2. Prevent OS Upgrades via Windows Update
Apply-SystemTweak "SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" "DisableOSUpgrade" 1
# 3. Disable the "End of Support" full-screen prompts
Apply-SystemTweak "SOFTWARE\Microsoft\Windows\CurrentVersion\Gwx" "DisableGwx" 1

# Force kill the process if it's running to avoid the "Waiting" loop
Get-Process -Name "DiagTrack" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
# Disable the service so it doesn't start on reboot
Set-Service -Name "DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue

# Disable scheduler telemetry tasks (critical!)
Disable-ScheduledTask -TaskName "ProgramDataUpdater" -TaskPath "\Microsoft\Windows\Application Experience\" -ErrorAction SilentlyContinue
Disable-ScheduledTask -TaskName "Microsoft-Windows-DiskDiagnosticDataCollector" -TaskPath "\Microsoft\Windows\DiskDiagnostic\" -ErrorAction SilentlyContinue

Write-Host "All tweaks applied successfully!" -ForegroundColor Green