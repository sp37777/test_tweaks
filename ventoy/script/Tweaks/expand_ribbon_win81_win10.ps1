# Use this to find the header in the SAME directory
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "Header.ps1")

# Windows 8.1 & 10: Force Ribbon to stay expanded
Apply-UserTweak "Software\Microsoft\Windows\CurrentVersion\Explorer\Ribbon" "MinimizedStateTabletModeOff" 0 "DWord"
