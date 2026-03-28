#!/usr/bin/env bash
# macrift — macOS system customization tool

set -euo pipefail

MACRIFT_ENTRY="${BASH_SOURCE[0]}"
[[ -L "$MACRIFT_ENTRY" ]] && MACRIFT_ENTRY="$(readlink "$MACRIFT_ENTRY")"
source "$(cd "$(dirname "$MACRIFT_ENTRY")" && pwd)/common.sh"

# 
main_menu() {
    while true; do
        clear
        set_title "macrift"

        local choice
        choice=$(show_menu "macrift 26.03" \
            "System Tweaks" \
            "Apps & Packages" \
            "Customize" \
            "Security & Privacy" \
            "Cleanup" \
            "Exit")

        case "$choice" in
            1) source "$MACRIFT_DIR/tweaks/tweaks_menu.sh" && tweaks_menu ;;
            2) source "$MACRIFT_DIR/apps/apps_menu.sh" && apps_menu ;;
            3) source "$MACRIFT_DIR/apps/customize_menu.sh" && customize_menu ;;
            4) source "$MACRIFT_DIR/security/privacy.sh" && privacy_menu ;;
            5) source "$MACRIFT_DIR/cleanup/cleanup.sh" && cleanup_menu ;;
            0) cleanup_sudo; printf "\n  ${DIM}bye${RESET}\n\n"; exit 0 ;;
            *) ;;
        esac
    done
}

# 
check_macos
check_homebrew

trap cleanup_sudo EXIT

main_menu
