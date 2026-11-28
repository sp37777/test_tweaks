# Use this to find the header in the SAME directory
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "Header.ps1")

if( Should-Apply 'DisableSmartScreen' ) {
    # --- SYSTEM-WIDE SETTINGS (HKLM) ---

    # 1. Disable System-wide SmartScreen (Explorer)
    Apply-SystemTweak "SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" "SmartScreenEnabled" "Off" "String"

    # --- USER-SPECIFIC SETTINGS (Using Default Hive Logic) ---

    # 2. Microsoft Edge SmartScreen
    Apply-UserTweak "SOFTWARE\Microsoft\Edge" "SmartScreenEnabled" 0

    # 3. AppHost Content Evaluation
    Apply-UserTweak "SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost" "EnableWebContentEvaluation" 0

    Write-Host "SmartScreen and Content Evaluation have been disabled." -ForegroundColor Yellow
}