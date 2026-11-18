# Helper function to ensure keys exist and set values
function Set-RegKey {
    param (
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = "String"
    )
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
}

# --- RESTORE WINDOWS PHOTO VIEWER ---
$baseApp = "Registry::HKEY_CLASSES_ROOT\Applications\photoviewer.dll\shell\open"
Set-RegKey -Path $baseApp -Name "MuiVerb" -Value "@photoviewer.dll,-3043"
Set-RegKey -Path "$baseApp\command" -Name "(Default)" -Value "rundll32.exe `"%ProgramFiles%\Windows Photo Viewer\PhotoViewer.dll`", ImageView_Fullscreen %1"
Set-RegKey -Path "$baseApp\DropTarget" -Name "Clsid" -Value "{FFE2A43C-56B9-4bf5-9A79-CC6D4285608A}"

# --- FILE ASSOCIATIONS (HKLM) ---
$capPath = "HKLM:\SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities\FileAssociations"
$assocs = @{
    ".bmp"  = "PhotoViewer.FileAssoc.Bitmap";  ".dib"  = "PhotoViewer.FileAssoc.Bitmap"
    ".gif"  = "PhotoViewer.FileAssoc.Gif";     ".jfif" = "PhotoViewer.FileAssoc.JFIF"
    ".jpe"  = "PhotoViewer.FileAssoc.Jpeg";    ".jpeg" = "PhotoViewer.FileAssoc.Jpeg"
    ".jpg"  = "PhotoViewer.FileAssoc.Jpeg";    ".jxr"  = "PhotoViewer.FileAssoc.Wdp"
    ".png"  = "PhotoViewer.FileAssoc.Png";     ".tif"  = "PhotoViewer.FileAssoc.Tiff"
    ".tiff" = "PhotoViewer.FileAssoc.Tiff";    ".wdp"  = "PhotoViewer.FileAssoc.Wdp"
    ".cr2"  = "PhotoViewer.FileAssoc.Tiff"
}

foreach ($ext in $assocs.Keys) {
    Set-RegKey -Path $capPath -Name $ext -Value $assocs[$ext]
}

# --- ASSOCIATION CLASSES ---
$classes = @(
    @{ Name = "Bitmap"; Icon = "-70"; Flag = 1 }
    @{ Name = "Gif";    Icon = "-83"; Flag = 1 }
    @{ Name = "JFIF";   Icon = "-72"; Flag = 0x10000; Type = "Dword" }
    @{ Name = "Jpeg";   Icon = "-72"; Flag = 0x10000; Type = "Dword" }
    @{ Name = "Png";    Icon = "-71"; Flag = 1 }
    @{ Name = "Wdp";    Icon = "-400"; Flag = 0x10000; Type = "Dword"; Dll = "wmphoto.dll" }
    @{ Name = "Tiff";   Icon = "-70"; Flag = 0x10000; Type = "Dword" }
)

foreach ($c in $classes) {
    $cPath = "Registry::HKEY_CLASSES_ROOT\PhotoViewer.FileAssoc.$($c.Name)"
    $dll = if ($c.Dll) { $c.Dll } else { "imageres.dll" }
    $flagName = if ($c.Type -eq "Dword") { "EditFlags" } else { "ImageOptionFlags" }
    $flagType = if ($c.Type -eq "Dword") { "DWord" } else { "DWord" } # Both are Dword in your reg file

    Set-RegKey -Path $cPath -Name $flagName -Value $c.Flag -Type DWord
    Set-RegKey -Path "$cPath\DefaultIcon" -Name "(Default)" -Value "%SystemRoot%\System32\$dll,$($c.Icon)"
    Set-RegKey -Path "$cPath\shell\open\command" -Name "(Default)" -Value "rundll32.exe `"%ProgramFiles%\Windows Photo Viewer\PhotoViewer.dll`", ImageView_Fullscreen %1"
}

Write-Host "Windows Photo Viewer restoration complete." -ForegroundColor Green
