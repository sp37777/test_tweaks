#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "===================================================="
echo "    Deemix GUI Installer for Linux Mint (2026)      "
echo "===================================================="

# 1. Install system prerequisites (git and curl are required for the build)
echo "--> Checking and installing basic system utilities..."
sudo apt update && sudo apt install -y git curl libpixman-1-dev libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev librsvg2-dev

# 2. Use NVM to manage an isolated Node.js environment (prevents Mint system conflicts)
echo "--> Setting up sandboxed Node.js environment via NVM..."
export NVM_DIR="$HOME/.nvm"
if [ ! -d "$NVM_DIR" ]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
fi

# Load NVM into this shell session
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Install Node 24 (Required by the bambanah monorepo)
nvm install 24
nvm use 24

# 3. Enable Corepack to fetch pnpm safely without global npm pollution
echo "--> Enabling pnpm via Node Corepack..."
corepack enable
corepack prepare pnpm@latest --activate

# 4. Clone the repository into a temporary build location
BUILD_DIR=$(mktemp -d)
echo "--> Cloning latest bambanah/deemix source code to $BUILD_DIR..."
git clone --depth=1 https://github.com/bambanah/deemix.git "$BUILD_DIR"
cd "$BUILD_DIR"

# 5. Build and package the Electron application
echo "--> Installing project dependencies (this may take a few minutes)..."
pnpm install

echo "--> Compiling components and packaging Electron GUI..."
pnpm build
pnpm --filter gui package:linux

# 6. Install the compiled binary to the local user space
echo "--> Deploying compiled application to ~/.local/bin..."
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.local/share/applications"
mkdir -p "$HOME/.local/share/icons"

# Locate the compiled output directory
DIST_DIR=$(find "$BUILD_DIR/packages/gui/out" -maxdepth 2 -type d -name "deemix-gui-linux-*" | head -n 1)

if [ -z "$DIST_DIR" ]; then
    echo "Error: Could not locate compiled Linux distribution directory."
    exit 1
fi

# Move binaries to a permanent user-space directory
TARGET_DIR="$HOME/.local/share/deemix-gui"
rm -rf "$TARGET_DIR"
cp -r "$DIST_DIR" "$TARGET_DIR"

# Create a symlink to make it executable from path
ln -sf "$TARGET_DIR/deemix-gui" "$HOME/.local/bin/deemix-gui"

# Fetch a temporary placeholder icon for the app menu
curl -s -o "$HOME/.local/share/icons/deemix.png" https://raw.githubusercontent.com/bambanah/deemix/main/packages/webui/public/favicon.png

# 7. Create a compliant Linux Desktop entry launcher
echo "--> Creating Mint Application Menu Entry..."
cat << EOF > "$HOME/.local/share/applications/deemix.desktop"
[Desktop Entry]
Name=Deemix GUI
Exec=$HOME/.local/bin/deemix-gui %U
Terminal=false
Type=Application
Icon=deemix
Categories=AudioVideo;Audio;Network;
Comment=Download music tracks from Deezer streams.
StartupWMClass=deemix-gui
EOF

# 8. Clean up build artifacts
echo "--> Cleaning up compiler storage..."
rm -rf "$BUILD_DIR"

echo "===================================================="
echo " SUCCESS: Deemix GUI has been installed!"
echo " You can find it in your Mint Start Menu under Audio/Video."
echo " Note: If it doesn't appear immediately, restart your panel or log out/in."
echo "===================================================="
