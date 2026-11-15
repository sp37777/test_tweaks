#!/bin/bash
apt --fix-broken install
sudo wget https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg -O /usr/share/keyrings/vscodium-archive-keyring.asc
echo 'deb [ signed-by=/usr/share/keyrings/vscodium-archive-keyring.asc ] https://paulcarroty.gitlab.io/vscodium-deb-rpm-repo/debs vscodium main' | sudo tee /etc/apt/sources.list.d/vscodium.list
sudo apt update
sudo apt install -y codium
codium --install-extension ms-ceintl.vscode-language-pack-uk
jq '."pinned-apps"."value"[."pinned-apps"."value"| length] |= . + "codium.desktop"' ~/.config/cinnamon/spices/grouped-window-list@cinnamon.org/2.json | sponge ~/.config/cinnamon/spices/grouped-window-list@cinnamon.org/2.json
cinnamon --replace & disown