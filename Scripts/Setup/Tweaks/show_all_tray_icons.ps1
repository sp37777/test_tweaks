# Use this to find the header in the SAME directory
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "Header.ps1")

# Universal: Show all icons in system tray
Apply-UserTweak "Software\Microsoft\Windows\CurrentVersion\Explorer" "EnableAutoTray" 0 DWord
