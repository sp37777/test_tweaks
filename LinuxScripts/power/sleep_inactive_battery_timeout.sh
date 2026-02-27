#!/bin/bash
echo "Enter sleep inactive battery timeout in seconds [900 (15 min)]"
read timeout
timeout=${timeout:-900}
gsettings set org.$DESKTOP_SESSION.settings-daemon.plugins.power sleep-inactive-battery-timeout $timeout
