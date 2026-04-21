#!/usr/bin/env bash
# macrift — one-line installer
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/emylfy/macrift/main/install.sh)
# Works on a fresh macOS — only needs curl (built-in). No git, no Xcode CLT.

set -euo pipefail

REPO_TAR="https://github.com/emylfy/macrift/archive/main.tar.gz"
INSTALL_DIR="$HOME/.macrift"
LOCAL_BIN="$HOME/.local/bin"

BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[38;5;39m'
RED='\033[0;31m'

info()  { printf '  %b›%b  %s\n' "$CYAN"   "$RESET" "$1"; }
ok()    { printf '  %b✓%b  %s\n' "$GREEN"  "$RESET" "$1"; }
err()   { printf '  %b✗%b  %s\n' "$RED"    "$RESET" "$1"; }

ask() {
    printf '  %b%s%b %b[y/n]%b ' "$YELLOW" "$1" "$RESET" "$DIM" "$RESET"
    read -r answer </dev/tty
    [[ "$answer" =~ ^[Yy]$ ]]
}

if [[ "$(uname)" != "Darwin" ]]; then
    err "macrift is for macOS only"
    exit 1
fi

printf '\n  %bmacrift installer%b\n\n' "$BOLD" "$RESET"

# Download
info "Downloading macrift..."
tmp="$(mktemp -d)"
if curl -fsSL "$REPO_TAR" | tar -xz -C "$tmp"; then
    # Atomic swap: backup old → move new → remove backup
    [[ -d "$INSTALL_DIR" ]] && mv "$INSTALL_DIR" "$INSTALL_DIR.bak"
    if mv "$tmp/macrift-main" "$INSTALL_DIR"; then
        rm -rf "$INSTALL_DIR.bak"
    else
        err "Failed to move files into place"
        [[ -d "$INSTALL_DIR.bak" ]] && mv "$INSTALL_DIR.bak" "$INSTALL_DIR"
        rm -rf "$tmp"
        exit 1
    fi
    rm -rf "$tmp"
    ok "Downloaded → $INSTALL_DIR"
else
    rm -rf "$tmp"
    err "Download failed — check your internet connection"
    exit 1
fi

# Permissions
chmod +x "$INSTALL_DIR/macrift.sh"
find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} +

# Global command — ~/.local/bin (no sudo)
_link_exists() {
    local target="$1/macrift"
    [[ -L "$target" ]] && [[ "$(readlink "$target" 2>/dev/null)" == "$INSTALL_DIR/macrift.sh" ]]
}

if _link_exists "$LOCAL_BIN" || _link_exists "/usr/local/bin"; then
    ok "macrift command already set up"
else
    printf '\n'
    if ask "Create global 'macrift' command?"; then
        mkdir -p "$LOCAL_BIN"
        ln -sf "$INSTALL_DIR/macrift.sh" "$LOCAL_BIN/macrift"
        ok "Linked → $LOCAL_BIN/macrift"

        if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
            local_zshrc="$HOME/.zshrc"
            path_line='export PATH="$HOME/.local/bin:$PATH" # added by macrift'
            if ! grep -qF '# added by macrift' "$local_zshrc" 2>/dev/null; then
                printf '\n%s\n' "$path_line" >> "$local_zshrc"
                ok "Added ~/.local/bin to PATH in .zshrc"
            fi
            export PATH="$LOCAL_BIN:$PATH"
        fi
        ok "Run from anywhere: macrift"
    else
        info "Run directly: ~/.macrift/macrift.sh"
    fi
fi

printf '\n  %bDone!%b Run %bmacrift%b to start.\n\n' "$GREEN" "$RESET" "$BOLD" "$RESET"

# Launch
"$INSTALL_DIR/macrift.sh"
