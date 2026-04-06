#!/usr/bin/env bash
# macrift — Spicetify marketplace settings restore

MARKETPLACE_BACKUP="$MACRIFT_DIR/config/spicetify/marketplace-settings.json"
RESTORE_EXT="macrift-restore.js"
SPICETIFY_EXT_DIR="$HOME/.config/spicetify/Extensions"

restore_marketplace() {
    clear

    if ! command -v spicetify &>/dev/null; then
        log_err "Spicetify not installed — install it from Apps > Spotify first"
        wait_enter
        return
    fi

    if [[ ! -f "$MARKETPLACE_BACKUP" ]]; then
        log_err "Backup not found: config/spicetify/marketplace-settings.json"
        wait_enter
        return
    fi

    if [[ ! -d "$HOME/.config/spicetify/CustomApps/marketplace" ]]; then
        log_info "Installing Marketplace..."
        curl -fsSL https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.sh | sh
        log_ok "Marketplace installed"
    fi

    _ensure_spotify_prefs || return

    show_info_box "Restore Marketplace Settings" \
        "This will:" \
        "  1. Generate a temporary Spicetify extension" \
        "  2. Apply it to inject saved marketplace settings" \
        "  3. Clean up after Spotify loads"

    if ! confirm "Continue?"; then
        return
    fi

    # Generate JS extension with embedded settings
    log_info "Generating restore extension..."
    mkdir -p "$SPICETIFY_EXT_DIR"

    local ext_file="$SPICETIFY_EXT_DIR/$RESTORE_EXT"

    {
        cat <<'JSHEAD'
(function macriftRestore() {
    if (!Spicetify || !Spicetify.LocalStorage) {
        setTimeout(macriftRestore, 300);
        return;
    }
    const data =
JSHEAD
        cat "$MARKETPLACE_BACKUP"
        cat <<'JSTAIL'
;
    // Only restore once — check flag
    if (Spicetify.LocalStorage.get("macrift-restore-done")) return;
    for (const [key, value] of Object.entries(data)) {
        Spicetify.LocalStorage.set(key, value);
    }
    Spicetify.LocalStorage.set("macrift-restore-done", "1");
    Spicetify.showNotification("macrift: Marketplace settings restored!");
})();
JSTAIL
    } > "$ext_file"

    log_ok "Extension generated"

    log_info "Adding extension to Spicetify..."
    spicetify config extensions "$RESTORE_EXT" 2>/dev/null || true
    if spicetify backup apply 2>/dev/null || spicetify apply 2>/dev/null; then
        log_ok "Applied — open Spotify to restore settings"
    else
        log_warn "Spicetify apply failed — try running 'spicetify backup apply' manually"
        wait_enter
        return
    fi

    log_ok "Open Spotify — settings will be restored once automatically"

    wait_enter
}
