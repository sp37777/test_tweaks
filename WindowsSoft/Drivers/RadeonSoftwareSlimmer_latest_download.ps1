# Define the repository
$repo = "GSDragoon/RadeonSoftwareSlimmer"
$apiUrl = "https://api.github.com/repos/$repo/releases/latest"

# Fetch the latest release data
Write-Host "Checking for the latest version..." -ForegroundColor Cyan
$release = Invoke-RestMethod -Uri $apiUrl

# Find the download URL (specifically for the .zip file)
$asset = $release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
$downloadUrl = $asset.browser_download_url
$fileName = $asset.name

if ($downloadUrl) {
    Write-Host "Downloading version $($release.tag_name): $fileName" -ForegroundColor Green
    Invoke-WebRequest -Uri $downloadUrl -OutFile $fileName
    Write-Host "Download complete!" -ForegroundColor Green
} else {
    Write-Error "Could not find a zip file in the latest release."
}