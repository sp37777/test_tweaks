# Use this to find the header in the SAME directory
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "Header.ps1")

# Windows 7 & 8.1: Show My Computer Icon
$myCompGUID = "{20D04FE0-3AEA-1069-A2D8-08002B30309D}"

# New Start Panel (Common for both)
Apply-UserTweak "Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" $myCompGUID 0 DWord

# Classic Start Menu (Necessary for Windows 7)
if ($osVersion -eq "7") {
    Apply-UserTweak "Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu" $myCompGUID 0 DWord
}