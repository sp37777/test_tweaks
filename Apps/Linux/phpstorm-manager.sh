#!/usr/bin/env bash

set -e

# URL для завантаження останньої версії PhpStorm (Linux, 64-bit)
PHPSTORM_URL="https://data.services.jetbrains.com/products/download?code=PS&latest=true&platform=linux"
INSTALL_DIR="/opt/phpstorm"
BIN_LINK="/usr/local/bin/phpstorm"
DESKTOP_FILE="$HOME/.local/share/applications/phpstorm.desktop"
UPDATE_CMD="/usr/local/bin/phpstorm-update"
VERSION_FILE="$INSTALL_DIR/.version"

# --- Деінсталяція ---
uninstall_phpstorm() {
    echo "==> Видаляємо PhpStorm..."

    if [ -d "$INSTALL_DIR" ]; then
        sudo rm -rf "$INSTALL_DIR"
        echo "Видалено каталог $INSTALL_DIR"
    fi

    if [ -L "$BIN_LINK" ] || [ -f "$BIN_LINK" ]; then
        sudo rm -f "$BIN_LINK"
        echo "Видалено симлінк $BIN_LINK"
    fi

    if [ -f "$DESKTOP_FILE" ]; then
        rm -f "$DESKTOP_FILE"
        echo "Видалено desktop-файл $DESKTOP_FILE"
        update-desktop-database ~/.local/share/applications || true
    fi

    if [ -f "$UPDATE_CMD" ]; then
        sudo rm -f "$UPDATE_CMD"
        echo "Видалено команду $UPDATE_CMD"
    fi

    echo "✅ PhpStorm успішно видалено."
    exit 0
}

# --- Обробка ключів ---
if [[ "$1" == "--uninstall" || "$1" == "-u" ]]; then
    uninstall_phpstorm
fi

# --- Отримати останню версію ---
get_latest_version() {
    curl -sI "$PHPSTORM_URL" | grep -i "location:" | sed -E 's/.*PhpStorm-([0-9.]+)\.tar\.gz.*/\1/i' | tr -d '\r'
}

# --- Встановлення / оновлення ---
install_phpstorm() {
    local VERSION="$1"
    echo "==> Завантаження PhpStorm $VERSION ..."
    TMPFILE=$(mktemp)
    wget -q --show-progress -O "$TMPFILE" "$PHPSTORM_URL"

    echo "==> Встановлення в $INSTALL_DIR ..."
    sudo rm -rf "$INSTALL_DIR"
    sudo mkdir -p "$INSTALL_DIR"
    sudo tar -xzf "$TMPFILE" -C /opt
    # tarball створює теку PhpStorm-xxxx.x, перейменовуємо її у стабільну PhpStorm
    local TMP_DIR=$(tar -tzf "$TMPFILE" | head -1 | cut -f1 -d"/")
    sudo mv "/opt/$TMP_DIR" "$INSTALL_DIR"
    rm "$TMPFILE"

    echo "$VERSION" | sudo tee "$VERSION_FILE" >/dev/null

    # Симлінк на виконуваний скрипт
    echo "==> Створення симлінку $BIN_LINK ..."
    sudo rm -f "$BIN_LINK"
    sudo ln -s "$INSTALL_DIR/bin/phpstorm.sh" "$BIN_LINK"

    # Desktop файл
    echo "==> Створення desktop-файлу $DESKTOP_FILE ..."
    mkdir -p "$(dirname "$DESKTOP_FILE")"
    cat > "$DESKTOP_FILE" <<EOL
[Desktop Entry]
Name=PhpStorm
Exec=$BIN_LINK
Icon=$INSTALL_DIR/bin/phpstorm.png
Type=Application
Categories=Development;IDE;
Terminal=false
StartupNotify=true
EOL

    update-desktop-database ~/.local/share/applications || true

    echo "✅ PhpStorm $VERSION встановлено/оновлено."
}

# --- Основна логіка ---
LATEST_VERSION=$(get_latest_version)
INSTALLED_VERSION=""

if [ -d "$INSTALL_DIR" ] && [ -f "$VERSION_FILE" ]; then
    INSTALLED_VERSION=$(cat "$VERSION_FILE")
fi

if [ ! -d "$INSTALL_DIR" ]; then
    echo "🔄 PhpStorm не встановлено, встановлюємо останню версію..."
    install_phpstorm "$LATEST_VERSION"
elif [ "$LATEST_VERSION" = "$INSTALLED_VERSION" ]; then
    echo "✅ У вас вже найновіший PhpStorm ($INSTALLED_VERSION)"
else
    echo "🔄 Знайдено нову версію: $LATEST_VERSION (поточна: $INSTALLED_VERSION)"
    install_phpstorm "$LATEST_VERSION"
fi

# --- Створення / оновлення phpstorm-update ---
SCRIPT_PATH="$(realpath "$0")"
if [ "$SCRIPT_PATH" != "$UPDATE_CMD" ]; then
    sudo cp "$SCRIPT_PATH" "$UPDATE_CMD"
    sudo chmod +x "$UPDATE_CMD"
fi
