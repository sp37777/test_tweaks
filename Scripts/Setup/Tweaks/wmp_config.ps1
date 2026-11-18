# Use this to find the header in the SAME directory
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "Header.ps1")

# --- WINDOWS MEDIA PLAYER 12 OPTIMIZATION ---
$WMPPath = "SOFTWARE\Microsoft\MediaPlayer\Preferences"
Apply-UserTweak $WMPPath "AcceptedPrivacyStatement" 1 "DWord"
Apply-UserTweak $WMPPath "AddVideosFromPicturesLibrary" 0 "DWord"
Apply-UserTweak $WMPPath "AutoAddMusicToLibrary" 0 "DWord"
Apply-UserTweak $WMPPath "DeleteRemovesFromComputer" 0 "DWord"
Apply-UserTweak $WMPPath "DisableLicenseRefresh" 1 "DWord"
Apply-UserTweak $WMPPath "FirstRun" 0 "DWord"
Apply-UserTweak $WMPPath "FlushRatingsToFiles" 0 "DWord"
Apply-UserTweak $WMPPath "HTMLViewAsk" 0 "DWord"
Apply-UserTweak $WMPPath "LibraryHasBeenRun" 1 "DWord"
Apply-UserTweak $WMPPath "MetadataRetrieval" 0 "DWord"
Apply-UserTweak $WMPPath "SilentAcquisition" 0 "DWord"
Apply-UserTweak $WMPPath "SilentDRMConfiguration" 0 "DWord"
Apply-UserTweak $WMPPath "UpgradeCheckFrequency" 2 "DWord"

Write-Host "WMP settings applied to Default User hive." -ForegroundColor Cyan