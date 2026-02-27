# Header.ps1
# 1. Fix PSScriptRoot for Windows 7
if (-not $PSScriptRoot) {
    $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
}

# 2. Path to the Library (which is one level UP from the Tweaks folder)
$parentDir = (Get-Item $PSScriptRoot).Parent.FullName
$Global:LibPath = Join-Path $parentDir "RegistryLib.ps1"

# 3. Only load the library if it's not already in memory
if (-not (Get-Command Apply-SystemTweak -ErrorAction SilentlyContinue)) {
    if (Test-Path $Global:LibPath) { 
        . $Global:LibPath 
    }
}

# 4. Fix for Windows 7 Get-Content -Raw compatibility
function Get-ContentRaw([string]$FilePath) {
    if ($PSVersionTable.PSVersion.Major -ge 3) {
        return Get-Content $FilePath -Raw
    } else {
        return [System.IO.File]::ReadAllText($FilePath)
    }
}
