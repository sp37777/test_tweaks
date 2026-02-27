# Use this to find the header in the SAME directory
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "Header.ps1")

foreach ($Root in (Get-UserRegistryTargets)) {
    # 1. Fix the variable expansion using curly braces
    $Path = "Registry::${Root}\Software\Microsoft\Windows\CurrentVersion\TaskManager"

    Write-Host "Applying task manager detailed view tweak to ${Path}"

    # 2. Check if the Registry Key exists; if not (e.g., during Sysprep/Specialize), create it
    if (!(Test-Path $Path)) {
        Write-Host "Registry path not found. Creating new key for installation stage..." -ForegroundColor Yellow
        New-Item -Path $Path -Force | Out-Null
    }

    # 3. Get the 'Preferences' item property safely
    $registryValue = Get-ItemProperty -Path $Path -Name "Preferences" -ErrorAction SilentlyContinue

    # 4. Process the data
    $binData = $registryValue.Preferences
    if ($null -ne $registryValue -and $registryValue.Preferences.Count -ge 29) {
        Write-Host "Using main method"
        $binData[28] = 1
    } else {
        Write-Host "Using fallback method"
        $binData = [byte[]](
            0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 
            0x01, 0x00, 0x00, 0x00, 0x28, 0x00, 0x00, 0x00, 
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        );
    }
    if ($null -ne $binData) {
         Set-ItemProperty -Path $Path -Name "Preferences" -Value $binData
    }
}

Write-Host "Task Manager tweak applied successfully." -ForegroundColor Green