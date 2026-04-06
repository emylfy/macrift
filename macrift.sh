#!/usr/bin/env bash
# shellcheck disable=SC1091
# macrift — macOS system customization tool
#
# Usage: macrift [--dry-run] [--no-confirm] [--log]

set -euo pipefail

trap 'stty echo 2>/dev/null; printf "\033[?25h"' EXIT

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



main_menu() {
    crumb_push "macrift"
    while true; do
        clear

        # Build title with version, update hint, and flags
        local title="macrift $MACRIFT_VERSION"
        [[ -n "$MACRIFT_UPDATE" ]] && title+=" → $MACRIFT_UPDATE"
        local flags=""
        [[ "$MACRIFT_DRY_RUN" == true ]] && flags+=" [dry-run]"
        [[ "$MACRIFT_NO_CONFIRM" == true ]] && flags+=" [auto]"
        [[ -n "$MACRIFT_LOG" ]] && flags+=" [log]"
        [[ -n "$flags" ]] && title+="$flags"

        # Update menu label
        local update_label="Update"
        [[ -n "$MACRIFT_UPDATE" ]] && update_label="Update → $MACRIFT_UPDATE"

        local choice
        choice=$(show_menu "$title" \
            "System Tweaks" \
            "Apps & Packages" \
            "Customize" \
            "Security & Privacy" \
            "Cleanup" \
            "---" \
            "$update_label" \
            "Exit")

        case "$choice" in
            1) source "$MACRIFT_DIR/tweaks/menu.sh" && tweaks_menu ;;
            2)
                if check_homebrew; then
                    source "$MACRIFT_DIR/apps/menu.sh" && apps_menu
                else
                    wait_enter
                fi
                ;;
            3)
                if check_homebrew; then
                    source "$MACRIFT_DIR/customize/menu.sh" && customize_menu
                else
                    wait_enter
                fi
                ;;
            4) source "$MACRIFT_DIR/security/menu.sh" && privacy_menu ;;
            5) source "$MACRIFT_DIR/cleanup/menu.sh" && cleanup_menu ;;
            6)
                if macrift_update; then
                    log_info "Restarting..."
                    sleep 1
                    exec "$MACRIFT_DIR/macrift.sh"
                else
                    wait_enter
                fi
                ;;
            0) printf '\n  %bbye%b\n\n' "$DIM" "$RESET"; exit 0 ;;
            *) ;;
        esac
    done
}

#
check_macos
check_update

main_menu
