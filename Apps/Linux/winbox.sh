#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "============================================="
echo " Installing Native WinBox 4+ for Linux"
echo "============================================="

# 2. Setup directory paths
TARGET_DIR="$HOME/.local/bin"
ICON_DIR="$HOME/.local/share/icons"
LAUNCHER_DIR="$HOME/.local/share/applications"
TMP_DIR=$(mktemp -d)

mkdir -p "$TARGET_DIR" "$ICON_DIR" "$LAUNCHER_DIR"

# Ensure cleanup of temporary directory on exit
trap 'rm -rf "$TMP_DIR"' EXIT

# 3. Scrape the official WinBox sub-page for the actual download URL
echo "--> Fetching the latest download URL from MikroTik..."
DOWNLOAD_PAGE="https://mikrotik.com/download/winbox"
WINBOX_URL=$(curl -s "$DOWNLOAD_PAGE" | grep -oP 'https://download.mikrotik.com/routeros/winbox/[d.]+/WinBox_Linux.zip' | head -n 1)

if [ -z "$WINBOX_URL" ]; then
    echo "[-] Error: Could not dynamically resolve the WinBox URL from $DOWNLOAD_PAGE"
    echo "[-] Falling back to v4.1 target path..."
    WINBOX_URL="https://download.mikrotik.com/routeros/winbox/4.1/WinBox_Linux.zip"
fi

echo "--> Found URL: $WINBOX_URL"

# 4. Download the package
echo "--> Downloading package..."
wget -O "$TMP_DIR/WinBox_Linux.zip" "$WINBOX_URL"

# 5. Extract components
echo "--> Extracting binary..."
unzip -q -o "$TMP_DIR/WinBox_Linux.zip" -d "$TMP_DIR"

# Move the main executable
if [ -f "$TMP_DIR/WinBox" ]; then
    mv "$TMP_DIR/WinBox" "$TARGET_DIR/WinBox"
else
    mv "$TMP_DIR/"*[Ww]in[Bb]ox* "$TARGET_DIR/WinBox" 2>/dev/null || true
fi
chmod +x "$TARGET_DIR/WinBox"

# Extract internal icon from zip asset path and move it to the Linux icon path
echo "--> Extracting and placing application icon..."
if [ -f "$TMP_DIR/assets/img/winbox.png" ]; then
    mv "$TMP_DIR/assets/img/winbox.png" "$ICON_DIR/winbox.png"
else
    echo "[-] Asset icon not found in expected zip path. Falling back to external fetch..."
    wget -O "$ICON_DIR/winbox.png" "https://upload.wikimedia.org/wikipedia/commons/d/d4/MikroTik_Logo.png"
fi

# 6. Create Desktop Entry
echo "--> Creating Desktop Entry..."
cat <<EOF > "$LAUNCHER_DIR/winbox.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=WinBox
Comment=MikroTik RouterOS Management Client (Native Linux)
Exec=$TARGET_DIR/WinBox
Icon=winbox
Terminal=false
Categories=Network;Utility;
EOF

# 7. Refresh desktop shortcuts database
if command -v update-desktop-database &> /dev/null; then
    update-desktop-database "$LAUNCHER_DIR"
fi

echo "============================================="
echo " Done! The latest native WinBox is installed."
echo " Launch it via your application menu or run: WinBox"
echo "============================================="
