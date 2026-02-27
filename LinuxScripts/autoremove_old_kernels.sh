#!/bin/bash
sudo apt autoremove -yq --purge
echo 'Unattended-Upgrade::Remove-New-Unused-Dependencies "true";' | sudo tee -a /etc/apt/apt.conf.d/53unattended-upgrades-local
