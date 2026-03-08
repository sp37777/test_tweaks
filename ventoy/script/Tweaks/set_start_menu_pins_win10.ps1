. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "Header.ps1")

# 1. Define the Shell directories for the Users
$Dirs = 'C:\Users\Default\AppData\Local\Microsoft\Windows\Shell', "%AppData%\Local\Microsoft\Windows\Shell"

# 2. Check if XML file exists
$xmlContent = "$PSScriptRoot\LayoutModification.xml"
if (Test-Path $xmlContent) {
    # 3. Copy it to User profiles
    foreach ($Dir in $Dirs) {
        if (-not (Test-Path $Dir)) {
            New-Item -Path $Dir -ItemType Directory -Force;
        }
        Copy-Item -Path $xmlContent -Destination $Dir
    }

    # 4. (Optional) Clean up by deleting the temporary folder from the C: drive
    $CustomLayout = 'C:\CustomLayout'
    if (Test-Path $CustomLayout) {
        Remove-Item -Path $CustomLayout -Recurse -Force
    }
}