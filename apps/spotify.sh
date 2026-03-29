#!/usr/bin/env bash
# macrift — Spotify customization (SpotX + Spicetify)

spotify_menu() {
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
            0) return ;;
            *) ;;
        esac
    done
}

SPOTX_URL="https://spotx-official.github.io/run.sh"
SPOTX_REPO="https://github.com/SpotX-Official/SpotX-Bash"

install_spotx() {
    while true; do
        clear

        show_info_box "External script execution" \
            "" \
            "Tool:   SpotX - Spotify ad blocker" \
            "URL:    $SPOTX_REPO" \
            "Source: $SPOTX_URL" \
            "" \
            "Y > Run   N > Cancel   R > Review source" \
            ""

        printf "\n"
        local choice
        read -r choice

        case "$choice" in
            y|Y)
                log_info "Running SpotX..."
                bash <(curl -fsSL "$SPOTX_URL") --installmac -f < /dev/tty
                log_ok "SpotX applied"
                wait_enter
                return
                ;;
            n|N)
                return
                ;;
            r|R)
                open "$SPOTX_REPO"
                ;;
            *)
                log_err "Invalid option — use Y, N, or R"
                wait_retry
                ;;
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
}
