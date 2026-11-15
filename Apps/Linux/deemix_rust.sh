#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "===================================================="
echo "    Deerix (Rust CLI) Installer for Linux Mint       "
echo "===================================================="

# 1. Setup local bin directory if it doesn't exist
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.config/deerix"

# 2. Detect system architecture
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    echo "Error: This automated script currently supports x86_64 architecture."
    exit 1
fi

# 3. Fetch latest binary version info from GitLab release API
echo "--> Fetching latest release information..."
LATEST_TAG=$(curl -s "https://gitlab.com/api/v4/projects/kowaczek%2Fdeerix/releases" | grep -oP '"tag_name":"\K[^"]+' | head -n 1)

if [ -z "$LATEST_TAG" ]; then
    # Fallback to a verified stable version string if API lookup fails
    LATEST_TAG="v0.5.5" 
fi

echo "--> Latest version found: $LATEST_TAG"

# 4. Download the self-contained Linux executable binary
echo "--> Downloading compiled Rust binary..."
DOWNLOAD_URL="https://gitlab.com/kowaczek/deerix/-/releases/${LATEST_TAG}/downloads/deerix-linux-x86_64"

# Safe download to a temporary file
TEMP_BIN=$(mktemp)
curl -L -s -o "$TEMP_BIN" "$DOWNLOAD_URL"

# 5. Deploy binary to local user space
echo "--> Deploying binary to ~/.local/bin/deerix..."
mv "$TEMP_BIN" "$HOME/.local/bin/deerix"
chmod +x "$HOME/.local/bin/deerix"

# 6. Generate a basic configuration skeleton if it doesn't exist
CONFIG_FILE="$HOME/.config/deerix/deerix_settings.toml"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "--> Creating default configuration file..."
    cat << EOF > "$CONFIG_FILE"
# Deerix Configuration
download_path = "$HOME/Music"
bitrate = "FLAC" # Options: MP3_128, MP3_320, FLAC

[auth]
# Paste your Deezer ARL cookie string below
arl = ""
EOF
    echo "    Created: $CONFIG_FILE"
fi

echo "===================================================="
echo " SUCCESS: Deerix CLI has been installed!"
echo " Location: ~/.local/bin/deerix"
echo "===================================================="
echo " To use it:"
echo " 1. Open ~/.config/deerix/deerix_settings.toml and paste your ARL."
echo " 2. Run in terminal: deerix \"<deezer_link_here>\""
echo "===================================================="
