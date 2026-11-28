# If this is a 64-bit OS but the script is running in a 32-bit process, QUIT.
# This happens when the x86 pass of the unattend.xml runs on a 64-bit ISO.
# Replace line 4 with:
if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64") { exit }

# Logging and Arguments
$passedDrive = $args[0]
$timestamp = Get-Date -Format "HH:mm:ss"
if ($null -eq $passedDrive -or $passedDrive -eq "") { $logDrive = "Unknown" } else { $logDrive = $passedDrive }
Write-Host "=== STARTING SPECIALIZE SCRIPT ===" -ForegroundColor Cyan

# Ensure the library is dot-sourced first
if (-not $PSScriptRoot) {
    $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
. "$PSScriptRoot\RegistryLib.ps1"

# Get the version using the new function
$osVersion = Get-OSVersion

# Search for Source (USB)
if ($null -eq $passedDrive -or $passedDrive.Trim() -eq "") {
    Write-Host "No drive passed, searching manually..." -ForegroundColor Yellow
    
    # We look for the folder specifically
    $drive = Get-PSDrive -PSProvider FileSystem | Where-Object { 
        $rootPath = if ($_.Root.EndsWith("\")) { $_.Root } else { "$($_.Root)\" }
        Test-Path "${rootPath}Scripts\Setup" 
    } | Select-Object -First 1
    
    if ($drive) {
        $passedDrive = $drive.Root
        Write-Host "Found source at: $passedDrive" -ForegroundColor Green
    } else {
        Write-Host "CRITICAL ERROR: USB drive not found!" -ForegroundColor Red
        pause
        exit
    }
}

# Path Correction
$passedDrive = $passedDrive.TrimEnd('\')
if ($passedDrive -notmatch ":$") { $passedDrive += ":" }
$src = Join-Path $passedDrive "Scripts\Setup"

if (-not (Test-Path $src)) {
    Write-Error "ERROR: USB source path '$src' not found!"
    pause
    exit
}

# Define choices target path
$TargetPath = "C:\Windows\Setup\Scripts"
if (!(Test-Path $TargetPath)) { New-Item -ItemType Directory -Path $TargetPath -Force }
$choicesName = "user_choices.json";
$SourceFile = Join-Path $src $choicesName
if (Test-Path $SourceFile) {
    Copy-Item -Path $SourceFile -Destination (Join-Path $TargetPath $choicesName) -Force
    # One-shot: the flash copy is removed so it can never leak into the next installation
    Remove-Item -Path $SourceFile -Force -ErrorAction SilentlyContinue
    if (Test-Path $SourceFile) { Clear-Content -Path $SourceFile -Force }
}

# --- Version Specific Tweaks ---

$tweaksRoot = "$src\Tweaks"
$label = "Windows"

try {
    # 1. Mount the hive once
    Mount-DefaultHive
	$Global:IsBulkTweak = $true

    # Define which scripts to run based on version
    $7_81    = "ie_config.ps1", "wmp_config.ps1", "show_all_tray_icons.ps1"
    $81_plus = "disable_fast_startup.ps1"
    $10_11   = "disable_news_on_specialize.ps1", "restore_photo_viewer.ps1"

    # Using @() to collect all switch stream output
    $scriptsToRun = @(
        "stop_index_removable_drives.ps1"
        "general.ps1"

        switch ($osVersion) {
            "11" {
                $label = "Windows 11" # Defining the variable will not be added to array
                "11.ps1"; "expand_taskmgr_win_11" # Lined will be added to array
                $81_plus; $10_11 # Arrays will be merged to the array
            }
            "10" {
                $label = "Windows 10"
                "10.ps1"; "expand_taskmgr_win_10"; "expand_ribbon_win81_win10.ps1"
                $81_plus; $10_11
            }
            "8.1" {
                $label = "Windows 8.1"
                "81.ps1"; "expand_ribbon_win81_win10.ps1"
                $81_plus; $7_81
            }
            "7" {
                $label = "Windows 7"
                $7_81
            }
        }
    )

    foreach ($scriptPath in $scriptsToRun) {
        $scriptFullPath = Join-Path $tweaksRoot $scriptPath # More reliable for PS 2.0
        if (Test-Path $scriptFullPath) {
            try {
                Write-Host "Executing: $scriptFullPath" -ForegroundColor Cyan
                . $scriptFullPath
            } catch {
                Write-Warning "Failed to execute $scriptFullPath : $($_.Exception.Message)"
            }
        }
    }
    
}
finally {
    # 4. Clean up - This block runs regardless of success or failure above
    Dismount-DefaultHive
	$Global:IsBulkTweak = $false
}

# --- Settings and component removal ---
# Separate processes on purpose: an exit, a crash or a hung window in them cannot abort this script.
# The default user hive is dismounted at this point; the child scripts load and unload it themselves.
function Invoke-ChildScript {
    param([string]$ScriptPath, [string[]]$ScriptArgs)
    if (-not (Test-Path $ScriptPath)) { Write-Warning "Not found: $ScriptPath"; return }
    $argList = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $ScriptPath
    foreach ($a in $ScriptArgs) { $argList += ' ' + $a }
    try {
        $p = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -ArgumentList $argList -Wait -PassThru
        if ($p.ExitCode -ne 0) { Write-Warning "$ScriptPath exited with code $($p.ExitCode)" }
    } catch {
        Write-Warning "Could not run $ScriptPath : $($_.Exception.Message)"
    }
}

$choicesFile = Join-Path $TargetPath "user_choices.json"

if ($osVersion -ge 8.1) {
    Write-Host "Applying settings" -ForegroundColor Cyan
    # -SkipUserCreation: the account is created by create_user.ps1 below (works on Windows 7 too)
    Invoke-ChildScript (Join-Path $PSScriptRoot 'apply_settings.ps1') @(
        ('-ChoicesPath "{0}"' -f $choicesFile),
        '-SkipUserCreation'
    )
}
if ($osVersion -ge 10) {
    Write-Host "Removing components" -ForegroundColor Cyan
    Invoke-ChildScript (Join-Path $PSScriptRoot 'removal_gui.ps1') @(
        ('-ChoicesPath "{0}"' -f $choicesFile),
        ('-CatalogPath "{0}"' -f (Join-Path $src 'removables.json'))
    )
}

# Apply the drive label
label $env:SystemDrive.TrimEnd('\') $label


# Preparing User Environment
Write-Host "Creating User" -ForegroundColor Cyan
. "$src\create_user.ps1"

Write-Host "=== SPECIALIZE SCRIPT FINISHED ===" -ForegroundColor Green