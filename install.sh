#!/usr/bin/env bash
# macrift — one-line installer
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/emylfy/macrift/main/install.sh)

set -euo pipefail

REPO="https://github.com/emylfy/macrift.git"
INSTALL_DIR="$HOME/.macrift"
BIN_LINK="/usr/local/bin/macrift"

printf "\n  macrift installer\n\n"

# Check git
if ! command -v git &>/dev/null; then
    echo "  git not found. Installing Xcode CLI tools..."
    xcode-select --install 2>/dev/null || true
    echo "  Run this script again after installation finishes."
    exit 1
fi

# Clone or update
if [[ -d "$INSTALL_DIR" ]]; then
    echo "  Updating macrift..."
    git -C "$INSTALL_DIR" pull --rebase --autostash --quiet
else
    echo "  Cloning macrift..."
    git clone --quiet "$REPO" "$INSTALL_DIR"
fi

# Make executable
chmod +x "$INSTALL_DIR/macrift.sh"
chmod +x "$INSTALL_DIR"/**/*.sh 2>/dev/null || true

# Create global command
if [[ ! -L "$BIN_LINK" ]]; then
    echo "  Creating 'macrift' command..."
    sudo mkdir -p /usr/local/bin
    sudo ln -sf "$INSTALL_DIR/macrift.sh" "$BIN_LINK"
fi

printf "\n  Done! Run with: macrift\n\n"

# Launch
"$INSTALL_DIR/macrift.sh"
