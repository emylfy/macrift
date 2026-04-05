#!/usr/bin/env bash
# macrift — Spotify customization (SpotX + Spicetify)

spotify_menu() {
    crumb_push "Spotify"
    while true; do
        clear
        set_title "macrift > spotify"
        local choice
        choice=$(show_menu "Spotify" \
            "SpotX — ad blocker (macOS)" \
            "Spicetify — customization framework" \
            "Spicetify — restore marketplace" \
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
    if command -v spicetify &>/dev/null; then
        log_ok "Spicetify installed"
        log_info "Checking for updates..."
        spicetify update 2>/dev/null || true
    else
        brew_install "spicetify-cli"
        if ! command -v spicetify &>/dev/null; then
            log_err "Spicetify not found after install"
            return 1
        fi
    fi

    log_info "Applying Spicetify..."
    spicetify restore &>/dev/null || true
    spicetify backup apply &>/dev/null

    # Install Marketplace if not present
    local mp_dir="$HOME/.config/spicetify/CustomApps/marketplace"
    if [[ ! -d "$mp_dir" ]]; then
        log_info "Installing Marketplace..."
        curl -fsSL https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.sh | sh < /dev/tty
    fi
    spicetify config custom_apps marketplace &>/dev/null
    spicetify apply &>/dev/null
    log_ok "Spicetify + Marketplace applied"
    wait_enter
}
