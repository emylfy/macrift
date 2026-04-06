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

    # Spotify must have been launched at least once to create prefs
    local prefs_path="$HOME/Library/Application Support/Spotify/prefs"
    if [[ ! -f "$prefs_path" ]]; then
        log_warn "Spotify prefs not found — need to launch it once"
        if confirm "Launch Spotify now?"; then
            open -a Spotify
            log_info "Waiting for Spotify to initialize..."
            local wait=0
            while [[ ! -f "$prefs_path" && $wait -lt 15 ]]; do
                sleep 1; wait=$((wait + 1))
            done
            if [[ ! -f "$prefs_path" ]]; then
                log_err "Prefs still not found — try opening Spotify manually and retry"
                wait_enter
                return
            fi
            log_ok "Prefs created — closing Spotify"
            killall Spotify 2>/dev/null || true
            sleep 1
        else
            log_info "Open Spotify manually, close it, then retry"
            wait_enter
            return
        fi
    elif pgrep -x Spotify &>/dev/null; then
        log_warn "Spotify must be closed before applying"
        if confirm "Quit Spotify now?"; then
            killall Spotify 2>/dev/null || true
            sleep 1
        else
            log_info "Close Spotify manually and retry"
            wait_enter
            return
        fi
    fi

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
