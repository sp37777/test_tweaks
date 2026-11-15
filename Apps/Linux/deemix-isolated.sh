
#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="ghcr.io/bambanah/deemix:latest"
CONTAINER="deemix-isolated"
PORT="6595"

BIN_DIR="$HOME/.local/bin"
APP_DIR="$HOME/.local/share/applications"
CONFIG_DIR="$HOME/.config/deemix"
DOWNLOAD_DIR="$HOME/deemix_downloads"
STATE_DIR="$HOME/.local/state/deemix"
LOG_FILE="$STATE_DIR/start.log"

PUID=1000
PGID=1000

echo "===================================================="
echo "      Deemix Isolated Suite Installer (Podman)      "
echo "===================================================="

# Do not run the installer as root.
if [[ $EUID -eq 0 ]]; then
    echo "ERROR: Run this installer as your normal user, without sudo."
    exit 1
fi

# 1. Check/install Podman.
if ! command -v podman >/dev/null 2>&1; then
    echo "Podman is not installed."
    read -r -p "Install Podman using APT? [y/N] " answer
    case "$answer" in
        y|Y|yes|YES)
            sudo apt-get update
            sudo apt-get install -y podman
            ;;
        *)
            echo "Installation cancelled."
            exit 1
            ;;
    esac
fi

# 2. Verify rootless UID/GID mappings before touching any files.
USER_NAME="$(id -un)"
USER_ID="$(id -u)"

check_subid_file() {
    local file="$1"

    if ! awk -F: -v u="$USER_NAME" -v uid="$USER_ID" '
        ($1 == u || $1 == uid) { total += $3 }
        END { exit !(total >= 65536) }
    ' "$file"; then
        echo "ERROR: $file has no suitable subordinate ID range"
        echo "for user $USER_NAME (UID $USER_ID)."
        echo "Fix rootless Podman configuration before continuing."
        exit 1
    fi
}

check_subid_file /etc/subuid
check_subid_file /etc/subgid

echo "--> Checking rootless Podman..."
if ! podman unshare true; then
    echo "ERROR: Podman user namespace is not working."
    echo "No application files have been modified by this installer."
    exit 1
fi

# 3. Download the image now, not on every application start.
echo "--> Downloading/checking Deemix image..."
podman pull "$IMAGE"

# 4. Prepare directories only after prerequisites pass.
echo "--> Preparing local directories..."
mkdir -p "$BIN_DIR" "$APP_DIR" "$CONFIG_DIR" \
         "$DOWNLOAD_DIR" "$STATE_DIR"

# Ensure bind-mounted files belong to the intended container UID/GID.
echo "--> Preparing rootless volume permissions..."
podman unshare chown -R "$PUID:$PGID" \
    "$CONFIG_DIR" "$DOWNLOAD_DIR"

# 5. Generate start script.
echo "--> Generating startup script..."
cat > "$BIN_DIR/start_deemix.sh" << START_EOF
#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p "$CONFIG_DIR" "$DOWNLOAD_DIR" "$STATE_DIR"
exec >> "$LOG_FILE" 2>&1

echo
echo "=== Deemix startup: \$(date) ==="

if ! podman unshare true; then
    echo "ERROR: Rootless Podman namespace is unavailable."
    exit 1
fi

if ! podman image exists "$IMAGE"; then
    echo "Image is missing; downloading it..."
    podman pull "$IMAGE"
fi

podman unshare chown -R "$PUID:$PGID" \
    "$CONFIG_DIR" "$DOWNLOAD_DIR"

podman run -d \
    --replace \
    --name "$CONTAINER" \
    -e PUID="$PUID" \
    -e PGID="$PGID" \
    -p 127.0.0.1:$PORT:$PORT \
    -v "$DOWNLOAD_DIR:/downloads:Z" \
    -v "$CONFIG_DIR:/config:Z" \
    "$IMAGE"

xdg-open "http://localhost:$PORT" >/dev/null 2>&1 &
echo "Deemix start command completed."
START_EOF

# 6. Generate stop script.
echo "--> Generating shutdown script..."
cat > "$BIN_DIR/stop_deemix.sh" << STOP_EOF
#!/usr/bin/env bash
set -u

if podman container exists $CONTAINER; then
    if podman stop $CONTAINER; then
        echo "Deemix stopped."
    else
        echo "ERROR: Could not stop Deemix."
        exit 1
    fi
else
    echo "Deemix container does not exist."
fi
STOP_EOF

# 7. Generate update script.
echo "--> Generating manual update script..."
cat > "$BIN_DIR/update_deemix.sh" << UPD_EOF
#!/usr/bin/env bash

if podman pull "$IMAGE"; then
    echo
    echo "SUCCESS: Deemix image updated successfully."
    echo "The new image will be used the next time"
    echo "Start Deemix recreates the container."
else
    status=\$?
    echo
    echo "ERROR: Deemix image update failed (exit code \$status)."
    echo "The previously downloaded image has not been"
    echo "intentionally removed."
fi

echo
read -r -p "Press Enter to close this window..."
UPD_EOF

chmod +x "$BIN_DIR/start_deemix.sh" "$BIN_DIR/stop_deemix.sh" "$BIN_DIR/update_deemix.sh"

# 8. Create application launchers.
echo "--> Creating Start Menu entries..."

cat > "$APP_DIR/deemix-start.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Start Deemix (Isolated)
Comment=Launch Deemix and open its local web interface
Exec=$BIN_DIR/start_deemix.sh
Icon=network-server
Categories=AudioVideo;Audio;Network;
Terminal=false
EOF

cat > "$APP_DIR/deemix-stop.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Stop Deemix (Isolated)
Comment=Stop the Deemix container
Exec=$BIN_DIR/stop_deemix.sh
Icon=process-stop
Categories=AudioVideo;Audio;Network;
Terminal=true
EOF

cat > "$APP_DIR/deemix-update.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Update Deemix
Comment=Manually download the latest Deemix image
Exec=$BIN_DIR/update_deemix.sh
Icon=system-software-update
Categories=AudioVideo;Audio;Network;
Terminal=true
EOF

chmod 644 "$APP_DIR/deemix-start.desktop" "$APP_DIR/deemix-stop.desktop" "$APP_DIR/deemix-update.desktop"

echo "===================================================="
echo " SUCCESS: Deemix Suite is installed!"
echo " Image: $IMAGE"
echo " Web UI: http://localhost:$PORT"
echo " Startup log: $STATE_DIR/start.log"
echo " Start Menu: Sound & Video"
echo "===================================================="
