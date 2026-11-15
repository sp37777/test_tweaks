# 1. Brutally stop and delete Intel's main logging & tracking engines
$IntelServices = @(
    "Intel(R) Telemetry Service", 
    "EsrvServiceIntel", 
    "IntelArcControlService", 
    "Intel(R) Capability Licensing Service Interface",
    "IntelContentProtection"
)
foreach ($Service in $IntelServices) {
    if (Get-Service -Name $Service -ErrorAction SilentlyContinue) {
        Stop-Service -Name $Service -Force -Confirm:$false
        sc.exe delete $Service
        Write-Host "🔥 Successfully deleted background service: $Service" -ForegroundColor Green
    }
}

# 2. Kill automated startup tasks hidden in Windows Task Scheduler
$IntelTasks = @(
    "\Intel\Intel Telemetry 2",
    "\Intel\Intel(R) Driver & Support Assistant\IntelDSAUpdateChecker",
    "\Intel\IntelSharedDirectoryTelemetry"
)
foreach ($Task in $IntelTasks) {
    if (Get-ScheduledTask -TaskPath $Task -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskPath $Task -Confirm:$false
        Write-Host "❌ Disabled hidden tracking task: $Task" -ForegroundColor Yellow
    }
}

# 3. Prevent background tray telemetry tools from starting with Windows
$RegistryPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
)
foreach ($Path in $RegistryPaths) {
    if (Test-Path $Path) {
        Remove-ItemProperty -Path $Path -Name "IntelGraphicsTrayIcon" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $Path -Name "IntelArcControl" -ErrorAction SilentlyContinue
    }
}
Write-Host "🎉 System-level Intel cleanup routine is complete!" -ForegroundColor Cyan
