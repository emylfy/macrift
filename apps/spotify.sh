#!/usr/bin/env bash
# macrift — Spotify customization (SpotX + Spicetify)

spotify_menu() {
    crumb_push "Spotify"
    while true; do
        clear

        local choice
        choice=$(show_menu "Spotify" \
            "SpotX — ad blocker (macOS)" \
            "Spicetify — customization framework" \
            "Restore marketplace settings" \
            "Back")

        case "$choice" in
            1) install_spotx ;;
            2) install_spicetify ;;
            3) source "$MACRIFT_DIR/apps/spicetify.sh" && restore_marketplace ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

SPOTX_URL="https://spotx-official.github.io/run.sh"
SPOTX_REPO="https://github.com/SpotX-Official/SpotX-Bash"

install_spotx() {
    while true; do
        clear

        local choice
        choice=$(show_menu "SpotX — Spotify ad blocker" \
            "Install SpotX" \
            "Review source" \
            "Back")

        case "$choice" in
            1)
                log_info "Running SpotX..."
                bash <(curl -fsSL "$SPOTX_URL") --installmac -f < /dev/tty
                log_ok "SpotX applied"
                wait_enter
                return
                ;;
            2) open "$SPOTX_REPO"; log_ok "Opened in browser" ;;
            0) return ;;
        esac
    done
}

install_spicetify() {
    # Check Spotify is installed
    if [[ ! -d "/Applications/Spotify.app" ]]; then
        log_err "Spotify not found — install it first"
        wait_enter
        return 1
    fi

    if command -v spicetify &>/dev/null; then
        run_with_spinner "Checking Spicetify for updates..." spicetify update || true
    else
        brew_install "spicetify-cli"
        if ! command -v spicetify &>/dev/null; then
            log_err "Spicetify not found after install"
            wait_enter
            return 1
        fi
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

    log_info "Applying Spicetify..."
    spicetify restore 2>/dev/null || true
    if ! spicetify backup apply 2>/dev/null; then
        log_warn "Spicetify backup apply failed — retrying..."
        spicetify apply 2>/dev/null || true
    fi

    # Install Marketplace if not present
    local mp_dir="$HOME/.config/spicetify/CustomApps/marketplace"
    if [[ ! -d "$mp_dir" ]]; then
        log_info "Installing Marketplace..."
        curl -fsSL https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.sh | sh
    fi
    spicetify config custom_apps marketplace 2>/dev/null || true
    spicetify apply 2>/dev/null || true
    log_ok "Spicetify + Marketplace applied"
    wait_enter
}
