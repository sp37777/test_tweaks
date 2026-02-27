# RegistryLib.ps1

# Check if Windows Setup is currently in progress
$isSetup = (Get-ItemProperty "HKLM:\System\Setup" -Name "SystemSetupInProgress" -ErrorAction SilentlyContinue).SystemSetupInProgress -eq 1
$defaultMountpoint = "HKU\DefaultUser"
$Global:CurrentMountPoint = $defaultMountpoint
$Global:IsBulkTweak = $false
$Global:osVersion = $null

if (-not $PSScriptRoot) {
    $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
}

function Get-SafeRegistryPath {
    param([string]$Path)
    $PathsToUpdate = New-Object 'System.Collections.Generic.List[string]'
    $PathsToUpdate.Add($Path)
    if ($isSetup -and $Path -match "CurrentControlSet") {
        # Swap CurrentControlSet for ControlSet001
        $PathsToUpdate.Add(($Path -replace "CurrentControlSet", "ControlSet001"))
    }
    
    return $PathsToUpdate
}

function Get-OSVersion {
    if ($null -ne $Global:osVersion) {
        return $Global:osVersion
    }

    # Define the path clearly
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $info = Get-ItemProperty -Path $regPath

    # 1. Get the Build Number (Reliable for 10 vs 11)
    [int]$build = $info.CurrentBuild

    # 2. Check for Modern Version Numbers (Win 10/11)
    # Note: These keys DO NOT EXIST in Windows 7/8.1
    $major = $info.CurrentMajorVersionNumber 

    if ($null -ne $major) {
        if ($build -ge 22000) {
            $Global:osVersion = 11
        } else {
            $Global:osVersion = 10
        }
    } 
    # 3. Fallback to ProductName for Legacy (Win 7/8.1)
    else {
        $prodName = $info.ProductName
        if ($prodName -like "*Windows 8.1*") {
            $Global:osVersion = 8.1
        } elseif ($prodName -like "*Windows 7*") {
            $Global:osVersion = 7
        }
    }

    return $Global:osVersion
}


function Mount-DefaultHive {
    param([string]$MountPoint = $defaultMountpoint)
    
    $HivePath = "C:\Users\Default\NTUSER.DAT"
    $Global:CurrentMountPoint = $MountPoint
    # 1. Check if already mounted
    if (Is-DefaultHiveMounted) {
		Write-Host "[Lib] Hive already mounted at $MountPoint" -ForegroundColor Gray
		return true
	}
	
	[System.GC]::Collect()
	[System.GC]::WaitForPendingFinalizers()
    
    # 2. Try to mount
    if (Test-Path $HivePath) {
        Write-Host "[Lib] Mounting Default Hive..." -ForegroundColor Cyan
        reg load "$MountPoint" "$HivePath" | Out-Null
        return $true
    }
    
    Write-Warning "[Lib] Default NTUSER.DAT not found at $HivePath"
    return $false
}

function Dismount-DefaultHive {
    param([string]$MountPoint = $Global:CurrentMountPoint)
    
    if (Is-DefaultHiveMounted $MountPoint) {
        Write-Host "[Lib] Dismounting Hive..." -ForegroundColor Cyan
        # Force cleanup of open handles
        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
        Start-Sleep -s 1
        reg unload $MountPoint | Out-Null
    }
}

function Is-DefaultHiveMounted {
	param([string]$MountPoint = $Global:CurrentMountPoint)
	return Test-Path "Registry::$MountPoint"
}

function Get-UserRegistryTargets {
    $targets = New-Object 'System.Collections.Generic.List[string]'
    # Always target current user (SYSTEM during specialize)
    [void]$targets.Add("HKCU")
    # Mount DefaultUser if available (idempotent)
    if (Is-DefaultHiveMounted $Global:CurrentMountPoint) {
        [void]$targets.Add($Global:CurrentMountPoint)
    }
    return $targets
}

function Apply-RegistryTweak {
    param (
        [Parameter(Mandatory=$true)]
        [string] $Root,

        [Parameter(Mandatory=$true)]
        [string] $SubPath,

        [Parameter(Mandatory=$true)]
        [string] $Name,

        [Parameter(Mandatory=$true)]
        $Value,

        # Change: Added "" to ValidateSet or allow null
        [ValidateSet("DWord", "QWord", "String", "ExpandString", "Binary", "MultiString", "")]
        [string] $Type = "" 
    )

    # --- Type inference ---
    # Change: Check if $Type is null or empty string
    if ($null -eq $Type -or $Type.Trim() -eq "") {
        switch ($Value.GetType().FullName) {
            'System.Byte[]'     { $Type = 'Binary' }
            'System.String'     { $Type = 'String' }
            'System.Int32'      { $Type = 'DWord' }
            'System.UInt32'     { $Type = 'DWord' }
            'System.Int64'      { $Type = 'QWord' }
            'System.UInt64'     { $Type = 'QWord' }
            'System.String[]'   { $Type = 'MultiString' }
            'System.Boolean' {
                $Type  = 'DWord'
                $Value = [int]$Value
            }
            default {
                throw "Apply-RegistryTweak: Cannot infer registry type for value '$Value' ($($Value.GetType().FullName))."
            }
        }
    }

    $subPaths = Get-SafeRegistryPath -Path $SubPath
    foreach ($path in $subPaths) {
        $regPath = "Registry::$Root\$path"
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        Set-ItemProperty -Path $regPath -Name $Name -Value $Value -Type $Type
    }
}


function Apply-SystemTweak {
    param (
        [Parameter(Mandatory=$true)]
        [string] $SubPath,

        [Parameter(Mandatory=$true)]
        [string] $Name,

        [Parameter(Mandatory=$true)]
        $Value,

        [ValidateSet("DWord", "QWord", "String", "ExpandString", "Binary", "MultiString")]
        [string] $Type
    )

    $SubPath = $SubPath -replace '^(HKLM|HKCU):\\', ''

    Apply-RegistryTweak "HKLM" $SubPath $Name $Value $Type
}

function Apply-UserTweak {
    param (
        [Parameter(Mandatory=$true)]
        [string] $SubPath,

        [Parameter(Mandatory=$true)]
        [string] $Name,

        [Parameter(Mandatory=$true)]
        $Value,

        [ValidateSet("DWord", "QWord", "String", "ExpandString", "Binary", "MultiString")]
        [string] $Type
    )

    $SubPath = $SubPath -replace '^(HKLM|HKCU):\\', ''

    foreach ($Root in (Get-UserRegistryTargets)) {
        Apply-RegistryTweak $Root $SubPath $Name $Value $Type
    }
}

function Remove-RegistryItem {
    param (
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$false)][string]$Name
    )
    $regPath = "Registry::$Root\$Path"
    if (Test-Path $regPath) {
        if ($null -ne $Name -and $Name -ne "") {
            # Removes a specific value
            Remove-ItemProperty -Path $regPath -Name $Name -Force -ErrorAction SilentlyContinue
        } else {
            # Removes the entire key and subkeys
            Remove-Item -Path $regPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Remove-SystemRegistryItem {
    param ([string]$Path, [string]$Name)
    $Path = $Path -replace '^(HKLM|HKCU):\\', ''
    Remove-RegistryItem "HKLM" $Path $Name
}

function Remove-UserRegistryItem {
    param ([string]$Path, [string]$Name)
    $Path = $Path -replace '^(HKLM|HKCU):\\', ''
    foreach ($Root in (Get-UserRegistryTargets)) {
        Remove-RegistryItem $Root $Path $Name
    }
}

function Initialize-TweakEnvironment {
    if (-not(Is-DefaultHiveMounted) -and -not($Global:IsBulkTweak)) {
        Mount-DefaultHive
    }
}

function Finalize-TweakEnvironment {
    param($isSetup)
    if (-not($isSetup) -and -not($Global:IsBulkTweak)) {
        Dismount-DefaultHive
    }
}

function Should-Apply($key) {
    $iniPath = "C:\Windows\Setup\Scripts\user_choices.ini"
    if (Test-Path $iniPath) {
        # Read the file and look for the specific key=1 pattern
        # This bypasses the need for ConvertFrom-StringData and handles sections safely
        $match = Get-Content $iniPath | Where-Object { $_ -match "^\s*$key\s*=\s*1" }
        if ($null -ne $match) {
            return $true
        }
    } else {
        # If no INI exists, default to applying the tweak
        return $true
    }
    return $false
}