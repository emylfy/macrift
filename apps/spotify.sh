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
            "Cancel")

        case "$choice" in
            1)
                log_info "Running SpotX..."
                bash <(curl -fsSL "$SPOTX_URL") --installmac -f < /dev/tty
                log_ok "SpotX applied"
                wait_enter
                return
                ;;
            2) open "$SPOTX_REPO" ;;
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

    if confirm "Apply Spicetify to Spotify?"; then
        spicetify restore 2>/dev/null || true
        spicetify backup apply
        log_ok "Spicetify applied"
        log_info "Use 'spicetify' command to customize further"
    fi
    wait_enter
}
