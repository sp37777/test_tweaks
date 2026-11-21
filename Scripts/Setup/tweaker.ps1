<#
  tweaker.ps1 - post-install tweaker for the specialize stage (or any elevated session)

  Rules this script follows:
    * A failing step is logged and skipped. It never stops Windows setup; the script always exits 0.
    * The GUI closes itself after -GuiTimeoutSeconds if nobody clicks Apply (nothing is applied then).
    * Components are scanned in a background runspace; the list fills in as each area finishes.
      Nothing is locked while scanning. If Apply is clicked early, removal waits for the scan.
    * -DryRun shows the GUI and logs what WOULD be done, but changes nothing (handy on a live system).

  Log: C:\Windows\Setup\Scripts\tweaker.log
#>
param(
    [switch]$DryRun,
    [int]$GuiTimeoutSeconds = 600,
    [int]$ScanWaitTimeoutSeconds = 600
)

$ErrorActionPreference = 'Continue'
$LogFile = 'C:\Windows\Setup\Scripts\tweaker.log'

# ======================================================================
#  HELPERS
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

# Runs one action. Any error is logged and swallowed. In -DryRun the action is not executed.
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

# Runs a native exe and returns its exit code. Throws on non-zero unless -AllowFail.
# The label is used in the error text, so arguments (e.g. a password) never end up in the log.
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

# Loads C:\Users\Default\NTUSER.DAT as HKU\DefaultUser, runs the block, unloads it again.
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

function Invoke-RegAdd {
    param([string[]]$RegArgs)
    [void](Invoke-Native -Exe 'reg.exe' -Arguments (@('add') + $RegArgs) -Label "reg add $($RegArgs[0])")
}

# User creation: same approach as create_user.ps1 (net.exe, admin group resolved by SID, autologon).
# The user name and password come from the GUI instead of user_choices.ini.
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

# ======================================================================
#  DATA
# ======================================================================

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

# Master list of components. IDs come from the Schneegans generator's own scripts
# (RemovePackage.ps1 / RemoveCapability.ps1 / RemoveFeature.ps1).
# Left out on purpose: Microsoft Store, Store Purchase App and the "MediaPlayback" feature.
#
# Optional keys that carry the companion tweaks the generator applies together with a removal:
#   Spec = scriptblock run as SYSTEM, Hive = scriptblock run while HKU\DefaultUser is loaded,
#   Once = PowerShell text that runs at the first logon of every new user.
# Which companion belongs to which entry is inferred from the generator's output; verify by
# generating the XML with and without the option and diffing the scripts.
$AllAppsData = @(
    @{ Name = "3D Viewer"; Checked = $true; Appx = @("Microsoft.Microsoft3DViewer"); Cap = @(); Feat = @() },
    @{ Name = "Bing News"; Checked = $true; Appx = @("Microsoft.BingNews"); Cap = @(); Feat = @() },
    @{ Name = "Bing Search"; Checked = $true; Appx = @("Microsoft.BingSearch"); Cap = @(); Feat = @() },
    @{ Name = "Bing Weather"; Checked = $true; Appx = @("Microsoft.BingWeather"); Cap = @(); Feat = @() },
    @{ Name = "Calculator"; Checked = $false; Appx = @("Microsoft.WindowsCalculator"); Cap = @(); Feat = @() },
    @{ Name = "Camera"; Checked = $true; Appx = @("Microsoft.WindowsCamera"); Cap = @(); Feat = @() },
    @{ Name = "Clipchamp"; Checked = $true; Appx = @("Clipchamp.Clipchamp"); Cap = @(); Feat = @() },
    @{ Name = "Clock"; Checked = $true; Appx = @("Microsoft.WindowsAlarms"); Cap = @(); Feat = @() },
    @{ Name = "Copilot"; Checked = $true; Appx = @("Microsoft.Copilot"); Cap = @(); Feat = @()
        Hive = { Add-HiveDword 'Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1 }
        Once = "Get-AppxPackage -Name 'Microsoft.Windows.Ai.Copilot.Provider' | Remove-AppxPackage"
    },
    @{ Name = "Cortana"; Checked = $true; Appx = @("Microsoft.549981C3F5F10"); Cap = @(); Feat = @() },
    @{ Name = "Dev Home"; Checked = $true; Appx = @("Microsoft.Windows.DevHome"); Cap = @(); Feat = @()
        Spec = { Remove-Item -LiteralPath 'HKLM:\Software\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate' -Recurse -Force -ErrorAction SilentlyContinue }
    },
    @{ Name = "Facial recognition (Windows Hello)"; Checked = $true; Appx = @(); Cap = @("Hello.Face.18967", "Hello.Face.Migration.18967", "Hello.Face.20134"); Feat = @() },
    @{ Name = "Family"; Checked = $true; Appx = @("MicrosoftCorporationII.MicrosoftFamily"); Cap = @(); Feat = @() },
    @{ Name = "Feedback Hub"; Checked = $true; Appx = @("Microsoft.WindowsFeedbackHub"); Cap = @(); Feat = @() },
    @{ Name = "Game Assist (Edge)"; Checked = $true; Appx = @("Microsoft.Edge.GameAssist"); Cap = @(); Feat = @() },
    @{ Name = "Get Help"; Checked = $true; Appx = @("Microsoft.GetHelp"); Cap = @(); Feat = @() },
    @{ Name = "Handwriting (all languages)"; Checked = $true; Appx = @(); Cap = @("Language.Handwriting"); Feat = @() },
    @{ Name = "Internet Explorer mode"; Checked = $true; Appx = @(); Cap = @("Browser.InternetExplorer"); Feat = @() },
    @{ Name = "Mail and Calendar"; Checked = $true; Appx = @("microsoft.windowscommunicationsapps"); Cap = @(); Feat = @() },
    @{ Name = "Maps"; Checked = $true; Appx = @("Microsoft.WindowsMaps"); Cap = @(); Feat = @() },
    @{ Name = "Math Input Panel"; Checked = $true; Appx = @(); Cap = @("MathRecognizer"); Feat = @() },
    @{ Name = "Mixed Reality Portal"; Checked = $true; Appx = @("Microsoft.MixedReality.Portal"); Cap = @(); Feat = @() },
    @{ Name = "Movies & TV"; Checked = $true; Appx = @("Microsoft.ZuneVideo"); Cap = @(); Feat = @() },
    @{ Name = "Notepad (modern)"; Checked = $false; Appx = @("Microsoft.WindowsNotepad"); Cap = @(); Feat = @()
        # Assumed to belong to the Notepad removal in the generator: keeps "New > Text Document" working
        Spec = {
            Invoke-RegAdd @('HKCR\.txt\ShellNew', '/v', 'ItemName', '/t', 'REG_EXPAND_SZ', '/d', '@C:\Windows\system32\notepad.exe,-470', '/f')
            Invoke-RegAdd @('HKCR\.txt\ShellNew', '/v', 'NullFile', '/t', 'REG_SZ', '/f')
            Invoke-RegAdd @('HKCR\txtfilelegacy', '/v', 'FriendlyTypeName', '/t', 'REG_EXPAND_SZ', '/d', '@C:\Windows\system32\notepad.exe,-469', '/f')
            Invoke-RegAdd @('HKCR\txtfilelegacy', '/ve', '/t', 'REG_SZ', '/d', 'Text Document', '/f')
        }
    },
    @{ Name = "Office hub (Microsoft 365)"; Checked = $true; Appx = @("Microsoft.MicrosoftOfficeHub"); Cap = @(); Feat = @() },
    @{ Name = "OneDrive"; Checked = $true; Appx = @(); Cap = @(); Feat = @(); Custom = "OneDrive"
        Spec = {
            $files = @(
                'C:\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk',
                'C:\Windows\System32\OneDriveSetup.exe',
                'C:\Windows\SysWOW64\OneDriveSetup.exe'
            )
            foreach ($f in $files) {
                if (Test-Path -LiteralPath $f) {
                    try { Remove-Item -LiteralPath $f -Force }
                    catch { Write-Log "FAILED OneDrive: delete $f : $($_.Exception.Message)" }
                }
            }
        }
        # exit code 1 only means the value was not there
        Hive = { [void](Invoke-Native -Exe 'reg.exe' -Arguments @('delete', 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Run', '/v', 'OneDriveSetup', '/f') -Label 'reg delete OneDriveSetup' -AllowFail) }
    },
    @{ Name = "OneNote"; Checked = $true; Appx = @("Microsoft.Office.OneNote"); Cap = @(); Feat = @() },
    @{ Name = "OneSync"; Checked = $true; Appx = @(); Cap = @("OneCoreUAP.OneSync"); Feat = @() },
    @{ Name = "OpenSSH Client"; Checked = $true; Appx = @(); Cap = @("OpenSSH.Client"); Feat = @() },
    @{ Name = "Outlook for Windows"; Checked = $true; Appx = @("Microsoft.OutlookForWindows"); Cap = @(); Feat = @()
        Spec = { Remove-Item -LiteralPath 'HKLM:\Software\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' -Recurse -Force -ErrorAction SilentlyContinue }
    },
    @{ Name = "Paint"; Checked = $false; Appx = @("Microsoft.Paint", "Microsoft.MSPaint"); Cap = @("Microsoft.Windows.MSPaint"); Feat = @() },
    @{ Name = "People"; Checked = $true; Appx = @("Microsoft.People"); Cap = @(); Feat = @() },
    @{ Name = "Photos"; Checked = $false; Appx = @("Microsoft.Windows.Photos"); Cap = @(); Feat = @() },
    @{ Name = "Power Automate"; Checked = $true; Appx = @("Microsoft.PowerAutomateDesktop"); Cap = @(); Feat = @() },
    @{ Name = "PowerShell 2.0"; Checked = $true; Appx = @(); Cap = @(); Feat = @("MicrosoftWindowsPowerShellV2Root") },
    @{ Name = "PowerShell ISE"; Checked = $true; Appx = @(); Cap = @("Microsoft.Windows.PowerShell.ISE"); Feat = @() },
    @{ Name = "Quick Assist"; Checked = $true; Appx = @("MicrosoftCorporationII.QuickAssist"); Cap = @("App.Support.QuickAssist"); Feat = @() },
    @{ Name = "Recall"; Checked = $true; Appx = @(); Cap = @(); Feat = @("Recall") },
    @{ Name = "Remote Desktop Client"; Checked = $true; Appx = @(); Cap = @(); Feat = @("Microsoft-RemoteDesktopConnection") },
    @{ Name = "Skype"; Checked = $true; Appx = @("Microsoft.SkypeApp"); Cap = @(); Feat = @() },
    @{ Name = "Snipping Tool"; Checked = $false; Appx = @("Microsoft.ScreenSketch"); Cap = @("Microsoft.Windows.SnippingTool"); Feat = @("Microsoft-SnippingTool") },
    @{ Name = "Solitaire Collection"; Checked = $true; Appx = @("Microsoft.MicrosoftSolitaireCollection"); Cap = @(); Feat = @() },
    @{ Name = "Speech (all languages)"; Checked = $true; Appx = @(); Cap = @("Language.Speech", "Language.TextToSpeech"); Feat = @() },
    @{ Name = "Steps Recorder"; Checked = $false; Appx = @(); Cap = @("App.StepsRecorder"); Feat = @() },
    @{ Name = "Sticky Notes"; Checked = $false; Appx = @("Microsoft.MicrosoftStickyNotes"); Cap = @(); Feat = @() },
    @{ Name = "Teams"; Checked = $true; Appx = @("MicrosoftTeams", "MSTeams"); Cap = @(); Feat = @()
        # Assumed to belong to the Teams removal in the generator
        Spec = { Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Communications' 'ConfigureChatAutoInstall' 0 }
    },
    @{ Name = "Tips (Get Started)"; Checked = $true; Appx = @("Microsoft.Getstarted"); Cap = @(); Feat = @() },
    @{ Name = "To Do"; Checked = $false; Appx = @("Microsoft.Todos"); Cap = @(); Feat = @() },
    @{ Name = "Voice Recorder"; Checked = $false; Appx = @("Microsoft.WindowsSoundRecorder"); Cap = @(); Feat = @() },
    @{ Name = "Wallet"; Checked = $true; Appx = @("Microsoft.Wallet"); Cap = @(); Feat = @() },
    @{ Name = "Windows Media Player (classic)"; Checked = $false; Appx = @(); Cap = @("Media.WindowsMediaPlayer"); Feat = @() },
    @{ Name = "Windows Media Player (modern)"; Checked = $true; Appx = @("Microsoft.ZuneMusic"); Cap = @(); Feat = @() },
    @{ Name = "Windows Terminal"; Checked = $false; Appx = @("Microsoft.WindowsTerminal"); Cap = @(); Feat = @() },
    @{ Name = "WordPad"; Checked = $false; Appx = @(); Cap = @("Microsoft.Windows.WordPad"); Feat = @() },
    @{ Name = "Xbox and Game Bar"; Checked = $true; Cap = @(); Feat = @()
        Appx = @("Microsoft.Xbox.TCUI", "Microsoft.XboxApp", "Microsoft.XboxGameOverlay", "Microsoft.XboxGamingOverlay", "Microsoft.XboxIdentityProvider", "Microsoft.XboxSpeechToTextOverlay", "Microsoft.GamingApp")
        # Assumed to belong to the Xbox removal in the generator
        Hive = { Add-HiveDword 'Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0 }
    },
    @{ Name = "Your Phone / Phone Link"; Checked = $true; Appx = @("Microsoft.YourPhone"); Cap = @(); Feat = @() }
)

# ======================================================================
#  STATE
# ======================================================================

$script:scan = [hashtable]::Synchronized(@{})   # filled by the background runspace: Appx, Feats, Caps, *Error, Done
$script:areaShown = @{ Appx = $false; Feats = $false; Caps = $false }
$script:listed = @{}
$script:Applying = $false
$script:RemovalPending = $false
$script:ApplyRequestedAt = $null

# ======================================================================
#  MAIN (everything GUI-related is inside try so that nothing can abort setup)
# ======================================================================

try {
    Write-Log "---- tweaker started (DryRun=$([bool]$DryRun), UserInteractive=$([Environment]::UserInteractive), SessionId=$((Get-Process -Id $PID).SessionId))"

    if (-not [Environment]::UserInteractive) {
        Write-Log 'Session is not interactive - the GUI cannot be shown. Nothing applied.'
        exit 0
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    # An unhandled exception in an event handler must never pop up a dialog that blocks setup
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
    [System.Windows.Forms.Application]::add_ThreadException({ param($s, $e) Write-Log "UI exception: $($e.Exception.Message)" })

    # --- MAIN WINDOW ---
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Windows Post-Install Tweaker (closes by itself after $([math]::Round($GuiTimeoutSeconds / 60, 1)) min without Apply)"
    if ($DryRun) { $form.Text += ' [DRY RUN]' }
    $form.Size = New-Object System.Drawing.Size(760, 560)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.TopMost = $true
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

    # --- LEFT COLUMN: USER ACCOUNT ---
    $grpUser = New-Object System.Windows.Forms.GroupBox
    $grpUser.Text = "1. User Account (before creation)"
    $grpUser.Location = New-Object System.Drawing.Point(15, 15)
    $grpUser.Size = New-Object System.Drawing.Size(340, 145)
    $form.Controls.Add($grpUser)

    $lblUser = New-Object System.Windows.Forms.Label
    $lblUser.Text = "Username (leave blank for standard OOBE):"
    $lblUser.Location = New-Object System.Drawing.Point(12, 25)
    $lblUser.AutoSize = $true
    $grpUser.Controls.Add($lblUser)

    $txtUser = New-Object System.Windows.Forms.TextBox
    $txtUser.Text = "User"
    $txtUser.Location = New-Object System.Drawing.Point(12, 48)
    $txtUser.Size = New-Object System.Drawing.Size(310, 25)
    $grpUser.Controls.Add($txtUser)

    $lblPass = New-Object System.Windows.Forms.Label
    $lblPass.Text = "Password (optional):"
    $lblPass.Location = New-Object System.Drawing.Point(12, 80)
    $lblPass.AutoSize = $true
    $grpUser.Controls.Add($lblPass)

    $txtPass = New-Object System.Windows.Forms.TextBox
    $txtPass.Location = New-Object System.Drawing.Point(165, 77)
    $txtPass.Size = New-Object System.Drawing.Size(157, 25)
    $txtPass.UseSystemPasswordChar = $true
    $grpUser.Controls.Add($txtPass)

    $chkAutoLogon = New-Object System.Windows.Forms.CheckBox
    $chkAutoLogon.Text = "Auto-logon (password stored in plain text)"
    $chkAutoLogon.Checked = $true
    $chkAutoLogon.Location = New-Object System.Drawing.Point(12, 110)
    $chkAutoLogon.Size = New-Object System.Drawing.Size(315, 24)
    $grpUser.Controls.Add($chkAutoLogon)

    # --- LEFT COLUMN: TWEAKS ---
    $grpTweaks = New-Object System.Windows.Forms.GroupBox
    $grpTweaks.Text = "2. System Tweaks & Optimization"
    $grpTweaks.Location = New-Object System.Drawing.Point(15, 170)
    $grpTweaks.Size = New-Object System.Drawing.Size(340, 290)
    $form.Controls.Add($grpTweaks)

    function New-TweakCheckBox {
        param([string]$Text, [bool]$Checked, [int]$Y)
        $c = New-Object System.Windows.Forms.CheckBox
        $c.Text = $Text
        $c.Checked = $Checked
        $c.Location = New-Object System.Drawing.Point(12, $Y)
        $c.Size = New-Object System.Drawing.Size(315, 24)
        $grpTweaks.Controls.Add($c)
        return $c
    }

    $chkNoReboot = New-TweakCheckBox "Prevent Windows Update auto-reboot" $false 28
    $chkWPBT = New-TweakCheckBox "Disable WPBT execution (BIOS software injection)" $true 58
    $chkNoDevApps = New-TweakCheckBox "Prevent hardware device apps auto-install" $true 88
    $chkNoCoInst = New-TweakCheckBox "Disable driver co-installers (may affect old drivers)" $false 118
    $chkNoEncrypt = New-TweakCheckBox "[Low-end PC] Prevent device encryption" $false 160
    $chkNoIndex = New-TweakCheckBox "[Low-end PC] Disable file search indexing" $false 190
    $chkVisualFX = New-TweakCheckBox "[Low-end PC] Best performance visual effects" $false 220
    $chkNoTransp = New-TweakCheckBox "[Low-end PC] Disable transparency effects" $false 250

    # --- RIGHT COLUMN: COMPONENTS TO REMOVE ---
    $grpApps = New-Object System.Windows.Forms.GroupBox
    $grpApps.Text = "3. Components to remove - scanning..."
    $grpApps.Location = New-Object System.Drawing.Point(370, 15)
    $grpApps.Size = New-Object System.Drawing.Size(360, 445)
    $form.Controls.Add($grpApps)

    $lv = New-Object System.Windows.Forms.ListView
    $lv.Location = New-Object System.Drawing.Point(12, 25)
    $lv.Size = New-Object System.Drawing.Size(335, 340)
    $lv.View = 'Details'
    $lv.CheckBoxes = $true
    $lv.FullRowSelect = $true
    $lv.HideSelection = $false
    $lv.HeaderStyle = 'None'
    [void]$lv.Columns.Add('Component', 295)
    $grpApps.Controls.Add($lv)

    $lblScan = New-Object System.Windows.Forms.Label
    $lblScan.Text = "Scan: appx ... | features ... | capabilities ..."
    $lblScan.Location = New-Object System.Drawing.Point(12, 372)
    $lblScan.Size = New-Object System.Drawing.Size(335, 20)
    $grpApps.Controls.Add($lblScan)

    $btnAll = New-Object System.Windows.Forms.Button
    $btnAll.Text = "Select All"
    $btnAll.Location = New-Object System.Drawing.Point(12, 402)
    $btnAll.Size = New-Object System.Drawing.Size(110, 28)
    $btnAll.Add_Click({ foreach ($li in $lv.Items) { $li.Checked = $true } })
    $grpApps.Controls.Add($btnAll)

    $btnNone = New-Object System.Windows.Forms.Button
    $btnNone.Text = "Select None"
    $btnNone.Location = New-Object System.Drawing.Point(130, 402)
    $btnNone.Size = New-Object System.Drawing.Size(110, 28)
    $btnNone.Add_Click({ foreach ($li in $lv.Items) { $li.Checked = $false } })
    $grpApps.Controls.Add($btnNone)

    # --- APPLY BUTTON ---
    $btnApply = New-Object System.Windows.Forms.Button
    $btnApply.Text = "Apply && Continue Setup"
    $btnApply.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnApply.Location = New-Object System.Drawing.Point(15, 470)
    $btnApply.Size = New-Object System.Drawing.Size(715, 38)
    $btnApply.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnApply.ForeColor = [System.Drawing.Color]::White
    $btnApply.FlatStyle = "Flat"
    $form.Controls.Add($btnApply)

    # ==================================================================
    #  COMPONENT LIST LOGIC
    # ==================================================================

    # Which installed objects belong to a catalog entry (uses only the areas scanned so far)
    function Get-CatalogMatches {
        param($App)
        $appx = @(); $caps = @(); $feats = @()
        if ($script:scan.ContainsKey('Appx')) { $appx = @($script:scan['Appx'] | Where-Object { $App.Appx -contains $_.DisplayName }) }
        if ($script:scan.ContainsKey('Caps')) { $caps = @($script:scan['Caps'] | Where-Object { $App.Cap -contains ($_.Name -split '~')[0] }) }
        if ($script:scan.ContainsKey('Feats')) { $feats = @($script:scan['Feats'] | Where-Object { $App.Feat -contains $_.FeatureName }) }
        return [pscustomobject]@{ Appx = $appx; Caps = $caps; Feats = $feats }
    }

    function Add-ListItem {
        param($App)
        if ($script:listed.ContainsKey($App.Name)) { return }
        $li = New-Object System.Windows.Forms.ListViewItem($App.Name)
        $li.Tag = $App
        $li.Checked = [bool]$App.Checked
        [void]$lv.Items.Add($li)
        $script:listed[$App.Name] = $true
    }

    function Update-ComponentList {
        foreach ($area in 'Appx', 'Feats', 'Caps') {
            if ($script:scan.ContainsKey($area) -and -not $script:areaShown[$area]) {
                $script:areaShown[$area] = $true
                if ($script:scan.ContainsKey("${area}Error")) {
                    Write-Log "Scan $area FAILED: $($script:scan["${area}Error"])"
                }
                else {
                    Write-Log "Scan ${area}: $(@($script:scan[$area]).Count) items"
                }
                # Items discovered after Apply was clicked are not offered (the user never saw them)
                if (-not $script:Applying) {
                    foreach ($app in $AllAppsData) {
                        if ($script:listed.ContainsKey($app.Name)) { continue }
                        $m = Get-CatalogMatches $app
                        if (($m.Appx.Count + $m.Caps.Count + $m.Feats.Count) -gt 0) { Add-ListItem $app }
                    }
                }
            }
        }
        $st = { param($k) if ($script:scan.ContainsKey($k)) { 'done' } else { '...' } }
        $lblScan.Text = "Scan: appx $(& $st 'Appx') | features $(& $st 'Feats') | capabilities $(& $st 'Caps')"
        if ($script:scan.ContainsKey('Done')) {
            $grpApps.Text = "3. Components to remove ($($lv.Items.Count) found)"
        }
        else {
            $grpApps.Text = "3. Components to remove - scanning ($($lv.Items.Count) so far)..."
        }
    }

    # Writes the "first logon of every new user" snippets to their own file and registers it in the
    # default user's RunOnce. The tweaks\ folder and the TweakerUserOnce value name cannot collide
    # with the generator's own files (Specialize.ps1, DefaultUser.ps1, UserOnce.ps1, ...).
    function Write-UserOnce {
        param($Apps)
        $dir = 'C:\Windows\Setup\Scripts\tweaks'
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('# Generated by tweaker.ps1 - runs once at the first logon of every new user')
        foreach ($a in $Apps) {
            [void]$sb.AppendLine('try {')
            [void]$sb.AppendLine([string]$a.Once)
            [void]$sb.AppendLine('} catch { }')
        }
        Set-Content -LiteralPath (Join-Path $dir 'useronce.ps1') -Value $sb.ToString() -Encoding UTF8
        Invoke-DefaultHive {
            [void](Invoke-Native -Exe 'reg.exe' -Arguments @('add', 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\RunOnce', '/v', 'TweakerUserOnce', '/t', 'REG_SZ', '/d', 'powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File C:\Windows\Setup\Scripts\tweaks\useronce.ps1', '/f') -Label 'register RunOnce')
        }
    }

    # Companion tweaks of the removed entries: system context, default-user hive, first logon of each user
    function Invoke-Companions {
        param($Apps)
        foreach ($app in $Apps) {
            if ($app.Spec) { Invoke-Step "Companion tweaks (system): $($app.Name)" $app.Spec }
        }
        $hiveApps = @($Apps | Where-Object { $_.Hive })
        if ($hiveApps.Count -gt 0) {
            Invoke-Step 'Companion tweaks (default user hive)' {
                Invoke-DefaultHive {
                    foreach ($a in $hiveApps) {
                        try { & $a.Hive; Write-Log "OK     hive tweak: $($a.Name)" }
                        catch { Write-Log "FAILED hive tweak: $($a.Name) : $($_.Exception.Message)" }
                    }
                }
            }
        }
        $onceApps = @($Apps | Where-Object { $_.Once })
        if ($onceApps.Count -gt 0) {
            Invoke-Step 'Companion tweaks (first logon of each new user)' { Write-UserOnce $onceApps }
        }
    }

    function Remove-SelectedComponents {
        $selected = @($lv.Items | Where-Object { $_.Checked })
        $apps = @()
        $i = 0
        foreach ($li in $selected) {
            $i++
            $app = $li.Tag
            $apps += $app
            $btnApply.Text = "Removing $($app.Name) ($i/$($selected.Count))..."
            [System.Windows.Forms.Application]::DoEvents()
            $m = Get-CatalogMatches $app
            foreach ($p in $m.Appx) {
                Invoke-Step "Remove appx $($p.DisplayName)" { Remove-AppxProvisionedPackage -Online -AllUsers -PackageName $p.PackageName | Out-Null }
            }
            foreach ($c in $m.Caps) {
                Invoke-Step "Remove capability $($c.Name)" { Remove-WindowsCapability -Online -Name $c.Name | Out-Null }
            }
            foreach ($f in $m.Feats) {
                Invoke-Step "Remove feature $($f.FeatureName)" { Disable-WindowsOptionalFeature -Online -FeatureName $f.FeatureName -Remove -NoRestart | Out-Null }
            }
        }
        # Registry/files are touched only after all DISM work, so the default hive is never loaded during DISM
        $btnApply.Text = 'Applying companion tweaks...'
        [System.Windows.Forms.Application]::DoEvents()
        Invoke-Companions $apps
    }

    # Runs the removal stage once the scan has finished (or the wait timed out), then closes the form
    function Complete-ApplyIfReady {
        if (-not $script:RemovalPending) { return }
        $waited = ((Get-Date) - $script:ApplyRequestedAt).TotalSeconds
        if (-not $script:scan.ContainsKey('Done') -and $waited -lt $ScanWaitTimeoutSeconds) {
            $btnApply.Text = 'Waiting for the component scan to finish...'
            return
        }
        $script:RemovalPending = $false
        $timer.Stop()
        if (-not $script:scan.ContainsKey('Done')) {
            Write-Log "Scan did not finish within $ScanWaitTimeoutSeconds s - component removal skipped"
        }
        else {
            Remove-SelectedComponents
        }
        Write-Log 'Apply finished'
        $form.Close()
    }

    # ==================================================================
    #  APPLY
    # ==================================================================

    function Invoke-Apply {
        $userName = $txtUser.Text.Trim()
        $password = $txtPass.Text

        # Input problems the person can fix: keep the window open
        if ($userName -ne '') {
            if ($userName.Length -gt 20 -or $userName -match '["/\\\[\]:;|=,+*?<>]' -or $userName -match '[\s.]$') {
                [void][System.Windows.Forms.MessageBox]::Show('Invalid user name (max 20 characters, no " / \ [ ] : ; | = , + * ? < > and no trailing dot or space).', 'Tweaker', 'OK', 'Warning')
                return
            }
            if ($password.Contains('"')) {
                [void][System.Windows.Forms.MessageBox]::Show('The password must not contain double quotes.', 'Tweaker', 'OK', 'Warning')
                return
            }
        }

        $script:Applying = $true
        $deadline.Stop()
        foreach ($c in @($grpUser, $grpTweaks, $lv, $btnAll, $btnNone, $btnApply)) { $c.Enabled = $false }
        $btnApply.Text = 'Applying settings...'
        $form.Refresh()
        Write-Log "Apply clicked (user='$userName', autologon=$($chkAutoLogon.Checked))"

        # 1. User account
        if ($userName -ne '') {
            Invoke-Step "User account '$userName'" {
                New-AutoLogonUser -Name $userName -Password $password -AutoLogon $chkAutoLogon.Checked
            }
        }

        # 2. System tweaks
        if ($chkNoReboot.Checked) {
            Invoke-Step 'Prevent auto-reboot (MoveActiveHours task)' {
                Register-ScheduledTask -TaskName 'MoveActiveHours' -Xml $MoveActiveHoursXml -Force | Out-Null
            }
        }
        if ($chkWPBT.Checked) {
            Invoke-Step 'Disable WPBT execution' { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'DisableWpbtExecution' 1 }
        }
        if ($chkNoDevApps.Checked) {
            Invoke-Step 'Prevent device metadata / hardware apps download' { Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata' 'PreventDeviceMetadataFromNetwork' 1 }
        }
        if ($chkNoCoInst.Checked) {
            Invoke-Step 'Disable driver co-installers' { Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer' 'DisableCoInstallers' 1 }
        }
        if ($chkNoEncrypt.Checked) {
            Invoke-Step 'Prevent device encryption' { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker' 'PreventDeviceEncryption' 1 }
        }
        if ($chkNoIndex.Checked) {
            Invoke-Step 'Disable search indexing (WSearch)' {
                Set-Service -Name 'WSearch' -StartupType Disabled
                Stop-Service -Name 'WSearch' -Force -ErrorAction SilentlyContinue
            }
        }
        if ($chkVisualFX.Checked) {
            Invoke-Step 'Visual effects: per-effect defaults (HKLM)' {
                foreach ($n in $VisualEffectNames) {
                    Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\$n" 'DefaultValue' 0
                }
            }
        }
        if ($chkVisualFX.Checked -or $chkNoTransp.Checked) {
            Invoke-Step 'Default user hive: visual effects / transparency' {
                Invoke-DefaultHive {
                    if ($chkVisualFX.Checked) { Add-HiveDword 'Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2 }
                    if ($chkNoTransp.Checked) { Add-HiveDword 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0 }
                }
            }
        }

        # 3. Component removal (waits for the scan if it is still running)
        $script:RemovalPending = $true
        $script:ApplyRequestedAt = Get-Date
        Complete-ApplyIfReady
    }

    $btnApply.Add_Click({
            try { Invoke-Apply }
            catch {
                Write-Log "Apply crashed: $($_.Exception.Message)"
                $form.Close()
            }
        })

    # ==================================================================
    #  TIMERS AND BACKGROUND SCAN
    # ==================================================================

    # Closes the GUI by itself so a window nobody can see can never hang the installation
    $deadline = New-Object System.Windows.Forms.Timer
    $deadline.Interval = [int]($GuiTimeoutSeconds * 1000)
    $deadline.Add_Tick({
            $deadline.Stop()
            if ($script:Applying) { return }
            Write-Log "GUI timeout after $GuiTimeoutSeconds s - nothing applied"
            $form.Close()
        })

    # Picks up finished scan areas and finishes a pending Apply
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 400
    $timer.Add_Tick({
            try {
                Update-ComponentList
                Complete-ApplyIfReady
            }
            catch { Write-Log "Timer tick failed: $($_.Exception.Message)" }
        })

    $form.Add_Shown({
            try {
                Write-Log 'GUI shown'
                $deadline.Start()

                # OneDrive has no appx/capability/feature: detect it by its installer files
                if ((Test-Path -LiteralPath 'C:\Windows\System32\OneDriveSetup.exe') -or (Test-Path -LiteralPath 'C:\Windows\SysWOW64\OneDriveSetup.exe')) {
                    Add-ListItem ($AllAppsData | Where-Object { $_.Custom -eq 'OneDrive' })
                }

                # One background runspace, areas scanned one after another (DISM does not like parallel work)
                $script:scanPs = [powershell]::Create()
                [void]$script:scanPs.AddScript({
                        param($scan)
                        try { $scan['Appx'] = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop) }
                        catch { $scan['AppxError'] = $_.Exception.Message; $scan['Appx'] = @() }
                        try { $scan['Feats'] = @(Get-WindowsOptionalFeature -Online -ErrorAction Stop | Where-Object { $_.State -notin @('Disabled', 'DisabledWithPayloadRemoved') }) }
                        catch { $scan['FeatsError'] = $_.Exception.Message; $scan['Feats'] = @() }
                        try { $scan['Caps'] = @(Get-WindowsCapability -Online -ErrorAction Stop | Where-Object { $_.State -notin @('NotPresent', 'Removed') }) }
                        catch { $scan['CapsError'] = $_.Exception.Message; $scan['Caps'] = @() }
                        $scan['Done'] = $true
                    }).AddArgument($script:scan)
                [void]$script:scanPs.BeginInvoke()
                $timer.Start()
            }
            catch { Write-Log "Shown handler failed: $($_.Exception.Message)" }
        })

    $form.Add_FormClosed({
            if (-not $script:Applying) { Write-Log 'Window closed without applying' }
        })

    [void]$form.ShowDialog()
    Write-Log 'GUI closed'
}
catch {
    Write-Log "FATAL: $($_.Exception.Message)"
}

Write-Log '---- tweaker finished'
exit 0
