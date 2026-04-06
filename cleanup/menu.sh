#!/usr/bin/env bash
# macrift — System cleanup (Mole)

MOLE_REPO="https://github.com/tw93/mole"
MOLE_INSTALL="https://raw.githubusercontent.com/tw93/mole/main/install.sh"

cleanup_menu() {
    crumb_push "Cleanup"
    while true; do
        clear


        local choice
        choice=$(show_menu "Cleanup" \
            "Homebrew Cleanup" \
            "Deep Clean (Mole)" \
            "Back")

        case "$choice" in
            1) run_brew_cleanup ;;
            2) run_mole_cleanup ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

run_brew_cleanup() {
    clear

    if ! command -v brew &>/dev/null; then
        log_err "Homebrew is not installed"
        wait_enter
        return
    fi

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Would run: brew cleanup --prune=all && brew autoremove"
    else
        log_info "Running Homebrew cleanup..."
        brew cleanup --prune=all
        brew autoremove
        log_ok "Homebrew cleanup complete"
    fi

    wait_enter
}

run_mole_cleanup() {
    if command -v mole &>/dev/null; then
        clear
        mo clean
        wait_enter
        return
    fi

    while true; do
        clear

        local choice
        choice=$(show_menu "Mole — system cleanup" \
            "Install & run" \
            "Review source" \
            "Back")

        case "$choice" in
            1)
                log_info "Installing Mole..."
                if curl -fsSL "$MOLE_INSTALL" | bash; then
                    log_ok "Mole installed"
                    mole
                else
                    log_err "Failed to install Mole"
                fi
                wait_enter
                return
                ;;
            2) open "$MOLE_REPO"; log_ok "Opened in browser" ;;
            0) return ;;
        esac
    done
}
