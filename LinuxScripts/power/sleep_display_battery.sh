#!/bin/bash
echo "Enter sleep display battery timeout in seconds [300 (5 min)]"
read timeout
timeout=${timeout:-300}
gsettings set org.$DESKTOP_SESSION.settings-daemon.plugins.power sleep-display-battery $timeout
