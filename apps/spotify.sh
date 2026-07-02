#!/usr/bin/env bash
# macrift — Spotify customization (SpotX + Spicetify)

# Ensure Spotify prefs file exists (created on first launch) and Spotify is closed.
# Returns 1 if user aborts or prefs can't be created.
_ensure_spotify_prefs() {
    local prefs_path="$HOME/Library/Application Support/Spotify/prefs"
    if [[ ! -f "$prefs_path" ]]; then
        log_warn "Spotify prefs not found — need to launch it once"
        if confirm "Launch Spotify now?"; then
            open -a Spotify
            log_info "Waiting for Spotify to initialize..."
            local w=0
            while [[ ! -f "$prefs_path" && $w -lt 15 ]]; do
                sleep 1; w=$((w + 1))
            done
            if [[ ! -f "$prefs_path" ]]; then
                log_err "Prefs still not found — try opening Spotify manually and retry"
                wait_enter
                return 1
            fi
            log_ok "Prefs created — closing Spotify"
            killall Spotify 2>/dev/null || true
            sleep 1
        else
            log_info "Open Spotify manually, close it, then retry"
            wait_enter
            return 1
        fi
    elif pgrep -x Spotify &>/dev/null; then
        log_info "Closing Spotify..."
        killall Spotify 2>/dev/null || true
        sleep 1
    fi
    return 0
}

spotify_menu() {
    if ! check_homebrew; then wait_enter; return; fi
    crumb_push "Spotify"
    while true; do
        clear

        local choice
        choice=$(show_menu "Spotify" \
            "SpotX — ad blocker" \
            "Spicetify — customization framework" \
            "---" \
            "Restore marketplace settings" \
            "Save marketplace settings" \
            "Back")

        case "$choice" in
            1) install_spotx ;;
            2) install_spicetify ;;
            3) source "$MACRIFT_DIR/apps/spicetify.sh" && restore_marketplace ;;
            4) source "$MACRIFT_DIR/apps/spicetify.sh" && save_marketplace ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

SPOTX_URL="https://spotx-official.github.io/run.sh"
SPOTX_REPO="https://github.com/SpotX-Official/SpotX-Bash"

install_spotx() {
    clear
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install SpotX"
        wait_enter
        return 0
    fi
    log_info "SpotX — Spotify ad blocker"
    printf '  %bSource: %s%b\n\n' "$DIM" "$SPOTX_REPO" "$RESET"

    if confirm "Install SpotX?"; then
        log_info "Running SpotX..."
        # Guard set -e: SpotX exits non-zero on network failure / unsupported
        # Spotify version, which would otherwise abort the whole menu.
        if bash <(curl -fsSL "$SPOTX_URL") --installmac -f < /dev/tty; then
            log_ok "SpotX applied"
        else
            log_warn "SpotX exited with an error"
        fi
    fi
    wait_enter
}

install_spicetify() {
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install Spicetify + Marketplace"
        wait_enter
        return 0
    fi

    # Check Spotify is installed
    if [[ ! -d "/Applications/Spotify.app" ]]; then
        log_err "Spotify not found — install it first"
        wait_enter
        return 1
    fi

    if command -v spicetify &>/dev/null; then
        run_with_spinner "Checking Spicetify for updates..." spicetify update || true
    else
        brew_install "spicetify-cli" && _journal_append_brew "spicetify-cli" "formula" "" "absent"
        if ! command -v spicetify &>/dev/null; then
            log_err "Spicetify not found after install"
            wait_enter
            return 1
        fi
    fi

    # Spotify must have been launched at least once to create prefs
    _ensure_spotify_prefs || return 0

    log_info "Applying Spicetify..."
    local apply_ok=true mp_ok=true
    spicetify restore 2>/dev/null || true
    if ! spicetify backup apply 2>/dev/null; then
        log_warn "Spicetify backup apply failed — retrying..."
        spicetify apply 2>/dev/null || apply_ok=false
    fi

    # Install Marketplace if not present.
    # Installer calls `spicetify apply` internally — track failure instead of
    # letting set -e + pipefail kill macrift.
    local mp_dir="$HOME/.config/spicetify/CustomApps/marketplace"
    if [[ ! -d "$mp_dir" ]]; then
        log_info "Installing Marketplace..."
        curl -fsSL https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.sh | sh || mp_ok=false
        [[ -d "$mp_dir" ]] || mp_ok=false
    fi
    spicetify config custom_apps marketplace 2>/dev/null || mp_ok=false
    spicetify apply 2>/dev/null || apply_ok=false

    if $apply_ok && $mp_ok; then
        log_ok "Spicetify + Marketplace applied"
    else
        $mp_ok || log_warn "Marketplace install failed"
        $apply_ok || log_err "Spicetify apply failed"
        log_hint "try 'spicetify backup apply' manually, or re-run this step"
    fi
    wait_enter
}
