#!/bin/bash

set -e

echo "==========================================="
echo " Installing Android Studio to Home Directory"
echo "==========================================="

# 1. Install system dependencies (still requires sudo)
#echo "--> Installing necessary system dependencies..."
#sudo apt update
#sudo apt install -y libc6:i386 libncurses5:i386 libstdc++6:i386 lib32z1 libbz2-1.0:i386 wget curl tar unzip libsqlite3-dev

# 2. Ensure local directories exist
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.local/share"
mkdir -p "$HOME/.local/share/applications"

# 3. Fetch the absolute latest stable tar.gz download link directly
echo "--> Resolving latest Android Studio download link..."

# Scraping using a wider pattern that catches the exact direct download endpoints
DOWNLOAD_URL=$(curl -s https://developer.android.com/studio | grep -o 'https://[^"]*linux.tar.gz' | head -n 1)

if [ -z "$DOWNLOAD_URL" ]; then
    echo "Fallback: Parsing alternative manifest structure..."
    DOWNLOAD_URL=$(curl -s https://developer.android.com/studio | grep -o 'https://redirector[^"]*linux.tar.gz' | head -n 1)
fi

if [ -z "$DOWNLOAD_URL" ]; then
    echo "ERROR: Could not resolve the Google download link automatically."
    echo "Please download the Linux .tar.gz manually from https://developer.android.com/studio"
    exit 1
fi

echo "Found latest release: $DOWNLOAD_URL"

# 4. Download the tarball
echo "--> Downloading (this may take a few minutes)..."
wget -O /tmp/android-studio.tar.gz "$DOWNLOAD_URL"

# 5. Extract to ~/.local/share/
echo "--> Extracting files to ~/.local/share/..."
if [ -d "$HOME/.local/share/android-studio" ]; then
    echo "    Old local installation found. Removing it..."
    rm -rf "$HOME/.local/share/android-studio"
fi

tar -xzf /tmp/android-studio.tar.gz -C "$HOME/.local/share/"

# 6. Create a symlink in ~/.local/bin
echo "--> Creating symlink in ~/.local/bin/..."
ln -sf "$HOME/.local/share/android-studio/bin/studio.sh" "$HOME/.local/bin/studio"

# 7. Create a user-level Desktop Entry
echo "--> Creating desktop shortcut..."
cat <<EOF > "$HOME/.local/share/applications/android-studio.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Android Studio
Exec=$HOME/.local/share/android-studio/bin/studio.sh
Icon=$HOME/.local/share/android-studio/bin/studio.png
Categories=Development;IDE;
Terminal=false
StartupNotify=true
EOF

# 8. Clean up
rm /tmp/android-studio.tar.gz

echo "==========================================="
echo " Installation Complete!"
echo " Note: Ensure '$HOME/.local/bin' is in your PATH."
echo "==========================================="