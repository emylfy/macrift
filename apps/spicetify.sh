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

    # Spotify must be closed for spicetify apply
    log_warn "Spotify must be closed before applying"
    if pgrep -x Spotify &>/dev/null; then
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
    for (const [key, value] of Object.entries(data)) {
        Spicetify.LocalStorage.set(key, value);
    }
    Spicetify.showNotification("macrift: Marketplace settings restored!");
})();
JSTAIL
    } > "$ext_file"

    log_ok "Extension generated"

    log_info "Adding extension to Spicetify..."
    spicetify config extensions "$RESTORE_EXT"
    spicetify apply 2>/dev/null
    log_ok "Applied — open Spotify to restore settings"

    printf "\n"
    printf '  %bOpen Spotify and wait for the notification,%b\n' "$YELLOW" "$RESET"
    printf '  %bthen press Y to clean up the temp extension.%b\n\n' "$YELLOW" "$RESET"

    if confirm "Done? Clean up now?"; then
        log_info "Removing restore extension..."
        spicetify config extensions "${RESTORE_EXT}-"
        rm -f "$ext_file"
        spicetify apply 2>/dev/null
        log_ok "Cleanup complete"
    else
        log_warn "Extension left in place — remove manually:"
        log_info "  spicetify config extensions ${RESTORE_EXT}-"
        log_info "  rm $ext_file"
    fi

    wait_enter
}
