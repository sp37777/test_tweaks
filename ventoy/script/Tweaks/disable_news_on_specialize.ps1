# Use this to find the header in the SAME directory
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "Header.ps1")

# Disable News & Interests / Widgets (Policy Level - HKLM)
# This covers Pro/Enterprise and is the "cleanest" way to block the feature.

Apply-SystemTweak "SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests" 0
Apply-SystemTweak "SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" "EnableFeeds" 0

# Force Taskbar State for New Users (Default Hive - HKCU)
# This is crucial for Windows 10 Home/Pro where the taskbar might ignore policies.
# ShellFeedsState: 2 = Hidden
Apply-UserTweak "Software\Microsoft\Windows\CurrentVersion\Feeds" "ShellFeedsState" 2

Write-Host "News and interests hided."

# Existing Meet Now & Chat Tweaks (From your original script)
Apply-SystemTweak "SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "HideSCAMeetNow" 1
Apply-SystemTweak "SOFTWARE\Policies\Microsoft\Windows\Windows Chat" "ChatIcon" 3

Write-Host "Chat icon hided."