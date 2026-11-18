# ==============================================================================
# Cross-Windows Compatibility Script (7, 8.1, 10, 11)
# Optimized for: Windows Setup "Specialize" Stage
# ==============================================================================
# Use this to find the header in the SAME directory
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "Header.ps1")

# Disable "- Shortcut" Text
Apply-UserTweak "Software\Microsoft\Windows\CurrentVersion\Explorer" "link" ([byte[]](0,0,0,0)) "Binary"

# CMD Customization
$cmdPath = "Console\%SystemRoot%_system32_cmd.exe"
Apply-UserTweak $cmdPath "QuickEdit" 1
Apply-UserTweak $cmdPath "ScreenBufferSize" 58982480
Apply-UserTweak $cmdPath "FontSize" 1048576
Apply-UserTweak $cmdPath "FontFamily" 54
Apply-UserTweak $cmdPath "FontWeight" 400
Apply-UserTweak $cmdPath "FaceName" "Consolas" "String"

# System UI & Behavior
Apply-UserTweak "Software\Microsoft\Shared Tools\MsConfig" "NoRebootUI" 1

Apply-UserTweak "Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" "EnthusiastMode" 1

# Startup Performance
Apply-UserTweak "Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" "StartupDelayInMSec" 0

# Privacy: Ink and Text Collection
Apply-UserTweak "Software\Microsoft\InputPersonalization" "RestrictImplicitTextCollection" 1
Apply-UserTweak "Software\Microsoft\InputPersonalization" "RestrictImplicitInkCollection" 1

# Desktop Preferences Mask
Apply-UserTweak "Control Panel\Desktop" "UserPreferencesMask" ([byte[]](0x90,0x12,0x03,0x80,0x92,0x00,0x00,0x00)) "Binary"

# Windows 7 & 8.1: Show My Computer Icon
$myCompGUID = "{20D04FE0-3AEA-1069-A2D8-08002B30309D}"
#$recycleBinGUID = "{645FF040-5081-101B-9F08-00AA002F954E}"

# New Start Panel (Common for both)
Apply-UserTweak "Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" $myCompGUID 0 "DWord"
    
# Classic Start Menu (Necessary for Windows 7)
#if ($osVersion -eq "7") {
#    Apply-UserTweak "Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu" $myCompGUID 0 "DWord"
#}

# Show file extensions
Apply-UserTweak "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideFileExt" 0 "DWord"


# --- System-Wide Tweaks (HKLM) ---

# Windows Error Reporting
Apply-SystemTweak "SOFTWARE\Microsoft\Windows\Windows Error Reporting" "Disabled" 1

# Memory Management: Disable Paging Executive
Apply-SystemTweak "System\CurrentControlSet\Control\Session Manager\Memory Management" "DisablePagingExecutive" 1


# Enable F8 Last Known Good
Apply-SystemTweak "SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager\LastKnownGood" "Enabled" 1

# Add System Tools to "This PC" / "My Computer" Context
$sys32   = [System.IO.Path]::Combine($env:SystemRoot, "System32")
$clsBase = "SOFTWARE\Classes\CLSID\{20D04FE0-3AEA-1069-A2D8-08002B30309D}\shell"

# Device Manager
Apply-SystemTweak "$clsBase\DevMgr" "MUIVerb" "@$sys32\devmgr.dll,-4" "String"
Apply-SystemTweak "$clsBase\DevMgr" "Icon" "devmgr.dll,5" "String"
Apply-SystemTweak "$clsBase\DevMgr\command" "(Default)" "mmc.exe devmgmt.msc" "String"

# Disk Management
Apply-SystemTweak "$clsBase\DiskMgmt" "MUIVerb" "@$sys32\dmdskres.dll,-1003" "String"
Apply-SystemTweak "$clsBase\DiskMgmt" "Icon" "dmdskres.dll,0" "String"
Apply-SystemTweak "$clsBase\DiskMgmt\command" "(Default)" "mmc.exe diskmgmt.msc" "String"

# Device Installation Settings
Apply-SystemTweak "$clsBase\DeviceInstall" "MUIVerb" "@$sys32\DeviceCenter.dll,-900" "String"
Apply-SystemTweak "$clsBase\DeviceInstall" "Icon" "newdev.dll,0" "String"
Apply-SystemTweak "$clsBase\DeviceInstall\command" "(Default)" "rundll32.exe newdev.dll,DeviceInternetSettingUi 2" "String"

# Remove Network Troubleshooting
Remove-SystemRegistryItem "SOFTWARE\Classes\CLSID\{26EE0668-A00A-44D7-9371-BEB064C98683}\shell\NetworkDiagnostics"

# Subgroup: Power buttons and lid
$subGroup = "4f971e89-eebd-4455-a8de-9e59040e7347"

# Setting GUIDs
$powerButtonSetting = "7648efa3-dd9c-4e3e-b566-50f929386280"
$lidCloseSetting    = "5ca83367-6e45-459f-a27b-476b1d01c936"

# Action: 3 = Shut down
$action = 3

# Apply to Power Button (AC & DC)
powercfg /setacvalueindex SCHEME_CURRENT $subGroup $powerButtonSetting $action
powercfg /setdcvalueindex SCHEME_CURRENT $subGroup $powerButtonSetting $action

# Apply to Lid Close (AC & DC)
if ($false) {
    powercfg /setacvalueindex SCHEME_CURRENT $subGroup $lidCloseSetting $action
    powercfg /setdcvalueindex SCHEME_CURRENT $subGroup $lidCloseSetting $action
}

# Save and refresh the active scheme
powercfg /setactive SCHEME_CURRENT

if( Should-Apply 'RealTimeIsUniversal' ) {
    if ($isSetup) {
        # Set Hardware Clock to UTC (RealTimeIsUniversal) for Dual-Boot compatibility
        . "$PSScriptRoot\set_real_time_utc_during_setup.ps1"
    } else {
        Apply-SystemTweak "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" "RealTimeIsUniversal" 1
    }
}

Write-Host "All cross-platform tweaks applied successfully!" -ForegroundColor Green
