# Use this to find the header in the SAME directory
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "Header.ps1")

# --- Context Menu Tweaks (Windows 7, 8.1, 10 Only) ---
if ([string]$osVersion -ne "11") {

    # Determine the correct label for PowerShell based on OS version
    $psLabel = if ([string]$osVersion -eq "10") { "@shell32.dll,-37379" } else { "Open PowerShell Here" }
    
    # List of paths to apply these to (Icon itself and the Background)
    $targetPaths = @(
        "SOFTWARE\Classes\Directory\shell",
        "SOFTWARE\Classes\Directory\Background\shell"
    )

    foreach ($basePath in $targetPaths) {
        
        # 1. Command Prompt (Always Visible)
        $cmdKey = "$basePath\cmd"
        Apply-SystemTweak $cmdKey "MUIVerb" "@shell32.dll,-22022" "String"
        Apply-SystemTweak $cmdKey "Icon" "cmd.exe" "String"
        Remove-SystemRegistryItem $cmdKey "Extended"
        Remove-SystemRegistryItem $cmdKey "HideBasedOnVelocityId"
        Apply-SystemTweak "$cmdKey\command" "(Default)" 'cmd.exe /s /k pushd "%V"' "String"

        # 2. PowerShell (Always Visible)
        $psKey = "$basePath\Powershell"
        Apply-SystemTweak $psKey "MUIVerb" $psLabel "String"
        Apply-SystemTweak $psKey "Icon" "powershell.exe" "String"
        Remove-SystemRegistryItem $psKey "Extended"
        Remove-SystemRegistryItem $psKey "HideBasedOnVelocityId"
        # -LiteralPath ensures it works with folders containing brackets []
        Apply-SystemTweak "$psKey\command" "(Default)" 'powershell.exe -noexit -command Set-Location -LiteralPath ''%V''' "String"
    }

    # 3. Copy as Path (Localized, No Quotes, Micro-flash)
    # Applied to 'Allfilesystemobjects' so it works on files AND folders
    $copyPathShell = "SOFTWARE\Classes\Allfilesystemobjects\shell\windows.copypath"
    Apply-SystemTweak $copyPathShell "MUIVerb" "@shell32.dll,-30329" "String"
    Apply-SystemTweak $copyPathShell "Icon" "shell32.dll,-16763" "String"
    Remove-SystemRegistryItem $copyPathShell "Extended"
    # Overriding the default command with your quote-stripping version
    Apply-SystemTweak "$copyPathShell\command" "(Default)" 'cmd.exe /c <nul set /p="%1"|clip' "String"


    # Fix Copy To / Move To in Explorer using reg.exe to avoid Shell Deadlocks
    $ContextPaths = @(
        "HKLM\SOFTWARE\Classes\*\shellex\ContextMenuHandlers",
        "HKLM\SOFTWARE\Classes\Directory\shellex\ContextMenuHandlers"
    )
    foreach ($path in $ContextPaths) {
        $sub = "$path\Copy To"
        $mt  = "$path\Move To"
        
        # Using reg.exe bypasses the PowerShell Registry Provider's overhead/hangs
        & reg.exe add "$sub" /ve /t REG_SZ /d "{C2FBB630-2971-11D1-A18C-00C04FD75D13}" /f | Out-Null
        & reg.exe add "$mt" /ve /t REG_SZ /d "{C2FBB631-2971-11D1-A18C-00C04FD75D13}" /f | Out-Null
    }
}


