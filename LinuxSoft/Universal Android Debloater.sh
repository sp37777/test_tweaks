#!/bin/bash
sudo apt install -y android-sdk-platform-tools
wget https://github.com/0x192/universal-android-debloater/releases/download/0.5.1/uad_gui-noselfupdate-linux-opengl.tar.gz -O uad.tar.gz
sudo mkdir /opt/UAD
sudo tar xzf "uad.tar.gz" -C /opt/UAD
sudo ln -s /opt/UAD/uad_gui-noselfupdate-linux-opengl /usr/local/bin/uad_gui
rm uad.tar.gz
sudo tee -a /usr/share/applications/uad_gui.desktop > /dev/null <<EOT
[Desktop Entry]
Name=Universal Android Debloater
Comment=improve privacy and battery performance by removing unnecessary and obscure system apps
Exec=/opt/UAD/uad_gui-noselfupdate-linux-opengl %u
Path=/opt/UAD/
Terminal=false
Type=Application
EOT
