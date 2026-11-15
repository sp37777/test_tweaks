#!/bin/bash

# --- Simple terminal sudo elevation ---
if [[ $EUID -ne 0 ]]; then
    echo "This script needs root privileges."
    echo "Requesting sudo access..."
    exec sudo bash "$0" "$@"
fi

# --- Original script below ---
set -e

# Function to list available ext4 drives except the current OS drive
list_ext4_drives() {
    ROOT_PART=$(findmnt / -o SOURCE -n)
    lsblk -o NAME,FSTYPE,MOUNTPOINT -l | grep "ext4" | awk '{print "/dev/"$1}' | grep -v "$ROOT_PART"
}

# Function to list available Bluetooth adapters
list_adapters() {
    hcitool dev | grep -Eo '([[:xdigit:]]{2}[:]){5}[[:xdigit:]]{2}' || echo "No Bluetooth adapters found."
}

# Get the currently selected default adapter
get_default_adapter() {
    bluetoothctl show | grep 'Controller' | awk '{print $2}'
}

AVAILABLE_ADAPTERS=$(list_adapters)
if [ "$AVAILABLE_ADAPTERS" == "No Bluetooth adapters found." ]; then
    echo "No Bluetooth adapters found!"
    exit 1
fi

DEFAULT_ADAPTER=$(get_default_adapter)
echo "Available Bluetooth Adapters:"
i=1
for ADAPTER in $AVAILABLE_ADAPTERS; do
    if [ "$ADAPTER" == "$DEFAULT_ADAPTER" ]; then
        echo "$i) $ADAPTER (default)"
    else
        echo "$i) $ADAPTER"
    fi
    ((i++))
done

echo -n "Select an adapter by number (default is $DEFAULT_ADAPTER): "
read -r ADAPTER_NUM
if ! [[ "$ADAPTER_NUM" =~ ^[0-9]+$ ]] || [ "$ADAPTER_NUM" -lt 1 ] || [ "$ADAPTER_NUM" -gt "$i" ]; then
    echo "Invalid selection, defaulting to $DEFAULT_ADAPTER."
    SELECTED_ADAPTER=$DEFAULT_ADAPTER
else
    SELECTED_ADAPTER=$(echo "$AVAILABLE_ADAPTERS" | sed -n "${ADAPTER_NUM}p")
fi

echo "Selected adapter: $SELECTED_ADAPTER"

echo "Paired or Connected devices under $SELECTED_ADAPTER:"
ALL_DEVICES=$(bluetoothctl devices | awk '{print $2}')
if [ -z "$ALL_DEVICES" ]; then
    echo "No paired or connected devices found."
    exit 1
fi

echo "Available devices:"
i=1
for DEVICE_MAC in $ALL_DEVICES; do
    DEVICE_NAME=$(bluetoothctl info "$DEVICE_MAC" | grep "Name" | cut -d " " -f 2-)
    echo "$i) $DEVICE_MAC - $DEVICE_NAME"
    ((i++))
done

echo -n "Select a device by number (default is 1): "
read -r DEVICE_NUM
if ! [[ "$DEVICE_NUM" =~ ^[0-9]+$ ]] || [ "$DEVICE_NUM" -lt 1 ] || [ "$DEVICE_NUM" -gt "$i" ]; then
    echo "Invalid selection, defaulting to the first device."
    DEVICE_NUM=1
fi

SELECTED_DEVICE_MAC=$(echo "$ALL_DEVICES" | sed -n "${DEVICE_NUM}p")
SELECTED_DEVICE_NAME=$(bluetoothctl info "$SELECTED_DEVICE_MAC" | grep "Name" | cut -d " " -f 2-)
echo "Selected device: $SELECTED_DEVICE_MAC - $SELECTED_DEVICE_NAME"

AVAILABLE_DRIVES=$(list_ext4_drives)
if [ -z "$AVAILABLE_DRIVES" ]; then
    echo "No available ext4 drives found! Please ensure the destination drive is mounted."
    exit 1
fi

echo "Available ext4 drives (excluding the current OS drive):"
i=1
for DRIVE in $AVAILABLE_DRIVES; do
    echo "$i) $DRIVE"
    ((i++))
done

echo -n "Select a destination drive by number: "
read -r DRIVE_NUM
if ! [[ "$DRIVE_NUM" =~ ^[0-9]+$ ]] || [ "$DRIVE_NUM" -lt 1 ] || [ "$DRIVE_NUM" -gt "$i" ]; then
    echo "Invalid selection."
    exit 1
fi

SELECTED_DRIVE=$(echo "$AVAILABLE_DRIVES" | sed -n "${DRIVE_NUM}p")
echo "Selected destination drive: $SELECTED_DRIVE"

TEMP_MOUNT="/mnt/usb_mount"
echo "Mounting the selected drive at $TEMP_MOUNT..."
mkdir -p "$TEMP_MOUNT"
mount "$SELECTED_DRIVE" "$TEMP_MOUNT"

SOURCE_DIR="/var/lib/bluetooth/$SELECTED_ADAPTER/$SELECTED_DEVICE_MAC"
if [ ! -f "$SOURCE_DIR/info" ]; then
    echo "Error: The source device's LinkKey (info file) does not exist."
    umount "$TEMP_MOUNT"
    exit 1
fi

DEST_LINKKEY="$TEMP_MOUNT/var/lib/bluetooth/$SELECTED_ADAPTER/$SELECTED_DEVICE_MAC/info"
mkdir -p "$(dirname "$DEST_LINKKEY")"
cp "$SOURCE_DIR/info" "$DEST_LINKKEY"

echo "Successfully copied the LinkKey to $DEST_LINKKEY."
umount "$TEMP_MOUNT"
echo "Unmounted $TEMP_MOUNT."
echo "Done."
# Pause only if not running in an interactive terminal
if [ ! -t 0 ]; then
    echo
    read -rp "Press Enter to close..."
fi