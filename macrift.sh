#!/usr/bin/env bash
# macrift — macOS system customization tool
#
# Usage: macrift [--dry-run] [--no-confirm] [--log]

set -euo pipefail

# Parse flags before sourcing (exports to common.sh)
for arg in "$@"; do
    case "$arg" in
        --dry-run)     export MACRIFT_DRY_RUN=true ;;
        --no-confirm)  export MACRIFT_NO_CONFIRM=true ;;
        --log)         export MACRIFT_LOG="$HOME/.macrift/macrift.log" ;;
        --help|-h)
            echo "Usage: macrift [--dry-run] [--no-confirm] [--log]"
            echo "  --dry-run      Show what would change without applying"
            echo "  --no-confirm   Skip all confirmation prompts"
            echo "  --log          Write log to ~/.macrift/macrift.log"
            exit 0
            ;;
    esac
done

MACRIFT_ENTRY="${BASH_SOURCE[0]}"
[[ -L "$MACRIFT_ENTRY" ]] && MACRIFT_ENTRY="$(readlink "$MACRIFT_ENTRY")"
source "$(cd "$(dirname "$MACRIFT_ENTRY")" && pwd)/common.sh"

# Init log file
if [[ -n "$MACRIFT_LOG" ]]; then
    mkdir -p "$(dirname "$MACRIFT_LOG")"
    printf "\n── macrift session %s ──\n" "$(date '+%Y-%m-%d %H:%M:%S')" >> "$MACRIFT_LOG"
fi

#
main_menu() {
    while true; do
        clear
        set_title "macrift"

        # Show active flags in title
        local title="macrift 26.03"
        local flags=""
        [[ "$MACRIFT_DRY_RUN" == true ]] && flags+=" [dry-run]"
        [[ "$MACRIFT_NO_CONFIRM" == true ]] && flags+=" [auto]"
        [[ -n "$MACRIFT_LOG" ]] && flags+=" [log]"
        [[ -n "$flags" ]] && title+="$flags"

        local choice
        choice=$(show_menu "$title" \
            "System Tweaks" \
            "Apps & Packages" \
            "Customize" \
            "Security & Privacy" \
            "Cleanup" \
            "Profile Backup" \
            "Exit")

        case "$choice" in
            1) source "$MACRIFT_DIR/tweaks/tweaks_menu.sh" && tweaks_menu ;;
            2) source "$MACRIFT_DIR/apps/apps_menu.sh" && apps_menu ;;
            3) source "$MACRIFT_DIR/apps/customize_menu.sh" && customize_menu ;;
            4) source "$MACRIFT_DIR/security/privacy.sh" && privacy_menu ;;
            5) source "$MACRIFT_DIR/cleanup/cleanup.sh" && cleanup_menu ;;
            6) source "$MACRIFT_DIR/apps/profile.sh" && profile_menu ;;
            0) printf '\n  %bbye%b\n\n' "$DIM" "$RESET"; exit 0 ;;
            *) ;;
        esac
    done
}

# 
check_macos
check_homebrew

main_menu
