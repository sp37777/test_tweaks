Write-Host "Expanding Task Manager for Windows 11..." -ForegroundColor Cyan

# Define the target path in the Default User profile
# $DefaultUserPath should be defined by your mounting script (e.g., "C:\Mount\Users\Default")
$TargetDir = "$DefaultUserPath\AppData\Local\Microsoft\Windows\TaskManager"
$TargetFile = "$TargetDir\settings.json"

if (!(Test-Path $TargetDir)) {
    New-Item -Path $TargetDir -ItemType Directory -Force
}

# This JSON forces the "Summary View" (Simple mode) to FALSE
$SettingsJson = @'
{
    "active_page": 0,
    "is_summary_view": false,
    "window_placement": {
        "top": 0,
        "left": 0,
        "bottom": 0,
        "right": 0,
        "show_state": 0
    }
}
'@

$SettingsJson | Out-File -FilePath $TargetFile -Encoding utf8 -Force