# Use this to find the header in the SAME directory
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "Header.ps1")

# Windows 8.1: Remove Folders from 'This PC'
$namespace = "SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace"
$guids = @(
    "{1CF22129-2751-4030-AD05-738A24355674}", # Videos
    "{3ADD1653-EB32-4cb0-BBD7-EA4004079C31}", # Pictures
    "{A0953992-5903-4d61-8158-F1303B4BC269}", # Music
    "{A8CD357A-1531-4b74-85A1-D5A439A713F8}", # Documents
    "{374DE290-123F-4565-9164-39C4925E467B}", # Downloads
    "{B4BFDF3A-DB07-428a-BFAD-80517531650E}"  # Desktop
)

foreach ($guid in $guids) {
    Remove-SystemRegistryItem "$namespace" "$guid"
}