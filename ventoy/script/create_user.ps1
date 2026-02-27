# 1. Parse the INI using Multiline Regex
$iniPath = "C:\Windows\Setup\Scripts\user_choices.ini"
$targetUser = "User2"

if (Test-Path $iniPath) {
    if ($PSVersionTable.PSVersion.Major -ge 3) {
        $IniRaw = Get-Content $iniPath -Raw
    } else {
        $IniRaw = [System.IO.File]::ReadAllText($iniPath)
    }
    if ($IniRaw -match '(?m)^\s*Username\s*=\s*(.*)') {
        $targetUser = $matches[1].Trim()
    }
}

if (-not $targetUser) {
    Write-Error "Could not parse Username from $iniPath."
    exit 1
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