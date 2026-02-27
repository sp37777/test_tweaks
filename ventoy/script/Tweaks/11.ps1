# Use this to find the header in the SAME directory
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "Header.ps1")

# --- SYSTEM-WIDE SETTINGS (HKLM) ---

# 1. Disable System-wide SmartScreen (Explorer)
Apply-SystemTweak "SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" "SmartScreenEnabled" "Off" "String"

# 2. Reputation-based protection policy
Apply-SystemTweak "SYSTEM\CurrentControlSet\Control\CI\Policy" "VerifiedAndReputablePolicyState" 0

# --- USER-SPECIFIC SETTINGS (Using Default Hive Logic) ---

# 3. Microsoft Edge SmartScreen
Apply-UserTweak "SOFTWARE\Microsoft\Edge" "SmartScreenEnabled" 0

# 4. AppHost Content Evaluation
Apply-UserTweak "SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost" "EnableWebContentEvaluation" 0

Write-Host "SmartScreen and Content Evaluation have been disabled." -ForegroundColor Yellow