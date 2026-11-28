# 1. Read UserName from user_choices.json (copied here by specialize_custom.ps1).
# ConvertFrom-Json is used only on PowerShell 3+: Windows 7 ships PowerShell 2.0 without it.
$choicesPath = "C:\Windows\Setup\Scripts\user_choices.json"
$defaultUser = "User"
$targetUser = $defaultUser

if (Test-Path $choicesPath) {
    try {
        $raw = [System.IO.File]::ReadAllText($choicesPath)
        $name = $null
        if ($PSVersionTable.PSVersion.Major -ge 3) {
            $parsed = $raw | ConvertFrom-Json
            if ($parsed.settings -and $parsed.settings.UserName) { $name = [string]$parsed.settings.UserName }
        } elseif ($raw -match '(?i)"UserName"\s*:\s*"((?:[^"\\]|\\.)*)"') {
            $name = [regex]::Unescape($matches[1])
        }
        if ($name) { $name = $name.Trim() }
        if ($name) {
            $targetUser = $name
        } else {
            Write-Warning "UserName is empty or missing in $choicesPath. Using the default '$defaultUser'."
        }
    } catch {
        Write-Warning "Could not read $choicesPath ($($_.Exception.Message)). Using the default '$defaultUser'."
    }
}

# 2. Check for existence (Using WMI for language independence)
net user "$targetUser" >$null 2>&1
if ($?) {
    Write-Host "User '$targetUser' already exists. Skipping creation."
} else {
    # 3. Create User with Empty Password
    net user "$targetUser" "" /add /y /expires:never /passwordchg:no 2>$null

    # Small pause to let SAM database catch up (Crucial for Win7 Setup)
    net accounts /maxpwage:unlimited
    Start-Sleep -s 2

    # 4. Universal Admin Group (SID S-1-5-32-544)
    try {
        $sid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
        $adminGroupName = $sid.Translate([System.Security.Principal.NTAccount]).Value
        if ($adminGroupName -like "*\*") { $adminGroupName = $adminGroupName.Split("\")[-1] }
        
        net localgroup "$adminGroupName" "$targetUser" /add
    } catch {
        Write-Warning "Could not resolve localized Admin group name. Defaulting to 'Administrators'."
        net localgroup "Administrators" "$targetUser" /add
    }

    # 5. Disable Password Expiration and Mandatory Change
    # wmic useraccount where "Name='$targetUser' AND LocalAccount=True" set PasswordExpires=FALSE
    net user "$targetUser" /passwordchg:no
}

# 6. Configure AutoLogon & Windows 11 Passwordless Fix
$winlogonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
$passwordlessPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device"

# Registry Settings Map
$settings = @{
    $winlogonPath = @{
        "AutoAdminLogon"    = "1"
        "DefaultUserName"   = $targetUser
        "DefaultPassword"   = ""
        "DefaultDomainName" = $env:COMPUTERNAME
    }
    $passwordlessPath = @{
        "DevicePasswordLessBuildVersion" = 0 # Fixes Win 11 AutoLogon issues
    }
}

foreach ($path in $settings.Keys) {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    foreach ($key in $settings[$path].Keys) {
        Set-ItemProperty -Path $path -Name $key -Value $settings[$path][$key] -Force
    }
}

# 7. Security Policy: Allow Blank Password Logons
# This prevents the "Account Restriction" error on some Win 10/11 builds
$secPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
Set-ItemProperty -Path $secPath -Name "LimitBlankPasswordUse" -Value 0 -Force

Write-Host "Setup for $targetUser complete. AutoLogon configured."