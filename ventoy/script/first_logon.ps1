Write-Host "Setting Language List..."
try {
    # Creating language list (English + Ukrainian)
    $languages = New-WinUserLanguageList -Language "en-US"
    $languages.Add("uk-UA")
    
    # Setting it silently
    Set-WinUserLanguageList -LanguageList $languages -Force -ErrorAction SilentlyContinue
    
    # Lang panel config
    #Set-WinLanguageBarOption -LanguageBarStatus Enabled
} catch {
    Write-Warning "Could not set language list."
}

# Prevent Windows from adding keyboard layouts automatically
#$registryPath = "HKCU:\Control Panel\International\User Profile"
#if (Test-Path $registryPath) {
    #Set-ItemProperty -Path $registryPath -Name "HttpAcceptLanguageOptOut" -Value 1
#}