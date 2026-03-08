# --- CONFIGURATION ---
$BaseXmlPath = "$PSScriptRoot\autounattend_base.xml" # Your Schneegans file
$OutputDir   = $PSScriptRoot
if (!(Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir }

# List of Editions and their GVLK (KMS) Keys
$Editions = @(
    @{ Name="unattend_10_schneegans_LTSC_IoT";      Key="CGK42-GYN6Y-VD22B-BX98W-J8JXD"; Desc="IoT Enterprise LTSC" },
    @{ Name="unattend_10_schneegans_enterprise";    Key="M7XTQ-FN8P6-TTKYV-9D4CC-J462D"; Desc="Standard Enterprise LTSC" },
    @{ Name="unattend_10_schneegans";               Key="";                              Desc="Uses Laptop BIOS/UEFI Key" }
)

# --- PROCESSING ---
foreach ($E in $Editions) {
    [xml]$xml = Get-Content -Path $BaseXmlPath
    
    # Setup XML Namespace (required for Microsoft unattend files)
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace("u", "urn:schemas-microsoft-com:unattend")

    # Locate the Microsoft-Windows-Setup component
    $xpath = "//u:settings[@pass='windowsPE']/u:component[@name='Microsoft-Windows-Setup']"
    $setupNode = $xml.SelectSingleNode($xpath, $ns)

    if ($setupNode) {
        # 1. Handle UserData node
        $userData = $setupNode.SelectSingleNode("u:UserData", $ns)
        if (!$userData) {
            $userData = $xml.CreateElement("UserData", "urn:schemas-microsoft-com:unattend")
            $setupNode.AppendChild($userData)
        }

        # 2. Handle ProductKey node
        $productKey = $userData.SelectSingleNode("u:ProductKey", $ns)
        if (!$productKey) {
            $productKey = $xml.CreateElement("ProductKey", "urn:schemas-microsoft-com:unattend")
            $userData.AppendChild($productKey)
        }

        # 3. Inject the Key (Empty string for the BIOS version)
        $keyNode = $productKey.SelectSingleNode("u:Key", $ns)
        if (!$keyNode) {
            $keyNode = $xml.CreateElement("Key", "urn:schemas-microsoft-com:unattend")
            $productKey.AppendChild($keyNode)
        }
        $keyNode.InnerText = $E.Key

        # 4. Set WillShowUI to OnError for all versions
        $uiNode = $productKey.SelectSingleNode("u:WillShowUI", $ns)
        if (!$uiNode) {
            $uiNode = $xml.CreateElement("WillShowUI", "urn:schemas-microsoft-com:unattend")
            $productKey.AppendChild($uiNode)
        }
        $uiNode.InnerText = "OnError"

        # Save the file
        $FileName = "autounattend_" + $E.Name + ".xml"
        $xml.Save("$OutputDir\$FileName")
        
        Write-Host "Generated: $FileName ($($E.Desc))" -ForegroundColor Green
    } else {
        Write-Host "Error: Could not find Windows-Setup component in base XML." -ForegroundColor Red
    }
}