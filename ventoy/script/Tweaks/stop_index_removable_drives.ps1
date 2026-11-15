# Use this to find the header in the SAME directory
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "Header.ps1")

# DisableRemovableDriveIndexing
Apply-SystemTweak "SOFTWARE\Policies\Microsoft\Windows\Windows Search" "DisableRemovableDriveIndexing" 1

Write-Host "Success! Indexing for removable drives has been disabled." -ForegroundColor Green
Write-Host "Please restart your computer for the changes to take full effect." -ForegroundColor Yellow