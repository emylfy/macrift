#!/usr/bin/env bash
# macrift — Spicetify marketplace settings restore

MARKETPLACE_BACKUP="$MACRIFT_DIR/config/spicetify/marketplace-settings.json"
RESTORE_EXT="macrift-restore.js"
SPICETIFY_EXT_DIR="$HOME/.config/spicetify/Extensions"

restore_marketplace() {
    clear
    divider "Spicetify Marketplace Restore"

    if ! command -v spicetify &>/dev/null; then
        log_err "Spicetify not installed — install it from Apps > Spotify first"
        printf "\n  ${DIM}press enter to continue${RESET} "
        read -r < /dev/tty
        return
    fi

    if [[ ! -f "$MARKETPLACE_BACKUP" ]]; then
        log_err "Backup not found: config/spicetify/marketplace-settings.json"
        printf "\n  ${DIM}press enter to continue${RESET} "
        read -r < /dev/tty
        return
    fi

    if [[ ! -d "$HOME/.config/spicetify/CustomApps/marketplace" ]]; then
        log_warn "Marketplace custom app not found"
        if confirm "Install marketplace?"; then
            spicetify config custom_apps marketplace
            spicetify apply
            log_ok "Marketplace installed"
        else
            return
        fi
    fi

    show_info_box "Restore Marketplace Settings" \
        "" \
        "This will:" \
        "  1. Generate a temporary Spicetify extension" \
        "  2. Apply it to inject saved marketplace settings" \
        "  3. Clean up after Spotify loads" \
        ""

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
    printf "  ${YELLOW}Open Spotify and wait for the notification,${RESET}\n"
    printf "  ${YELLOW}then press Y to clean up the temp extension.${RESET}\n\n"

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

    printf "\n  ${DIM}press enter to continue${RESET} "
    read -r < /dev/tty
}
