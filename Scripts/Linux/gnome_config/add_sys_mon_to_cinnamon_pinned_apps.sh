#!/bin/bash
jq '."pinned-apps"."value"[."pinned-apps"."value"| length] |= . + "gnome-system-monitor.desktop"' ~/.config/cinnamon/spices/grouped-window-list@cinnamon.org/2.json | sponge ~/.config/cinnamon/spices/grouped-window-list@cinnamon.org/2.json
cinnamon --replace & disown