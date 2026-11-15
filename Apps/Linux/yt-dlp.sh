#!/bin/bash
set -e

echo "==========================================="
echo " Installing Latest yt-dlp to ~/.local/bin"
echo "==========================================="

# 1. Remove old apt version and install ffmpeg (requires sudo)
echo "-> Removing outdated apt version and installing ffmpeg..."
sudo apt remove -y yt-dlp
sudo apt update && sudo apt install -y ffmpeg curl

# 2. Create local bin directory if it doesn't exist
echo "-> Creating ~/.local/bin directory..."
mkdir -p ~/.local/bin

# 3. Download the latest official yt-dlp binary (no sudo needed)
echo "-> Downloading latest yt-dlp from GitHub..."
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o ~/.local/bin/yt-dlp

# 4. Make the binary executable
echo "-> Setting executable permissions..."
chmod a+rx ~/.local/bin/yt-dlp

# 5. Automatically detect system Download folder and set yt-dlp config
echo "-> Detecting system download folder and creating config..."
mkdir -p ~/.config/yt-dlp

DETECTED_DOWNLOAD_DIR=$(xdg-user-dir DOWNLOAD)

# Write both the path and the new naming template to the config file
cat << EOF > ~/.config/yt-dlp/config
-P "${DETECTED_DOWNLOAD_DIR}/yt-dlp"
-o "%(uploader)s - [%(upload_date)s] - %(title)s.%(ext)s"
EOF

echo "Config created: Default download path set to ${DETECTED_DOWNLOAD_DIR}/yt-dlp"
echo "Naming template set to: Channel - [Upload_Date] - Title.ext"

# 6. Verify or add ~/.local/bin to PATH
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo "-> Adding ~/.local/bin to your PATH..."
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    export PATH="$HOME/.local/bin:$PATH"
    echo "Notice: PATH updated. Please restart your terminal after this script finishes!"
fi

# 7. Verification
echo "==========================================="
echo "Success! Installation and configuration complete."
echo "Current version installed:"
~/.local/bin/yt-dlp --version
echo "==========================================="
echo "Tip: In the future, just run 'yt-dlp -U' (without sudo) to update."

