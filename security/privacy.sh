#!/usr/bin/env bash
# macrift — Security & Privacy

PRIVACY_SEXY_URL="https://privacy.sexy"
PRIVACY_MACOS_PRESET="https://www.privacylearn.com/downloads/macos/standard.sh"

privacy_menu() {
    while true; do
        clear
        set_title "macrift > privacy"

        local choice
        choice=$(show_menu "Privacy & Security" \
            "privacy.sexy - build custom batch" \
            "privacy.sexy - run standard preset" \
            "Set hostname (hide identity on network)" \
            "Disable Homebrew analytics" \
            "Set encrypted DNS (Quad9)" \
            "Back")

        case "$choice" in
            1) open "$PRIVACY_SEXY_URL" ;;
            2) run_standard_preset ;;
            3) set_hostname ;;
            4) disable_brew_analytics ;;
            5) set_encrypted_dns ;;
            0) return ;;
            *) ;;
        esac
    done
}

run_standard_preset() {
    while true; do
        clear

        show_info_box "External script execution" \
            "" \
            "Tool:   privacy.sexy - standard macOS preset" \
            "URL:    $PRIVACY_SEXY_URL" \
            "Source: $PRIVACY_MACOS_PRESET" \
            "" \
            "Y > Run   N > Cancel   R > Review source" \
            ""

        printf "\n"
        local choice
        read -r choice

        case "$choice" in
            n|N) return ;;
            y|Y)
                log_info "Downloading preset..."
                local tmp
                tmp=$(mktemp /tmp/macrift_privacy_XXXXXX.sh)
                if curl -fsSL "$PRIVACY_MACOS_PRESET" -o "$tmp"; then
                    require_sudo
                    chmod +x "$tmp"
                    sudo bash "$tmp" < /dev/tty
                    log_ok "Privacy preset applied"
                else
                    log_err "Failed to download preset"
                fi
                rm -f "$tmp"
                printf "\n  ${DIM}press enter to continue${RESET} "
                read -r < /dev/tty
                return
                ;;
            r|R)
                open "$PRIVACY_SEXY_URL"
                ;;
            *)
                log_err "Invalid option — use Y, N, or R"
                printf "  ${DIM}press enter to retry${RESET} "
                read -r < /dev/tty
                ;;
        esac
    done
}

set_hostname() {
    clear
    divider "Hostname"

    local current
    current=$(scutil --get ComputerName 2>/dev/null || echo "unknown")
    log_info "Current hostname: $current"

    printf "\n  ${DIM}Enter new hostname (e.g. MacBook):${RESET} "
    local name
    read -r name

    if [[ -z "$name" ]]; then
        log_info "Cancelled"
        printf "\n  ${DIM}press enter to continue${RESET} "
        read -r
        return
    fi

    require_sudo
    sudo scutil --set ComputerName "$name"
    sudo scutil --set LocalHostName "$name"
    sudo scutil --set HostName "$name"
    log_ok "Hostname set to: $name"
    log_info "Your Mac will no longer broadcast your real name on networks"

    printf "\n  ${DIM}press enter to continue${RESET} "
    read -r
}

disable_brew_analytics() {
    clear
    divider "Homebrew Analytics"

    local status
    status=$(brew analytics 2>/dev/null || echo "unknown")

    if echo "$status" | grep -q "disabled"; then
        log_ok "Analytics already disabled"
    else
        log_info "Homebrew sends anonymous usage data by default"
        if confirm "Disable Homebrew analytics?"; then
            brew analytics off
            log_ok "Analytics disabled"
        fi
    fi

    printf "\n  ${DIM}press enter to continue${RESET} "
    read -r
}

set_encrypted_dns() {
    clear
    divider "Encrypted DNS"

    local current
    current=$(networksetup -getdnsservers Wi-Fi 2>/dev/null || echo "unknown")
    log_info "Current DNS:"
    printf "  ${DIM}%s${RESET}\n" "$current"
    printf "\n"

    log_info "Quad9 (9.9.9.9) blocks malware domains and supports DNSSEC"
    printf "\n"

    if confirm "Set DNS to Quad9?"; then
        networksetup -setdnsservers Wi-Fi 9.9.9.9 149.112.112.112
        log_ok "DNS set to Quad9"
    fi

    printf "\n  ${DIM}press enter to continue${RESET} "
    read -r
}
