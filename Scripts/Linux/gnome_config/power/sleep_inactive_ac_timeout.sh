#!/bin/bash
echo "Enter sleep inactive ac timeout in seconds [0]"
read timeout
timeout=${timeout:-0}
gsettings set org.$DESKTOP_SESSION.settings-daemon.plugins.power sleep-inactive-ac-timeout $timeout
