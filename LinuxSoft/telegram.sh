#!/bin/bash
wget https://telegram.org/dl/desktop/linux -O linux.tar
sudo tar xJf linux.tar -C /opt/
sudo ln -s /opt/Telegram/Telegram /usr/local/bin/telegram-desktop
rm linux.tar
telegram-desktop
