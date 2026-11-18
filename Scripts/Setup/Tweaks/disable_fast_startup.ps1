# Use this to find the header in the SAME directory
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "Header.ps1")

# Disable Fast Startup
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 0