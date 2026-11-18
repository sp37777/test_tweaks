$json = '{
  "pinnedList": [
        { "packagedAppId": "windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel" },
        { "desktopAppLink": "%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\Windows PowerShell\\Windows PowerShell.lnk" },
        { "desktopAppLink": "%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\Windows PowerShell\\Windows PowerShell (x86).lnk" },
        { "desktopAppLink": "%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\System Tools\\Command Prompt.lnk" },
        { "desktopAppLink": "%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\System Tools\\Control Panel.lnk" },
        { "desktopAppLink": "%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\System Tools\\Run.lnk" }
    ]
}';
if( [System.Environment]::OSVersion.Version.Build -lt 20000 ) {
	return;
}
$key = 'Registry::HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Start';
New-Item -Path $key -ItemType 'Directory' -ErrorAction 'SilentlyContinue';
Set-ItemProperty -LiteralPath $key -Name 'ConfigureStartPins' -Value $json -Type 'String';

Get-AppxPackage Microsoft.Windows.StartMenuExperienceHost | Reset-AppxPackage

# 2. Kill the processes that hold the Start Menu in RAM
Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue

# 3. Wipe the database file so it regenerates from the Policy
Start-Sleep -Seconds 2
$db = "$env:LocalAppData\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\start2.bin"
if (Test-Path $db) { Remove-Item $db -Force }

# 4. Restart the shell
Start-Process "explorer.exe"