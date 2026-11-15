#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Configuration
REPO="Universal-Debloater-Alliance/universal-android-debloater-next-generation"
INSTALL_DIR="$HOME/.local/bin"
BINARY_NAME="uad-ng"
TARGET_PATH="$INSTALL_DIR/$BINARY_NAME"

ICON_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"
ICON_PATH="$ICON_DIR/uad-ng.png"
SHORTCUT_DIR="$HOME/.local/share/applications"
SHORTCUT_PATH="$SHORTCUT_DIR/uad-ng.desktop"

# Ensure local binary and asset directories exist
mkdir -p "$INSTALL_DIR"
mkdir -p "$ICON_DIR"
mkdir -p "$SHORTCUT_DIR"

# Provide a path warning if necessary
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo "Notice: $INSTALL_DIR is not currently in your system PATH environment variable."
fi

echo "Checking the latest version of UAD-ng on GitHub..."
LATEST_TAG=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$LATEST_TAG" ]; then
    echo "Error: Failed to fetch the release tag from the GitHub API repository." >&2
    exit 1
fi

# Strip 'v' from tag names for pure string comparison (e.g., v1.2.0 -> 1.2.0)
LATEST_VERSION="${LATEST_TAG#v}"
SHOULD_DOWNLOAD=true
FIRST_INSTALLATION=false

# Determine current local version if binary is present
if [ -f "$TARGET_PATH" ]; then
    if CURRENT_VERSION_RAW=$("$TARGET_PATH" --version 2>/dev/null || "$TARGET_PATH" -V 2>/dev/null); then
        CURRENT_VERSION=$(echo "$CURRENT_VERSION_RAW" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
    else
        CURRENT_VERSION=""
    fi

    if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
        echo "Universal Android Debloater Next Generation is already up to date (v$CURRENT_VERSION)."
        SHOULD_DOWNLOAD=false
    elif [ -n "$CURRENT_VERSION" ]; then
        echo "An update is available: v$CURRENT_VERSION -> $LATEST_TAG"
    else
        echo "UAD-ng file found, but its version output couldn't be parsed. Forcing update..."
    fi
else
    echo "UAD-ng is not currently installed. Initializing fresh installation..."
    FIRST_INSTALLATION=true
fi

# Execute download and file updates if version is missing or outdated
if [ "$SHOULD_DOWNLOAD" = true ]; then
    echo "Locating Linux platform asset inside release lists..."
    DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" \
        | grep "browser_download_url" \
        | grep -i "linux" \
        | grep -v -i "opengl" \
        | head -n 1 \
        | cut -d '"' -f 4)

    if [ -z "$DOWNLOAD_URL" ]; then
        echo "Error: No matching Linux target found in the latest release assets." >&2
        exit 1
    fi

    echo "Downloading $LATEST_TAG..."
    TMP_FILE=$(mktemp)
    curl -L -o "$TMP_FILE" "$DOWNLOAD_URL"
    mv "$TMP_FILE" "$TARGET_PATH"
    chmod +x "$TARGET_PATH"
    echo "Application binary successfully processed."
fi

if [ "$FIRST_INSTALLATION" = true ]; then
    sudo apt install -y adb

    # Icon & Desktop Integration (Runs even if binary is up to date to repair broken shortcuts)
    echo "Checking desktop shortcut integration..."

    # Download logo-dark.png (white text designed for dark panels/menus)
    ICON_URL="https://raw.githubusercontent.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation/main/resources/assets/logo-dark.png"
    if ! curl -sL -o "$ICON_PATH" "$ICON_URL"; then
        echo "Warning: Could not retrieve the repository icon asset file."
    fi

    # Write out the standard FreeDesktop menu specification profile
    cat << EOF > "$SHORTCUT_PATH"
[Desktop Entry]
Version=1.0
Type=Application
Name=Universal Android Debloater (Next Gen)
Comment=Debloat non-rooted Android devices using ADB
Exec=$TARGET_PATH
Icon=uad-ng
Terminal=false
Categories=Utility;Development;
Keywords=android;adb;debloat;cleanup;
EOF

    chmod +x "$SHORTCUT_PATH"

    # Refresh local application entry cache databases immediately
    if command -v update-desktop-database &> /dev/null; then
        update-desktop-database "$SHORTCUT_DIR"
    fi
fi

echo "Process completed! UAD-ng is accessible via your terminal launcher ($BINARY_NAME) or desktop application menus."
