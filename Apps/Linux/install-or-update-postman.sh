#!/usr/bin/env bash

set -e

POSTMAN_URL="https://dl.pstmn.io/download/latest/linux_64"
INSTALL_DIR="/opt/postman"
BIN_LINK="/usr/local/bin/postman"
DESKTOP_FILE="$HOME/.local/share/applications/postman.desktop"
UPDATE_CMD="/usr/local/bin/postman-update"
VERSION_FILE="$INSTALL_DIR/.version"

# --- Функція деінсталяції ---
uninstall_postman() {
    echo "==> Видаляємо Postman..."

    # Видаляємо каталог
    if [ -d "$INSTALL_DIR" ]; then
        sudo rm -rf "$INSTALL_DIR"
        echo "Видалено каталог $INSTALL_DIR"
    fi

    # Видаляємо симлінк
    if [ -L "$BIN_LINK" ] || [ -f "$BIN_LINK" ]; then
        sudo rm -f "$BIN_LINK"
        echo "Видалено симлінк $BIN_LINK"
    fi

    # Видаляємо desktop-файл
    if [ -f "$DESKTOP_FILE" ]; then
        rm -f "$DESKTOP_FILE"
        echo "Видалено desktop-файл $DESKTOP_FILE"
        update-desktop-database ~/.local/share/applications || true
    fi

    # Видаляємо команду оновлення
    if [ -f "$UPDATE_CMD" ]; then
        sudo rm -f "$UPDATE_CMD"
        echo "Видалено команду $UPDATE_CMD"
    fi

    echo "✅ Postman успішно видалено."
    exit 0
}

# --- Обробка ключів ---
if [[ "$1" == "--uninstall" || "$1" == "-u" ]]; then
    uninstall_postman
fi

# --- Функція отримання останньої версії ---
get_latest_version() {
    curl -sI "$POSTMAN_URL" | grep -i "location:" | sed -E 's/.*Postman-linux-x64-(.*).tar.gz.*/\1/i' | tr -d '\r'
}

# --- Встановлення / оновлення ---
install_postman() {
    local VERSION="$1"
    echo "==> Завантаження Postman $VERSION ..."
    TMPFILE=$(mktemp)
    wget -q --show-progress "$POSTMAN_URL" -O "$TMPFILE"

    echo "==> Встановлення в $INSTALL_DIR ..."
    sudo rm -rf "$INSTALL_DIR"
    sudo mkdir -p "$INSTALL_DIR"
    sudo tar -xzf "$TMPFILE" -C /opt
    sudo mv /opt/Postman "$INSTALL_DIR"
    rm "$TMPFILE"

    # Записуємо версію
    echo "$VERSION" | sudo tee "$VERSION_FILE" >/dev/null

    # Симлінк на виконуваний файл
    echo "==> Створення симлінку $BIN_LINK ..."
    sudo rm -f "$BIN_LINK"
    sudo ln -s "$INSTALL_DIR/Postman/Postman" "$BIN_LINK"

    # Створення desktop-файлу
    echo "==> Створення desktop-файлу $DESKTOP_FILE ..."
    mkdir -p "$(dirname "$DESKTOP_FILE")"
    cat > "$DESKTOP_FILE" <<EOL
[Desktop Entry]
Name=Postman
Exec=$BIN_LINK
Icon=$INSTALL_DIR/Postman/app/resources/app/assets/icon.png
Type=Application
Categories=Development;Utility;
Terminal=false
StartupNotify=true
EOL

    # Оновлення кешу меню
    update-desktop-database ~/.local/share/applications || true

    echo "✅ Postman $VERSION встановлено/оновлено."
}

# --- Основна логіка ---
LATEST_VERSION=$(get_latest_version)

# Перевірка наявності нових версій і встановлення чи оновлення за потреби
if [ ! -d "$INSTALL_DIR" ]; then
    echo "🔄 Postman не встановлено, встановлюємо останню версію..."
    install_postman "$LATEST_VERSION"
elif [ -f "$VERSION_FILE" ]; then
    INSTALLED_VERSION=$(cat "$VERSION_FILE")
    if [ "$LATEST_VERSION" = "$INSTALLED_VERSION" ]; then
        echo "✅ У вас вже найновіший Postman ($INSTALLED_VERSION)"
    else
        echo "🔄 Знайдено нову версію: $LATEST_VERSION (поточна: $INSTALLED_VERSION)"
        install_postman "$LATEST_VERSION"
    fi
else
    # каталог є, але файла .version немає
    echo "⚠️ Файл версії відсутній, перевстановлюємо Postman..."
    install_postman "$LATEST_VERSION"
fi

# --- Створення / оновлення postman-update ---
SCRIPT_PATH="$(realpath "$0")"
if [ "$SCRIPT_PATH" != "$UPDATE_CMD" ]; then
    sudo cp "$SCRIPT_PATH" "$UPDATE_CMD"
    sudo chmod +x "$UPDATE_CMD"
fi
