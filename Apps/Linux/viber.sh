#!/bin/bash
wget https://download.cdn.viber.com/cdn/desktop/Linux/viber.deb
sudo dpkg -i viber.deb
rm viber.deb
jq '."pinned-apps"."value"[."pinned-apps"."value"| length] |= . + "viber.desktop"' ~/.config/cinnamon/spices/grouped-window-list@cinnamon.org/2.json | sponge ~/.config/cinnamon/spices/grouped-window-list@cinnamon.org/2.json
cinnamon --replace & disown