<#
  removal_gui.ps1 - confirm-and-remove step for the specialize stage (skeleton, based on tweaker.ps1)

  Flow
    1. Reads user_choices.json (written by the WinPE chooser) -> ids in "remove" are preselected.
    2. Reads removables.json (the catalog; single source of truth for names and targets).
    3. Scans the installed system in a background runspace; only catalog entries that are really
       present are listed (so whatever unattend.xml already removed never shows up).
    4. When the scan is done a countdown starts. Any change of a checkbox, or Select All/None,
       stops it for good. The countdown reaching 0 or the Start button runs the removal.
    5. Companion tweaks (Spec / Hive / Once) are kept in $Companions, keyed by catalog id.

  Rules (same as tweaker.ps1)
    * A failing step is logged and skipped. The script always exits 0 and never blocks setup.
    * No GUI is shown when there is nothing to confirm (no user_choices.json, or an empty "remove"
      list) unless -AlwaysShow is given.
    * Closing the window, or leaving it idle after the countdown was stopped, applies nothing.
    * -DryRun shows the GUI and logs what WOULD be done.

  Log: C:\Windows\Setup\Scripts\removal_gui.log
#>
param(
    [string]$ChoicesPath,
    [string]$CatalogPath,
    [int]$CountdownSeconds = 60,
    [int]$IdleTimeoutSeconds = 600,
    [int]$ScanWaitTimeoutSeconds = 600,
    [switch]$AlwaysShow,
    [switch]$ConsumeChoices,
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$LogFile = 'C:\Windows\Setup\Scripts\removal_gui.log'

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

function Invoke-RegAdd {
    param([string[]]$RegArgs)
    [void](Invoke-Native -Exe 'reg.exe' -Arguments (@('add') + $RegArgs) -Label "reg add $($RegArgs[0])")
}

# ======================================================================
#  FINDING THE FILES
# ======================================================================

# ADAPT: replace this with the lookup specialize_custom.ps1 already uses for user_choices.json.
# Default order: next to this script, then well-known folders on every drive root.
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

function Read-JsonFile {
    param([string]$Path)
    # -Encoding UTF8: Windows PowerShell 5.1 would otherwise read the file as ANSI
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

# ======================================================================
#  COMPANION TWEAKS, keyed by catalog id
#  Spec = run as SYSTEM, Hive = run while HKU\DefaultUser is loaded,
#  Once = PowerShell text that runs at the first logon of every new user.
#  Ported from tweaker.ps1; add the rest of your entries the same way.
# ======================================================================

$Companions = @{
    'notepad-modern' = @{
        Spec = {
            Invoke-RegAdd @('HKCR\.txt\ShellNew', '/v', 'ItemName', '/t', 'REG_EXPAND_SZ', '/d', '@C:\Windows\system32\notepad.exe,-470', '/f')
            Invoke-RegAdd @('HKCR\.txt\ShellNew', '/v', 'NullFile', '/t', 'REG_SZ', '/f')
            Invoke-RegAdd @('HKCR\txtfilelegacy', '/v', 'FriendlyTypeName', '/t', 'REG_EXPAND_SZ', '/d', '@C:\Windows\system32\notepad.exe,-469', '/f')
            Invoke-RegAdd @('HKCR\txtfilelegacy', '/ve', '/t', 'REG_SZ', '/d', 'Text Document', '/f')
        }
    }
    'onedrive'       = @{
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
        Hive = { [void](Invoke-Native -Exe 'reg.exe' -Arguments @('delete', 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Run', '/v', 'OneDriveSetup', '/f') -Label 'reg delete OneDriveSetup' -AllowFail) }
    }
    'outlook-new'    = @{
        Spec = { Remove-Item -LiteralPath 'HKLM:\Software\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' -Recurse -Force -ErrorAction SilentlyContinue }
    }
    'xbox'           = @{
        Hive = { Add-HiveDword 'Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0 }
    }
    'dev-home'       = @{
        Spec = { Remove-Item -LiteralPath 'HKLM:\Software\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate' -Recurse -Force -ErrorAction SilentlyContinue }
    }
    'teams'          = @{
        Spec = { Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Communications' 'ConfigureChatAutoInstall' 0 }
    }
    'copilot'        = @{
        Hive = { Add-HiveDword 'Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1 }
        Once = "Get-AppxPackage -Name 'Microsoft.Windows.Ai.Copilot.Provider' | Remove-AppxPackage"
    }
}

# "custom" catalog targets have no appx/capability/feature: detect them here. Removal itself is
# done by the companion tweaks above.
function Test-CustomPresent {
    param([string]$Name)
    switch ($Name) {
        'onedrive' {
            return ((Test-Path -LiteralPath 'C:\Windows\System32\OneDriveSetup.exe') -or (Test-Path -LiteralPath 'C:\Windows\SysWOW64\OneDriveSetup.exe'))
        }
        default { return $false }
    }
}

# ======================================================================
#  STATE
# ======================================================================

$script:scan = [hashtable]::Synchronized(@{})   # filled by the background runspace
$script:areaShown = @{ Appx = $false; Feats = $false; Caps = $false }
$script:listed = @{}
$script:Catalog = @()
$script:Preselect = @{}
$script:UseCatalogDefaults = $false
$script:Populating = $false
$script:CountdownArmed = $true
$script:CountdownLeft = $CountdownSeconds
$script:Applying = $false
$script:ApplyDone = $false
$script:RemovalPending = $false
$script:ApplyRequestedAt = $null

# ======================================================================
#  MAIN
# ======================================================================

try {
    Write-Log "---- removal_gui started (DryRun=$([bool]$DryRun), UserInteractive=$([Environment]::UserInteractive))"

    if (-not [Environment]::UserInteractive) {
        Write-Log 'Session is not interactive - the GUI cannot be shown. Nothing applied.'
        exit 0
    }

    # --- choices ---
    if (-not $ChoicesPath) { $ChoicesPath = Find-ChoicesFile }
    $choices = $null
    if ($ChoicesPath -and (Test-Path -LiteralPath $ChoicesPath)) {
        try { $choices = Read-JsonFile $ChoicesPath; Write-Log "Choices: $ChoicesPath" }
        catch { Write-Log "user_choices.json unreadable: $($_.Exception.Message)" }
    }
    else {
        Write-Log 'user_choices.json not found'
    }

    $remove = @()
    if ($choices -and $choices.remove) { $remove = @($choices.remove) }
    foreach ($id in $remove) { $script:Preselect["$id"] = $true }

    if (-not $AlwaysShow -and $remove.Count -eq 0) {
        Write-Log 'Nothing preselected in WinPE - no GUI (use -AlwaysShow to review anyway)'
        exit 0
    }
    if (-not $choices) { $script:UseCatalogDefaults = $true }   # -AlwaysShow without a choices file

    # --- catalog ---
    if (-not $CatalogPath) {
        $cands = @()
        if ($ChoicesPath) { $cands += (Join-Path (Split-Path -Parent $ChoicesPath) 'removables.json') }
        if ($PSScriptRoot) { $cands += (Join-Path $PSScriptRoot 'removables.json') }
        foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { $CatalogPath = $c; break } }
    }
    if (-not $CatalogPath -or -not (Test-Path -LiteralPath $CatalogPath)) {
        Write-Log 'removables.json not found - nothing applied'
        exit 0
    }
    try { $script:Catalog = @((Read-JsonFile $CatalogPath).items) }
    catch { Write-Log "removables.json unreadable: $($_.Exception.Message)"; exit 0 }
    Write-Log "Catalog: $CatalogPath ($($script:Catalog.Count) entries), preselected: $($remove.Count)"

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
    [System.Windows.Forms.Application]::add_ThreadException({ param($s, $e) Write-Log "UI exception: $($e.Exception.Message)" })

    # --- WINDOW ---
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Remove components'
    if ($DryRun) { $form.Text += ' [DRY RUN]' }
    $form.Size = New-Object System.Drawing.Size(480, 600)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.TopMost = $true
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Text = 'Checked items were chosen in WinPE. Change anything you like, then press Start.'
    $lblInfo.Location = New-Object System.Drawing.Point(15, 12)
    $lblInfo.Size = New-Object System.Drawing.Size(440, 36)
    $form.Controls.Add($lblInfo)

    $lv = New-Object System.Windows.Forms.ListView
    $lv.Location = New-Object System.Drawing.Point(15, 52)
    $lv.Size = New-Object System.Drawing.Size(440, 365)
    $lv.View = 'Details'
    $lv.CheckBoxes = $true
    $lv.FullRowSelect = $true
    $lv.HideSelection = $false
    $lv.HeaderStyle = 'None'
    [void]$lv.Columns.Add('Component', 400)
    $form.Controls.Add($lv)

    $lblScan = New-Object System.Windows.Forms.Label
    $lblScan.Text = 'Scan: appx ... | features ... | capabilities ...'
    $lblScan.Location = New-Object System.Drawing.Point(15, 423)
    $lblScan.Size = New-Object System.Drawing.Size(440, 20)
    $form.Controls.Add($lblScan)

    $lblCount = New-Object System.Windows.Forms.Label
    $lblCount.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $lblCount.Text = 'Scanning...'
    $lblCount.Location = New-Object System.Drawing.Point(15, 447)
    $lblCount.Size = New-Object System.Drawing.Size(440, 24)
    $form.Controls.Add($lblCount)

    $btnAll = New-Object System.Windows.Forms.Button
    $btnAll.Text = 'Select All'
    $btnAll.Location = New-Object System.Drawing.Point(15, 480)
    $btnAll.Size = New-Object System.Drawing.Size(110, 28)
    $form.Controls.Add($btnAll)

    $btnNone = New-Object System.Windows.Forms.Button
    $btnNone.Text = 'Select None'
    $btnNone.Location = New-Object System.Drawing.Point(133, 480)
    $btnNone.Size = New-Object System.Drawing.Size(110, 28)
    $form.Controls.Add($btnNone)

    $btnStart = New-Object System.Windows.Forms.Button
    $btnStart.Text = 'Start'
    $btnStart.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $btnStart.Location = New-Object System.Drawing.Point(15, 516)
    $btnStart.Size = New-Object System.Drawing.Size(440, 38)
    $btnStart.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnStart.ForeColor = [System.Drawing.Color]::White
    $btnStart.FlatStyle = 'Flat'
    $form.Controls.Add($btnStart)

    # ==================================================================
    #  CATALOG MATCHING AND LIST
    # ==================================================================

    # Installed objects that belong to a catalog entry (uses only the areas scanned so far)
    function Get-CatalogMatches {
        param($Item)
        $appx = @(); $caps = @(); $feats = @(); $custom = @()
        foreach ($t in @($Item.targets)) {
            $kind = [string]$t.kind
            $pattern = [string]$t.name
            if ($kind -eq 'appx') {
                if ($script:scan.ContainsKey('Appx')) {
                    $appx += @($script:scan['Appx'] | Where-Object { $_.DisplayName -like $pattern })
                }
            }
            elseif ($kind -eq 'capability') {
                # matches the full name (Language.Handwriting~~~en-US~0.0.1.0) or just the part before the first ~
                if ($script:scan.ContainsKey('Caps')) {
                    $caps += @($script:scan['Caps'] | Where-Object { ($_.Name -like $pattern) -or ((($_.Name -split '~')[0]) -like $pattern) })
                }
            }
            elseif ($kind -eq 'feature') {
                if ($script:scan.ContainsKey('Feats')) {
                    $feats += @($script:scan['Feats'] | Where-Object { $_.FeatureName -like $pattern })
                }
            }
            elseif ($kind -eq 'custom') {
                if (Test-CustomPresent $pattern) { $custom += $pattern }
            }
        }
        $appx = @($appx | Sort-Object -Property PackageName -Unique)
        $caps = @($caps | Sort-Object -Property Name -Unique)
        $feats = @($feats | Sort-Object -Property FeatureName -Unique)
        return [pscustomobject]@{ Appx = $appx; Caps = $caps; Feats = $feats; Custom = $custom }
    }

    function Add-ListItem {
        param($Item)
        $id = [string]$Item.id
        if ($script:listed.ContainsKey($id)) { return }
        $li = New-Object System.Windows.Forms.ListViewItem([string]$Item.label)
        $li.Tag = $Item
        if ($script:UseCatalogDefaults) { $li.Checked = [bool]$Item.default }
        else { $li.Checked = $script:Preselect.ContainsKey($id) }
        [void]$lv.Items.Add($li)
        $script:listed[$id] = $true
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
                # Items found after Start was pressed are not offered (the person never saw them)
                if (-not $script:Applying) {
                    $script:Populating = $true       # programmatic Checked must not stop the countdown
                    try {
                        foreach ($item in $script:Catalog) {
                            if ($script:listed.ContainsKey([string]$item.id)) { continue }
                            $m = Get-CatalogMatches $item
                            if (($m.Appx.Count + $m.Caps.Count + $m.Feats.Count + $m.Custom.Count) -gt 0) { Add-ListItem $item }
                        }
                    }
                    finally { $script:Populating = $false }
                }
            }
        }
        $st = { param($k) if ($script:scan.ContainsKey($k)) { 'done' } else { '...' } }
        $lblScan.Text = "Scan: appx $(& $st 'Appx') | features $(& $st 'Feats') | capabilities $(& $st 'Caps')"
    }

    # ==================================================================
    #  REMOVAL
    # ==================================================================

    # "First logon of every new user" snippets: own file and own RunOnce value, so they cannot
    # collide with tweaker.ps1 or with the generator's scripts.
    function Write-UserOnce {
        param([string[]]$Snippets)
        $dir = 'C:\Windows\Setup\Scripts\tweaks'
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('# Generated by removal_gui.ps1 - runs once at the first logon of every new user')
        foreach ($s in $Snippets) {
            [void]$sb.AppendLine('try {')
            [void]$sb.AppendLine($s)
            [void]$sb.AppendLine('} catch { }')
        }
        Set-Content -LiteralPath (Join-Path $dir 'useronce_removal.ps1') -Value $sb.ToString() -Encoding UTF8
        Invoke-DefaultHive {
            [void](Invoke-Native -Exe 'reg.exe' -Arguments @('add', 'HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\RunOnce', '/v', 'RemovalGuiUserOnce', '/t', 'REG_SZ', '/d', 'powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File C:\Windows\Setup\Scripts\tweaks\useronce_removal.ps1', '/f') -Label 'register RunOnce')
        }
    }

    function Invoke-Companions {
        param($Items)
        foreach ($it in $Items) {
            $c = $Companions[[string]$it.id]
            if ($c -and $c.Spec) { Invoke-Step "Companion tweaks (system): $($it.label)" $c.Spec }
        }
        $hiveItems = @($Items | Where-Object { $Companions[[string]$_.id] -and $Companions[[string]$_.id].Hive })
        if ($hiveItems.Count -gt 0) {
            Invoke-Step 'Companion tweaks (default user hive)' {
                Invoke-DefaultHive {
                    foreach ($it in $hiveItems) {
                        try { & $Companions[[string]$it.id].Hive; Write-Log "OK     hive tweak: $($it.label)" }
                        catch { Write-Log "FAILED hive tweak: $($it.label) : $($_.Exception.Message)" }
                    }
                }
            }
        }
        $onceSnippets = @($Items | Where-Object { $Companions[[string]$_.id] -and $Companions[[string]$_.id].Once } | ForEach-Object { [string]$Companions[[string]$_.id].Once })
        if ($onceSnippets.Count -gt 0) {
            Invoke-Step 'Companion tweaks (first logon of each new user)' { Write-UserOnce $onceSnippets }
        }
    }

    function Remove-SelectedComponents {
        $selected = @($lv.Items | Where-Object { $_.Checked })
        $items = @()
        $i = 0
        foreach ($li in $selected) {
            $i++
            $item = $li.Tag
            $items += $item
            $btnStart.Text = "Removing $($item.label) ($i/$($selected.Count))..."
            [System.Windows.Forms.Application]::DoEvents()
            $m = Get-CatalogMatches $item
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
        # Registry/files only after all DISM work, so the default hive is never loaded during DISM
        $btnStart.Text = 'Applying companion tweaks...'
        [System.Windows.Forms.Application]::DoEvents()
        Invoke-Companions $items
    }

    # Runs the removal once the scan has finished (or the wait timed out), then closes the form
    function Complete-ApplyIfReady {
        if (-not $script:RemovalPending) { return }
        $waited = ((Get-Date) - $script:ApplyRequestedAt).TotalSeconds
        if (-not $script:scan.ContainsKey('Done') -and $waited -lt $ScanWaitTimeoutSeconds) {
            $btnStart.Text = 'Waiting for the component scan to finish...'
            return
        }
        $script:RemovalPending = $false
        $tick.Stop()
        if (-not $script:scan.ContainsKey('Done')) {
            Write-Log "Scan did not finish within $ScanWaitTimeoutSeconds s - removal skipped"
        }
        else {
            Remove-SelectedComponents
        }
        Write-Log 'Removal finished'
        $script:ApplyDone = $true
        $form.Close()
    }

    function Start-Apply {
        if ($script:Applying) { return }
        $script:Applying = $true
        $script:CountdownArmed = $false
        $idle.Stop()
        foreach ($c in @($lv, $btnAll, $btnNone, $btnStart)) { $c.Enabled = $false }
        $lblCount.Text = ''
        $btnStart.Text = 'Applying...'
        $form.Refresh()
        $names = @($lv.Items | Where-Object { $_.Checked } | ForEach-Object { $_.Tag.id }) -join ', '
        Write-Log "Start: $names"
        $script:RemovalPending = $true
        $script:ApplyRequestedAt = Get-Date
        Complete-ApplyIfReady
    }

    # ==================================================================
    #  COUNTDOWN AND IDLE TIMER
    # ==================================================================

    function Stop-Countdown {
        if ($script:Applying) { return }
        if ($script:CountdownArmed) { Write-Log 'Countdown stopped by the user' }
        $script:CountdownArmed = $false
        $lblCount.Text = 'Timer stopped. Press Start when you are ready.'
        # Idle safety net: a window nobody touches must never hang the installation
        $idle.Stop(); $idle.Start()
    }

    $idle = New-Object System.Windows.Forms.Timer
    $idle.Interval = [int]($IdleTimeoutSeconds * 1000)
    $idle.Add_Tick({
            $idle.Stop()
            if ($script:Applying) { return }
            Write-Log "Idle timeout after $IdleTimeoutSeconds s - nothing applied"
            $form.Close()
        })

    # One-second tick: fills the list as scan areas finish, runs the countdown, finishes a pending Start
    $tick = New-Object System.Windows.Forms.Timer
    $tick.Interval = 1000
    $tick.Add_Tick({
            try {
                Update-ComponentList
                Complete-ApplyIfReady
                if ($script:Applying) { return }

                if (-not $script:scan.ContainsKey('Done')) {
                    if ($script:CountdownArmed) { $lblCount.Text = 'Scanning... the countdown starts when the list is complete.' }
                    return
                }
                if ($lv.Items.Count -eq 0) {
                    Write-Log 'Nothing from the catalog is installed - nothing to remove'
                    $script:ApplyDone = $true
                    $form.Close()
                    return
                }
                if ($script:CountdownArmed) {
                    $script:CountdownLeft--
                    if ($script:CountdownLeft -le 0) {
                        Write-Log 'Countdown finished'
                        Start-Apply
                    }
                    else {
                        $lblCount.Text = "Starting in $($script:CountdownLeft) s - change anything to stop the timer"
                    }
                }
            }
            catch { Write-Log "Timer tick failed: $($_.Exception.Message)" }
        })

    # ==================================================================
    #  EVENTS
    # ==================================================================

    $lv.Add_ItemChecked({ if (-not $script:Populating) { Stop-Countdown } })
    $btnAll.Add_Click({ foreach ($li in $lv.Items) { $li.Checked = $true } })
    $btnNone.Add_Click({ foreach ($li in $lv.Items) { $li.Checked = $false } })
    $btnStart.Add_Click({
            try { Start-Apply }
            catch { Write-Log "Start crashed: $($_.Exception.Message)"; $script:ApplyDone = $true; $form.Close() }
        })

    # The window cannot be closed in the middle of the removal
    $form.Add_FormClosing({
            param($s, $e)
            if ($script:Applying -and -not $script:ApplyDone) { $e.Cancel = $true }
        })

    $form.Add_Shown({
            try {
                Write-Log 'GUI shown'
                $tick.Start()

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
            }
            catch { Write-Log "Shown handler failed: $($_.Exception.Message)" }
        })

    $form.Add_FormClosed({
            if (-not $script:Applying) { Write-Log 'Window closed without applying' }
        })

    [void]$form.ShowDialog()
    Write-Log 'GUI closed'

    # One-shot choices: the file must not leak into the next installation from the same flash drive.
    # Use -ConsumeChoices only in the LAST script that reads user_choices.json.
    if ($ConsumeChoices -and $ChoicesPath -and (Test-Path -LiteralPath $ChoicesPath)) {
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

Write-Log '---- removal_gui finished'
exit 0
