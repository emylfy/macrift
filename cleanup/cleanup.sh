#!/usr/bin/env bash
# macrift — System cleanup (Mole)

MOLE_REPO="https://github.com/tw93/mole"
MOLE_INSTALL="https://raw.githubusercontent.com/tw93/mole/main/install.sh"

cleanup_menu() {
    while true; do
        clear
        set_title "macrift > cleanup"

        local choice
        choice=$(show_menu "Cleanup" \
            "Homebrew Cleanup" \
            "Deep Clean (Mole)" \
            "Back")

        case "$choice" in
            1) run_brew_cleanup ;;
            2) run_mole_cleanup ;;
            0) return ;;
            *) ;;
        esac
    done
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

        show_info_box "Mole not installed" \
            "" \
            "About:  removes caches, logs, Xcode/simulator/brew leftovers" \
            "URL:    $MOLE_REPO" \
            "" \
            "Y > Install & run   N > Cancel   R > Review source" \
            ""

        printf "\n"
        local choice
        read -r choice

        case "$choice" in
            y|Y)
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
            r|R)
                open "$MOLE_REPO"
                ;;
            n|N)
                return
                ;;
            *)
                log_err "Invalid option — use Y, N, or R"
                wait_retry
                ;;
        esac
    done
}
