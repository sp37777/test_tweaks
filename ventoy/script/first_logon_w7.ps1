$RegPath = "HKCU:\Keyboard Layout\Preload"
    
# Remove existing entries to prevent bloat
Remove-Item $RegPath -Recurse
New-Item $RegPath -Force | Out-Null

# Set English as 1 (Default) and Ukrainian as 2
Set-ItemProperty -Path $RegPath -Name "1" -Value "00000409"
Set-ItemProperty -Path $RegPath -Name "2" -Value "00000422"

Stop-Process -Name explorer -Force
# Explorer will usually auto-restart, but to be safe:
Start-Process explorer.exe

#& control.exe "intl.cpl,,/f:`"C:\path\to\Lang.xml`""