#!/usr/bin/env bash
# macrift — one-line installer
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/emylfy/macrift/main/install.sh)
# The install itself works on a fresh macOS — needs only curl/tar/shasum (all
# built-in). The optional extras plugin needs git and is skipped without it.

set -euo pipefail

REPO="emylfy/macrift"
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
    local answer=""
    # No tty (CI, scripted install) → default no instead of dying under set -e
    if [[ -r /dev/tty ]]; then
        read -r answer </dev/tty || true
    else
        printf '%b[no tty: n]%b\n' "$DIM" "$RESET"
    fi
    [[ "$answer" =~ ^[Yy]$ ]]
}

# Resolve the latest published release, download its checksummed tarball, verify
# the sha256, and extract into $1 (yielding $1/macrift). Pinned + verified — never
# floating `main`; fails loud rather than installing anything unverified. Needs
# only curl/tar/shasum (all stock on macOS — no python/jq).
fetch_verified_macrift() {
    local dest="$1" url tag ver fname asset_url

    info "Resolving latest release..."
    url=$(curl -fsSL -I -o /dev/null -w '%{url_effective}' \
        "https://github.com/$REPO/releases/latest" 2>/dev/null) || true
    tag="${url##*/}"
    if [[ -z "$tag" || "$tag" == "latest" ]]; then
        err "Could not resolve a published release"
        return 1
    fi
    ver="${tag#v}"
    fname="macrift-$ver.tar.gz"
    asset_url="https://github.com/$REPO/releases/download/$tag/$fname"

    info "Downloading macrift $tag..."
    if ! curl -fsSL -o "$dest/$fname" "$asset_url"; then
        err "Download failed — release asset missing or no connection"
        return 1
    fi
    if ! curl -fsSL -o "$dest/$fname.sha256" "$asset_url.sha256"; then
        err "No checksum published for $tag — refusing to install unverified"
        return 1
    fi

    info "Verifying checksum..."
    if ! ( cd "$dest" && shasum -a 256 -c "$fname.sha256" ) >/dev/null 2>&1; then
        err "Checksum mismatch — refusing to install"
        return 1
    fi
    ok "Verified $tag"

    if ! tar -xzf "$dest/$fname" -C "$dest" || [[ ! -d "$dest/macrift" ]]; then
        err "Extract failed or unexpected archive layout"
        return 1
    fi
}

if [[ "$(uname)" != "Darwin" ]]; then
    err "macrift is for macOS only"
    exit 1
fi

# One-shot mode: any args after `--` → download to /tmp, run macrift with those
# args, clean up, exit. Lets you do `... | bash -s -- check` to inspect a Mac
# without installing anything (perfect for the seller's machine before buying).
if [[ $# -gt 0 ]]; then
    printf '\n  %bmacrift%b %bone-shot:%b %s\n\n' "$BOLD" "$RESET" "$DIM" "$RESET" "$*"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    if fetch_verified_macrift "$tmp"; then
        chmod +x "$tmp/macrift/macrift.sh"
        find "$tmp/macrift" -name "*.sh" -exec chmod +x {} +
        "$tmp/macrift/macrift.sh" "$@"
        exit $?
    else
        exit 1
    fi
fi

printf '\n  %bmacrift installer%b\n\n' "$BOLD" "$RESET"

# Download + verify
tmp="$(mktemp -d)"
if fetch_verified_macrift "$tmp"; then
    # Atomic swap: backup old → move new → carry user data over → remove backup.
    # Clear any stale .bak from a prior interrupted run first, or the backup mv
    # would nest the old install inside it.
    rm -rf "$INSTALL_DIR.bak"
    [[ -d "$INSTALL_DIR" ]] && mv "$INSTALL_DIR" "$INSTALL_DIR.bak"
    if mv "$tmp/macrift" "$INSTALL_DIR"; then
        # User data (undo journal, plugins, logs) lives inside ~/.macrift —
        # move it into the new install instead of deleting it with the backup.
        for keep in state plugins plugins.lock.json macrift.log; do
            if [[ -e "$INSTALL_DIR.bak/$keep" && ! -e "$INSTALL_DIR/$keep" ]]; then
                mv "$INSTALL_DIR.bak/$keep" "$INSTALL_DIR/$keep"
            fi
        done
        rm -rf "$INSTALL_DIR.bak"
    else
        err "Failed to move files into place"
        [[ -d "$INSTALL_DIR.bak" ]] && mv "$INSTALL_DIR.bak" "$INSTALL_DIR"
        rm -rf "$tmp"
        exit 1
    fi
    rm -rf "$tmp"
    ok "Installed → $INSTALL_DIR"
else
    rm -rf "$tmp"
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

# Bundled extras (Spotify SpotX + Spicetify) ship as a separate plugin so the
# core stays lean. Install it by default to keep the out-of-box experience whole.
# Best-effort: a failed clone (offline / repo not published yet) just skips it.
MISC_PLUGIN_DIR="$HOME/.macrift/plugins/misc"
if [[ ! -d "$MISC_PLUGIN_DIR" ]]; then
    if command -v git >/dev/null 2>&1 && [[ -r /dev/tty ]]; then
        info "Adding bundled extras plugin (Spotify SpotX + Spicetify)…"
        if "$INSTALL_DIR/macrift.sh" plugin add github.com/emylfy/macrift-misc </dev/tty; then
            ok "Extras installed"
        else
            info "Skipped extras — add later with: macrift plugin add github.com/emylfy/macrift-misc"
        fi
    else
        info "Skipped extras (needs git + a terminal) — add later with: macrift plugin add github.com/emylfy/macrift-misc"
    fi
fi

printf '\n  %bDone!%b Run %bmacrift%b to start.\n\n' "$GREEN" "$RESET" "$BOLD" "$RESET"

# Launch (interactive installs only — scripted runs stop here)
if [[ -r /dev/tty ]]; then
    "$INSTALL_DIR/macrift.sh"
fi
