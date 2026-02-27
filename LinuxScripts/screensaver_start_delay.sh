#!/bin/bash
echo "Enter screensaver screen lock delay in seconds [600 (10 min)]"
read timeout
timeout=${timeout:-600}
gsettings set org.$DESKTOP_SESSION.desktop.session idle-delay "uint32 $timeout"
