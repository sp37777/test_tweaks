#!/bin/bash

# Path to the aliases file
ALIAS_FILE="$HOME/.bash_aliases"

# The function snippet to add
read -r -d '' SNIPPET << 'EOF'
dockercrmphp() {
    docker-compose exec -w /var/www php-fpm "$@"
}
dockercrmcomposer() {
    docker-compose exec php-fpm composer "$@"
}

EOF

# Create the file if it doesn't exist
if [ ! -f "$ALIAS_FILE" ]; then
    echo "# ~/.bash_aliases file created by setup script" > "$ALIAS_FILE"
    echo "Created $ALIAS_FILE"
fi

# Check if snippet is already in the file
if ! grep -q "dockerphp()" "$ALIAS_FILE"; then
    echo "" >> "$ALIAS_FILE"
    echo "$SNIPPET" >> "$ALIAS_FILE"
    echo "Added dockerphp() function to $ALIAS_FILE"
else
    echo "dockerphp() function already exists in $ALIAS_FILE"
fi

# Reload bash configuration
if [ -f "$HOME/.bashrc" ]; then
    # Ensure .bash_aliases is sourced
    if ! grep -q "\.bash_aliases" "$HOME/.bashrc"; then
        echo "[ -f ~/.bash_aliases ] && . ~/.bash_aliases" >> "$HOME/.bashrc"
        echo "Added source line for .bash_aliases in .bashrc"
    fi
    # Source immediately
    . "$HOME/.bash_aliases"
    echo "Reloaded ~/.bash_aliases"
fi
