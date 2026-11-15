# 1. Define paths
$scriptDir = "$env:SystemRoot\Setup\Scripts"
$setupComplete = Join-Path $scriptDir "SetupComplete.cmd"

# 2. Ensure the directory exists
if (!(Test-Path $scriptDir)) {
    New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
}

# 3. Create the batch file content
# This combines the registry tweak with the service reload commands
$cmdContent = @'
@echo off
:: 1. Set RealTimeIsUniversal to 1 (UTC) for both Control Sets
reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v "RealTimeIsUniversal" /t REG_DWORD /d 1 /f
reg add "HKLM\SYSTEM\ControlSet001\Control\TimeZoneInformation" /v "RealTimeIsUniversal" /t REG_DWORD /d 1 /f

:: 2. Force Windows Time service to resync and recognize the change immediately
:: We use 'net' commands for maximum compatibility with Windows 7 cmd environment
net stop w32time >nul 2>&1
w32tm /config /localclockdispersion:0
net start w32time >nul 2>&1
w32tm /resync /force >nul 2>&1

exit
'@

# 4. Write the file with ASCII encoding (Standard for .cmd files)
Set-Content -Path $setupComplete -Value $cmdContent -Encoding ASCII