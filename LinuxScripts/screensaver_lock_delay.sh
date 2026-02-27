#!/bin/bash
echo "Enter screensaver screen lock delay in seconds [60 (1 min)]"
read timeout
timeout=${timeout:-60}
gsettings set org.$DESKTOP_SESSION.desktop.screensaver lock-delay "uint32 $timeout"
