#!/usr/bin/env bash
# macrift — one-line installer
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/emylfy/macrift/main/install.sh)
# Works on a fresh macOS — no dependencies required (git, brew, etc.)

set -euo pipefail

REPO="https://github.com/emylfy/macrift.git"
REPO_TAR="https://github.com/emylfy/macrift/archive/main.tar.gz"
INSTALL_DIR="$HOME/.macrift"
BIN_LINK="/usr/local/bin/macrift"

BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[38;5;39m'
RED='\033[0;31m'

info()  { printf '  %b›%b  %s\n' "$CYAN"   "$RESET" "$1"; }
ok()    { printf '  %b✓%b  %s\n' "$GREEN"  "$RESET" "$1"; }
warn()  { printf '  %b!%b  %s\n' "$YELLOW" "$RESET" "$1"; }
err()   { printf '  %b✗%b  %s\n' "$RED"    "$RESET" "$1"; }

ask() {
    printf '  %b%s%b %b[y/n]%b ' "$YELLOW" "$1" "$RESET" "$DIM" "$RESET"
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

# macOS check
if [[ "$(uname)" != "Darwin" ]]; then
    err "macrift is for macOS only"
    exit 1
fi

printf '\n  %bmacrift installer%b\n\n' "$BOLD" "$RESET"

# Xcode Command Line Tools
if ! xcode-select -p &>/dev/null; then
    warn "Xcode Command Line Tools not found"
    if ask "Install? (provides git & developer tools)"; then
        xcode-select --install 2>/dev/null || true
        printf '  %bwaiting for installation...%b' "$DIM" "$RESET"
        until xcode-select -p &>/dev/null; do
            printf '.'
            sleep 5
        done
        printf '\n'
        ok "Xcode Command Line Tools installed"
    else
        info "Skipped — will download archive instead of git clone"
    fi
fi

# Download / Update
if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "Updating macrift..."
    git -C "$INSTALL_DIR" pull --rebase --autostash --quiet
    ok "Updated"
elif command -v git &>/dev/null; then
    [[ -d "$INSTALL_DIR" ]] && rm -rf "$INSTALL_DIR"
    info "Cloning macrift..."
    git clone --quiet "$REPO" "$INSTALL_DIR"
    ok "Cloned → $INSTALL_DIR"
else
    info "Downloading macrift..."
    tmp="$(mktemp -d)"
    curl -fsSL "$REPO_TAR" | tar -xz -C "$tmp"
    [[ -d "$INSTALL_DIR" ]] && rm -rf "$INSTALL_DIR"
    mv "$tmp/macrift-main" "$INSTALL_DIR"
    rm -rf "$tmp"
    ok "Downloaded → $INSTALL_DIR"
fi

# Permissions
chmod +x "$INSTALL_DIR/macrift.sh"
find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} +

# Global command
if [[ ! -L "$BIN_LINK" || "$(readlink "$BIN_LINK" 2>/dev/null)" != "$INSTALL_DIR/macrift.sh" ]]; then
    printf '\n'
    if ask "Create global 'macrift' command? (needs sudo)"; then
        sudo mkdir -p /usr/local/bin
        sudo ln -sf "$INSTALL_DIR/macrift.sh" "$BIN_LINK"
        ok "Run from anywhere: macrift"
    else
        info "Skipped — run directly: ~/.macrift/macrift.sh"
    fi
fi

printf '\n  %bDone!%b\n\n' "$GREEN" "$RESET"

# Launch
"$INSTALL_DIR/macrift.sh"
