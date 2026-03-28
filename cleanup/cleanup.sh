#!/usr/bin/env bash
# macrift — System cleanup (Mole)

MOLE_REPO="https://github.com/tw93/mole"
MOLE_INSTALL="https://raw.githubusercontent.com/tw93/mole/main/install.sh"

cleanup_menu() {
    while true; do
        clear
        set_title "macrift > cleanup"

        show_info_box "External script execution" \
            "" \
            "Tool:   Mole" \
            "URL:    $MOLE_REPO" \
            "Source: install.sh from main branch" \
            "" \
            "Y > Run   N > Cancel   R > Review source" \
            ""

        printf "\n"
        local choice
        read -r choice

        case "$choice" in
            y|Y)
                if command -v mole &>/dev/null; then
                    mole
                else
                    log_info "Installing Mole..."
                    if curl -fsSL "$MOLE_INSTALL" | bash; then
                        log_ok "Mole installed"
                        mole
                    else
                        log_err "Failed to install Mole"
                    fi
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
