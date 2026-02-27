# Use this to find the header in the SAME directory
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "Header.ps1")

# --- 2. APPLY USER-SPECIFIC SETTINGS (to Mounted Hive) ---
# Removals
Remove-UserRegistryItem "Software\Microsoft\Internet Explorer\TypedURLs"
Remove-UserRegistryItem "Software\Microsoft\Internet Explorer\SearchScopes"

# IE General
Apply-UserTweak "Software\Microsoft\Internet Explorer\Main" "DisableFirstRunCustomize" 1 "DWord"
Apply-UserTweak "Software\Microsoft\Internet Explorer\Main" "IE9TourNoShow" 1 "DWord"
Apply-UserTweak "Software\Microsoft\Internet Explorer\Main" "Start Page" "about:tabs" "String"
Apply-UserTweak "Software\Microsoft\Internet Explorer\Main" "NotifyDownloadComplete" "yes" "String"
Apply-UserTweak "Software\Microsoft\Internet Explorer\Main" "SmoothScroll" 0 "DWord"
Apply-UserTweak "Software\Microsoft\Internet Explorer\Main" "Check_Associations" "no" "String"
Apply-UserTweak "Software\Microsoft\Internet Explorer\Main" "Disable Script Debugger" "yes" "String"

# Security & Search
Apply-UserTweak "Software\Microsoft\Internet Explorer\PhishingFilter" "EnabledV9" 0 "DWord"
Apply-UserTweak "Software\Microsoft\Internet Explorer\SearchScopes" "DefaultScope" "{7C48FA5A-0A98-4590-A75C-0C82317A77DF}" "String"

$googlePath = "Software\Microsoft\Internet Explorer\SearchScopes\{7C48FA5A-0A98-4590-A75C-0C82317A77DF}"
Apply-UserTweak $googlePath "DisplayName" "Google" "String"
Apply-UserTweak $googlePath "URL" "http://www.google.com/search?hl=ru&q={searchTerms}" "String"

# UI & Downloads
Apply-UserTweak "Software\Microsoft\Internet Explorer\Suggested Sites" "Enabled" 0 "DWord"
Apply-UserTweak "Software\Microsoft\Internet Explorer\LinksBar" "Enabled" 0 "DWord"
Apply-UserTweak "Software\Microsoft\Internet Explorer\Download" "CheckExeSignatures" "no" "String"
Apply-UserTweak "Software\Microsoft\Internet Explorer\Download" "RunInvalidSignatures" 1 "DWord"
Apply-UserTweak "Software\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_LOCALMACHINE_LOCKDOWN\Settings" "LOCALMACHINE_CD_UNLOCK" 1 "DWord"

# --- 3. APPLY MACHINE-WIDE SETTINGS (HKLM) ---
Apply-SystemTweak "SOFTWARE\Microsoft\Internet Explorer\Geolocation" "BlockAllWebsites" 1 "DWord"
Apply-SystemTweak "SOFTWARE\Policies\Microsoft\Internet Explorer\Security" "DisableSecuritySettingsCheck" 1 "DWord"
Apply-SystemTweak "SOFTWARE\Microsoft\Internet Explorer\TabbedBrowsing" "ThumbnailBehavior" 0 "DWord"
Apply-SystemTweak "SOFTWARE\Microsoft\Internet Explorer\ContinuousBrowsing" "Enabled" 1 "DWord"
Apply-SystemTweak "Software\Policies\Microsoft\Internet Explorer\Main" "DisableFirstRunCustomize" 1 "DWord"
Apply-SystemTweak "Software\Policies\Microsoft\Internet Explorer\Main" "RunOnceHasShown" 1 "DWord"
Apply-SystemTweak "Software\Policies\Microsoft\Internet Explorer\Main" "RunOnceComplete" 1 "DWord"
Apply-SystemTweak "SOFTWARE\Microsoft\MSN\Toolbar" "version" "" "String"

Write-Host "Windows Installation Registry Adjustments Applied Successfully."