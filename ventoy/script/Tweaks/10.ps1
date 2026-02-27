# Use this to find the header in the SAME directory
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "Header.ps1")

$ControlSet = "SYSTEM\CurrentControlSet"
if (-not (Test-Path "HKLM:\$ControlSet")) {
    $ControlSet = "SYSTEM\ControlSet001"
}

if( Should-Apply 'DisableDefender' ) {
    Write-Host "Disabling Windows Defender Services for Windows 10..."
    
    # List of services that keep Defender alive
    $defenderServices = @(
        "WinDefend",   # Antivirus Service
        "WdNisSvc",    # Inspection Service
        "Sense",       # Advanced Threat Protection
        "WdBoot",      # Boot driver
        "WdFilter",    # File system filter
        "WdNisDrv"     # Network driver
    )

    foreach ($svc in $defenderServices) {
        # Use RegistryLib helper to set Start to 4 (Disabled)
        Apply-SystemTweak "$ControlSet\Services\$svc" "Start" 4 "DWord"
    }
    # Also kill the Security Health tray icon (the "Shield" in the taskbar)
    Apply-SystemTweak "SOFTWARE\Microsoft\Windows\CurrentVersion\Run" "SecurityHealth" "" "String"

    Get-ScheduledTask -TaskPath "\Microsoft\Windows\Windows Defender\*" | Disable-ScheduledTask -ErrorAction SilentlyContinue
}

if( Should-Apply 'DisableTelemetry' ) {
    Write-Host "Nuking Windows 10 Telemetry and Data Collection..."
    
    # Standard Policy keys
    Apply-SystemTweak "SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0 "DWord"
    Apply-SystemTweak "SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" "AllowTelemetry" 0 "DWord"
    
    # Disable the Telemetry service (Connected User Experiences and Telemetry)
    # This is the "DiagTrack" service.
    Apply-SystemTweak "$ControlSet\Services\DiagTrack" "Start" 4 "DWord"
    Apply-SystemTweak "$ControlSet\Services\dmwappushservice" "Start" 4 "DWord"

    # Block the "Tailored Experiences" (Microsoft's personalized ads/tips)
    Apply-SystemTweak "SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" 1 "DWord"

    # Stop the physical loggers from writing to disk
    $loggers = @("AutoLogger-Diagtrack-Listener", "ContextExplorerLog", "AppModelLog")
    foreach ($logger in $loggers) {
        Apply-SystemTweak "$ControlSet\Control\WMI\Autologger\$logger" "Start" 0 "DWord"
    }
}

if( Should-Apply 'DisableSmartScreen' ) {
    Write-Host "Disabling Windows 10 SmartScreen..."
    
    # Disable for File Explorer (Check apps and files)
    Apply-SystemTweak "SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" "SmartScreenEnabled" "Off" "String"
    
    # Disable for Microsoft Store Apps
    Apply-SystemTweak "SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost" "EnableWebContentEvaluation" 0 "DWord"
}

if( Should-Apply 'DisableSilentApps' ) {
    Write-Host "Preventing Windows 10 from auto-installing suggested apps..."
    
    $path = "SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    Apply-SystemTweak $path "SilentInstalledAppsEnabled" 0 "DWord"
    Apply-SystemTweak $path "PreInstalledAppsEnabled" 0 "DWord"
    Apply-SystemTweak $path "OemPreInstalledAppsEnabled" 0 "DWord"
    Apply-SystemTweak $path "SystemPaneSuggestionsEnabled" 0 "DWord"
}

if( Should-Apply 'DisableAppraiser' ) {
    Get-ScheduledTask -TaskName "Microsoft Compatibility Appraiser" -TaskPath "\Microsoft\Windows\Application Experience\" | Disable-ScheduledTask
}