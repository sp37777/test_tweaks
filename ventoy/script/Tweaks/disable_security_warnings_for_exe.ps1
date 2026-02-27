# Use this to find the header in the SAME directory
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "Header.ps1")

Write-Host "Disabling 'Open File - Security Warning' for all scripts and executables..."

# Define the policy path
$PolicyPath = "SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Associations"

# 1. Prevent Windows from saving zone information (the 'Mark of the Web')
Apply-SystemTweak "SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Attachments" "SaveZoneInformation" 1 "DWord"

# 2. Tell Windows that these file types are 'Low Risk' (No warning)
# You can add or remove extensions in this string
$LowRiskFiles = ".exe;.bat;.cmd;.ps1;.msi;.vbs;.reg"
Apply-SystemTweak $PolicyPath "LowRiskFileTypes" $LowRiskFiles "String"

# 3. Ensure the association doesn't trigger for these types
Apply-SystemTweak $PolicyPath "DefaultFileTypeRisk" 1803 "DWord"