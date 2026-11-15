#!/usr/bin/env bash

set -euo pipefail

# Кольори для зручного виводу в термінал
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}[1/4] Оновлення списків пакетів та встановлення Firejail...${NC}"
sudo apt update
sudo apt install -y firejail firetools

echo -e "${GREEN}[2/4] Налаштування підсистеми профілів Firejail...${NC}"
# Дозволяє використовувати стандартні AppArmor/Firejail профілі для застосунків
sudo firecfg --fix-sound || true

echo -e "${GREEN}[3/4] Створення яскравого ярлика у меню 'Пуск'...${NC}"

# Створюємо директорію для користувацьких ярликів, якщо її немає
mkdir -p "$HOME/.local/share/applications"

# Створення .desktop файлу для GUI GUI-GUI утиліти Firetools / Firejail
cat <<EOF > "$HOME/.local/share/applications/firejail-launcher.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Firejail Sandbox Manager
GenericName=Sandbox Launcher
Comment=Управління та запуск програм у ізольованій пісочниці
Exec=firetools
Icon=firetools
Terminal=false
Categories=System;Security;Settings;
Keywords=sandbox;security;isolation;firejail;
StartupNotify=true
EOF

# Створення додаткового ярлика для запусків довільних команд у пісочниці через термінал
cat <<EOF > "$HOME/.local/share/applications/firejail-terminal.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Firejail Terminal
GenericName=Sandboxed Terminal
Comment=Запуск нового терміналу всередині ізольованої пісочниці
Exec=x-terminal-emulator -e firejail
Icon=utilities-terminal
Terminal=false
Categories=System;Security;
Keywords=sandbox;terminal;bash;
StartupNotify=true
EOF

echo -e "${GREEN}[4/4] Оновлення бази даних ярликів столу...${NC}"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

echo -e "\n${GREEN}Встановлення завершено успішно!${NC}"
echo "Ярлики 'Firejail Sandbox Manager' та 'Firejail Terminal' додано у категорію 'Системні' в меню Пуск."
