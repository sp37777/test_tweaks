<#
  apply_settings.ps1 - applies the "settings" part of user_choices.json (specialize stage, no GUI)

  Keys it understands (the same keys as in 10_choices.json):
    UserName                 text   -> local administrator account, blank password, autologon
                                       (blank = nothing is created; -SkipUserCreation = never created
                                       here, e.g. because create_user.ps1 does it; -NoAutoLogon = no autologon)
    PreventUpdateReboot      bool   -> scheduled task that keeps moving the active hours
    DisableWpbt              bool   -> DisableWpbtExecution
    PreventDeviceApps        bool   -> PreventDeviceMetadataFromNetwork
    DisableCoInstallers      bool   -> DisableCoInstallers
    PreventDeviceEncryption  bool   -> PreventDeviceEncryption
    DisableIndexing          bool   -> Windows Search service disabled
    BestPerformanceVisuals   bool   -> per-effect defaults + VisualFXSetting for new users
    DisableTransparency      bool   -> EnableTransparency=0 for new users

  Rules (same as tweaker.ps1 / removal_gui.ps1)
    * A failing step is logged and skipped. The script always exits 0 and never blocks setup.
    * No user_choices.json (the chooser was closed without saving) means nothing is applied.
    * Missing keys count as "off". Unknown keys are logged and ignored.
    * -DryRun logs what WOULD be done and changes nothing.

  Log: C:\Windows\Setup\Scripts\apply_settings.log
#>
param(
    [string]$ChoicesPath,
    [switch]$NoAutoLogon,
    [switch]$SkipUserCreation,
    [switch]$ConsumeChoices,
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$LogFile = 'C:\Windows\Setup\Scripts\apply_settings.log'

# ======================================================================
#  HELPERS (copied from tweaker.ps1)
# ======================================================================

function Write-Log {
    param([string]$Message)
    try {
        $dir = Split-Path -Parent $LogFile
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -LiteralPath $LogFile -Value ('{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Message) -Encoding UTF8
    }
    catch { }
}

function Invoke-Step {
    param([string]$Name, [scriptblock]$Do)
    if ($DryRun) { Write-Log "DRYRUN $Name"; return }
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    try {
        & $Do
        Write-Log "OK     $Name"
    }
    catch {
        Write-Log "FAILED $Name : $($_.Exception.Message)"
    }
    finally {
        $ErrorActionPreference = $prev
    }
}

function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments, [string]$Label, [switch]$AllowFail)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = (& $Exe @Arguments 2>&1 | Out-String).Trim()
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $prev
    }
    if ($code -ne 0 -and -not $AllowFail) { throw "$Label failed (exit $code): $out" }
    return $code
}

function Set-Reg {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -Type $Type -Force
}

function Invoke-DefaultHive {
    param([scriptblock]$Do)
    $alreadyLoaded = Test-Path -LiteralPath 'Registry::HKEY_USERS\DefaultUser'
    if (-not $alreadyLoaded) {
        [void](Invoke-Native -Exe 'reg.exe' -Arguments @('load', 'HKU\DefaultUser', 'C:\Users\Default\NTUSER.DAT') -Label 'load default user hive')
    }
    try { & $Do }
    finally {
        if (-not $alreadyLoaded) {
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            $code = Invoke-Native -Exe 'reg.exe' -Arguments @('unload', 'HKU\DefaultUser') -Label 'unload default user hive' -AllowFail
            if ($code -ne 0) { Write-Log "WARN   could not unload default user hive (exit $code)" }
        }
    }
}

function Add-HiveDword {
    param([string]$Key, [string]$Name, [int]$Value)
    [void](Invoke-Native -Exe 'reg.exe' -Arguments @('add', "HKU\DefaultUser\$Key", '/v', $Name, '/t', 'REG_DWORD', '/d', "$Value", '/f') -Label "reg add $Name")
}

# User creation: net.exe, admin group resolved by SID, optional autologon (as in tweaker.ps1).
# The chooser has no password field, so the account is created with a blank password.
function New-AutoLogonUser {
    param([string]$Name, [string]$Password, [bool]$AutoLogon)

    $exists = (Invoke-Native -Exe 'net.exe' -Arguments @('user', $Name) -Label 'check user' -AllowFail) -eq 0
    if ($exists) {
        Write-Log "User '$Name' already exists - creation skipped"
    }
    else {
        $netArgs = @('user', $Name)
        if ($Password -ne '') { $netArgs += $Password }
        $netArgs += @('/add', '/y', '/expires:never', '/passwordchg:no')
        [void](Invoke-Native -Exe 'net.exe' -Arguments $netArgs -Label 'create user')
        [void](Invoke-Native -Exe 'net.exe' -Arguments @('accounts', '/maxpwage:unlimited') -Label 'net accounts' -AllowFail)
        Start-Sleep -Seconds 2   # let the SAM catch up

        $adminGroup = 'Administrators'
        try {
            $sid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
            $adminGroup = $sid.Translate([System.Security.Principal.NTAccount]).Value.Split('\')[-1]
        }
        catch { Write-Log "WARN   cannot resolve admin group name, using 'Administrators'" }
        [void](Invoke-Native -Exe 'net.exe' -Arguments @('localgroup', $adminGroup, $Name, '/add') -Label 'add user to admin group')
    }

    if ($AutoLogon) {
        $wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
        Set-Reg $wl 'AutoAdminLogon' '1' 'String'
        Set-Reg $wl 'DefaultUserName' $Name 'String'
        Set-Reg $wl 'DefaultPassword' $Password 'String'
        Set-Reg $wl 'DefaultDomainName' $env:COMPUTERNAME 'String'
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device' 'DevicePasswordLessBuildVersion' 0
    }
    if ($Password -eq '') {
        # Avoids the "account restriction" error for blank-password accounts on some Win 10/11 builds
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'LimitBlankPasswordUse' 0
    }
}

# ADAPT: replace this with the lookup specialize_custom.ps1 already uses for user_choices.json.
function Find-ChoicesFile {
    $candidates = @()
    if ($PSScriptRoot) { $candidates += (Join-Path $PSScriptRoot 'user_choices.json') }
    foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        foreach ($rel in @('Scripts\Setup', 'Setup', '')) {
            $candidates += (Join-Path (Join-Path $d.Root $rel) 'user_choices.json')
        }
    }
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

# ======================================================================
#  SETTINGS ACCESS
# ======================================================================

$script:Choices = $null

function Get-Setting {
    param([string]$Key, $Default = $null)
    if (-not $script:Choices -or -not $script:Choices.settings) { return $Default }
    $p = $script:Choices.settings.PSObject.Properties[$Key]
    if ($p -and $null -ne $p.Value) { return $p.Value }
    return $Default
}

function Test-Setting {
    param([string]$Key)
    return ((Get-Setting $Key $false) -eq $true)
}

# ======================================================================
#  DATA
# ======================================================================

$KnownKeys = @(
    'UserName', 'PreventUpdateReboot', 'DisableWpbt', 'PreventDeviceApps', 'DisableCoInstallers',
    'PreventDeviceEncryption', 'DisableIndexing', 'BestPerformanceVisuals', 'DisableTransparency'
)

# Same task as the Schneegans generator ("Prevent Windows Update from rebooting your computer")
$MoveActiveHoursXml = @'
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
	<Triggers>
		<BootTrigger>
			<Repetition>
				<Interval>PT4H</Interval>
				<StopAtDurationEnd>false</StopAtDurationEnd>
			</Repetition>
			<Enabled>true</Enabled>
		</BootTrigger>
		<RegistrationTrigger>
			<Repetition>
				<Interval>PT4H</Interval>
				<StopAtDurationEnd>false</StopAtDurationEnd>
			</Repetition>
			<Enabled>true</Enabled>
		</RegistrationTrigger>
	</Triggers>
	<Principals>
		<Principal id="Author">
			<UserId>S-1-5-19</UserId>
			<RunLevel>LeastPrivilege</RunLevel>
		</Principal>
	</Principals>
	<Settings>
		<MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
		<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
		<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
		<AllowHardTerminate>true</AllowHardTerminate>
		<StartWhenAvailable>false</StartWhenAvailable>
		<RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
		<IdleSettings>
			<StopOnIdleEnd>true</StopOnIdleEnd>
			<RestartOnIdle>false</RestartOnIdle>
		</IdleSettings>
		<AllowStartOnDemand>true</AllowStartOnDemand>
		<Enabled>true</Enabled>
		<Hidden>false</Hidden>
		<RunOnlyIfIdle>false</RunOnlyIfIdle>
		<WakeToRun>false</WakeToRun>
		<ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
		<Priority>7</Priority>
	</Settings>
	<Actions Context="Author">
		<Exec>
			<Command>%windir%\System32\conhost.exe</Command>
			<Arguments>--headless %windir%\System32\WindowsPowerShell\v1.0\powershell.exe -WindowStyle Hidden -NoProfile -NonInteractive -Command "$p = @{ LiteralPath = 'Registry::HKLM\Software\Microsoft\WindowsUpdate\UX\Settings'; Type = 'DWord'; }; $h = [datetime]::Now.Hour; Set-ItemProperty @p -Name 'ActiveHoursStart' -Value (($h + 23) % 24); Set-ItemProperty @p -Name 'ActiveHoursEnd' -Value (($h + 11) % 24); Set-ItemProperty @p -Name 'SmartActiveHoursState' -Value 2;"</Arguments>
		</Exec>
	</Actions>
</Task>
'@

# Per-effect defaults, as in the Schneegans generator (FontSmoothing=0 makes text rougher; remove it if unwanted)
$VisualEffectNames = @(
    'ControlAnimations', 'AnimateMinMax', 'TaskbarAnimations', 'DWMAeroPeekEnabled', 'MenuAnimation',
    'TooltipAnimation', 'SelectionFade', 'DWMSaveThumbnailEnabled', 'CursorShadow', 'ListviewShadow',
    'ThumbnailsOrIcon', 'ListviewAlphaSelect', 'DragFullWindows', 'ComboBoxAnimation', 'FontSmoothing',
    'ListBoxSmoothScrolling', 'DropShadow'
)

# ======================================================================
#  MAIN
# ======================================================================

try {
    Write-Log "---- apply_settings started (DryRun=$([bool]$DryRun))"

    # --- read the choices ---
    if (-not $ChoicesPath) { $ChoicesPath = Find-ChoicesFile }
    if (-not $ChoicesPath -or -not (Test-Path -LiteralPath $ChoicesPath)) {
        Write-Log 'user_choices.json not found - nothing applied'
        exit 0
    }
    try {
        # -Encoding UTF8: Windows PowerShell 5.1 would otherwise read the file as ANSI
        $script:Choices = Get-Content -LiteralPath $ChoicesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Log "user_choices.json unreadable ($ChoicesPath): $($_.Exception.Message) - nothing applied"
        exit 0
    }
    if (-not $script:Choices.settings) {
        Write-Log 'No "settings" section in user_choices.json - nothing applied'
        exit 0
    }
    Write-Log "Choices: $ChoicesPath"
    $summary = @($script:Choices.settings.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ', '
    Write-Log "Settings: $summary"
    foreach ($p in $script:Choices.settings.PSObject.Properties) {
        if ($KnownKeys -notcontains $p.Name) { Write-Log "WARN   unknown setting ignored: $($p.Name)" }
    }

    # --- 1. user account ---
    $userName = ([string](Get-Setting 'UserName' '')).Trim()
    if ($SkipUserCreation) {
        Write-Log "User creation skipped (-SkipUserCreation); UserName='$userName' is left to create_user.ps1"
    }
    elseif ($userName -ne '') {
        if ($userName.Length -gt 20 -or $userName -match '["/\\\[\]:;|=,+*?<>]' -or $userName -match '[\s.]$') {
            Write-Log "FAILED User account: '$userName' is not a valid user name - skipped"
        }
        else {
            Invoke-Step "User account '$userName'" {
                New-AutoLogonUser -Name $userName -Password '' -AutoLogon (-not $NoAutoLogon)
            }
        }
    }
    else {
        Write-Log 'UserName is blank - no account created (standard OOBE)'
    }

    # --- 2. system tweaks ---
    if (Test-Setting 'PreventUpdateReboot') {
        Invoke-Step 'Prevent auto-reboot (MoveActiveHours task)' {
            Register-ScheduledTask -TaskName 'MoveActiveHours' -Xml $MoveActiveHoursXml -Force | Out-Null
        }
    }
    if (Test-Setting 'DisableWpbt') {
        Invoke-Step 'Disable WPBT execution' { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'DisableWpbtExecution' 1 }
    }
    if (Test-Setting 'PreventDeviceApps') {
        Invoke-Step 'Prevent device metadata / hardware apps download' { Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata' 'PreventDeviceMetadataFromNetwork' 1 }
    }
    if (Test-Setting 'DisableCoInstallers') {
        Invoke-Step 'Disable driver co-installers' { Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer' 'DisableCoInstallers' 1 }
    }
    if (Test-Setting 'PreventDeviceEncryption') {
        Invoke-Step 'Prevent device encryption' { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker' 'PreventDeviceEncryption' 1 }
    }
    if (Test-Setting 'DisableIndexing') {
        Invoke-Step 'Disable search indexing (WSearch)' {
            Set-Service -Name 'WSearch' -StartupType Disabled
            Stop-Service -Name 'WSearch' -Force -ErrorAction SilentlyContinue
        }
    }

    $visualFx = Test-Setting 'BestPerformanceVisuals'
    $noTransparency = Test-Setting 'DisableTransparency'
    if ($visualFx) {
        Invoke-Step 'Visual effects: per-effect defaults (HKLM)' {
            foreach ($n in $VisualEffectNames) {
                Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\$n" 'DefaultValue' 0
            }
        }
    }
    if ($visualFx -or $noTransparency) {
        Invoke-Step 'Default user hive: visual effects / transparency' {
            Invoke-DefaultHive {
                if ($visualFx) { Add-HiveDword 'Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2 }
                if ($noTransparency) { Add-HiveDword 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0 }
            }
        }
    }

    # --- 3. one-shot choices ---
    # The file must not leak into the next installation from the same flash drive.
    # Use -ConsumeChoices only in the LAST script that reads user_choices.json.
    if ($ConsumeChoices -and -not $DryRun) {
        try {
            Move-Item -LiteralPath $ChoicesPath -Destination "$ChoicesPath.used" -Force -ErrorAction Stop
            Write-Log 'user_choices.json consumed (renamed to .used)'
        }
        catch { Write-Log "Could not rename user_choices.json: $($_.Exception.Message)" }
    }
}
catch {
    Write-Log "FATAL: $($_.Exception.Message)"
}

Write-Log '---- apply_settings finished'
exit 0
