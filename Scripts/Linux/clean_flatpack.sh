#!/bin/bash
flatpak pin | xargs -I {} flatpak pin --remove {} && flatpak uninstall --unused
