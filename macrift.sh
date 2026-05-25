#!/usr/bin/env bash
# shellcheck disable=SC1091
# macrift — macOS system customization tool
#
# Usage: macrift [--dry-run] [--no-confirm] [--log]

# Apple ships bash 3.2.57 — empty array expansions under `set -u` are unbound
# variable errors there. macrift uses arrays widely, so we require bash 4+.
# Re-exec under Homebrew bash if available, otherwise offer to install it.
if [[ "${BASH_VERSION%%.*}" -lt 4 ]]; then
    for _newer in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        [[ -x "$_newer" ]] && exec "$_newer" "$0" "$@"
    done

    printf '\n  \033[1;33mmacrift requires bash 4+\033[0m (you have %s)\n\n' "$BASH_VERSION" >&2

    if ! command -v brew >/dev/null 2>&1; then
        printf '  Install Homebrew first, then re-run macrift:\n' >&2
        printf '    \033[1m/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"\033[0m\n\n' >&2
        exit 1
    fi

    printf '  \033[0;33mInstall bash via Homebrew now?\033[0m \033[2m[y/n]\033[0m ' >&2
    read -r _answer </dev/tty
    if [[ "$_answer" =~ ^[Yy]$ ]]; then
        if brew install bash; then
            _newer="$(brew --prefix bash 2>/dev/null)/bin/bash"
            if [[ -x "$_newer" ]]; then
                printf '\n  \033[0;32m✓\033[0m Installed — restarting macrift under bash %s\n\n' \
                    "$("$_newer" -c 'echo "$BASH_VERSION"')" >&2
                exec "$_newer" "$0" "$@"
            fi
            printf '  \033[0;31m✗\033[0m brew installed bash but binary not found\n' >&2
        else
            printf '  \033[0;31m✗\033[0m brew install failed — see output above\n' >&2
        fi
        exit 1
    fi
    printf '  Cancelled. Run \033[1mbrew install bash\033[0m manually when ready.\n\n' >&2
    exit 1
fi

set -euo pipefail

_print_help() {
    echo "Usage: macrift [command] [flags]"
    echo ""
    echo "Commands:"
    echo "  fix [<path>...]              Remove quarantine xattr (fix 'damaged' errors)"
    echo "  gatekeeper [on|off|status]   Toggle Gatekeeper (alias: gk)"
    echo "  check                        Pre-purchase Mac check (used Mac diagnostics)"
    echo "  drift                        Show which applied tweaks still hold vs changed"
    echo "  undo [<session>|list]        Revert a journaled session (default: last)"
    echo "  apply [<file.json>]          Apply a declarative manifest (defaults family)"
    echo "  save [<file.json>]           Snapshot current tweaks to a manifest"
    echo "  help                         Show this help"
    echo ""
    echo "Flags:"
    echo "  --dry-run      Show what would change without applying"
    echo "  --no-confirm   Skip all confirmation prompts"
    echo "  --log          Write log to ~/.macrift/macrift.log"
    echo "  --uninstall    Remove macrift from this system"
    echo ""
    echo "Run without a command to open the interactive menu."
}

# Parse flags before sourcing (exports to common.sh). First non-flag arg
# becomes the subcommand; subsequent non-flag args become its arguments.
MACRIFT_SUBCMD=""
declare -a MACRIFT_SUBCMD_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --dry-run)     export MACRIFT_DRY_RUN=true ;;
        --no-confirm)  export MACRIFT_NO_CONFIRM=true ;;
        --log)         export MACRIFT_LOG="$HOME/.macrift/macrift.log" ;;
        --uninstall)
            printf '\n  Uninstall macrift?\n\n'
            printf '  This will remove:\n'
            printf '    ~/.macrift\n'
            printf '    ~/.local/bin/macrift\n'
            printf '    /usr/local/bin/macrift (if exists)\n'
            printf '    PATH line from ~/.zshrc\n\n'
            printf '  [y/n] '
            read -r answer
            if [[ "$answer" =~ ^[Yy]$ ]]; then
                rm -rf "$HOME/.macrift"
                rm -f "$HOME/.local/bin/macrift"
                [[ -L "/usr/local/bin/macrift" ]] && sudo rm -f "/usr/local/bin/macrift"
                if [[ -f "$HOME/.zshrc" ]]; then
                    sed -i '' '/# added by macrift/d' "$HOME/.zshrc" 2>/dev/null || true
                fi
                printf '  Done. macrift removed.\n\n'
            fi
            exit 0
            ;;
        --help|-h)
            _print_help
            exit 0
            ;;
        --*) ;;
        *)
            if [[ -z "$MACRIFT_SUBCMD" ]]; then
                MACRIFT_SUBCMD="$arg"
            else
                MACRIFT_SUBCMD_ARGS+=("$arg")
            fi
            ;;
    esac
done

# Resolve symlink — global 'macrift' command is a symlink to this file
MACRIFT_ENTRY="${BASH_SOURCE[0]}"
while [[ -L "$MACRIFT_ENTRY" ]]; do
    MACRIFT_ENTRY="$(readlink "$MACRIFT_ENTRY")"
done
source "$(cd "$(dirname "$MACRIFT_ENTRY")" && pwd)/common.sh"

# Init log file
if [[ -n "$MACRIFT_LOG" ]]; then
    mkdir -p "$(dirname "$MACRIFT_LOG")"
    printf "\n── macrift session %s ──\n" "$(date '+%Y-%m-%d %H:%M:%S')" >> "$MACRIFT_LOG"
fi

# Subcommand dispatch — runs before main_menu; exits when handled
case "${MACRIFT_SUBCMD:-}" in
    "") ;;
    help)
        _print_help
        exit 0
        ;;
    fix)
        check_macos
        source "$MACRIFT_DIR/security/menu.sh"
        quarantine_fix_cli "${MACRIFT_SUBCMD_ARGS[@]+"${MACRIFT_SUBCMD_ARGS[@]}"}"
        exit $?
        ;;
    gatekeeper|gk)
        check_macos
        source "$MACRIFT_DIR/security/menu.sh"
        gatekeeper_cli "${MACRIFT_SUBCMD_ARGS[@]+"${MACRIFT_SUBCMD_ARGS[@]}"}"
        exit $?
        ;;
    check)
        check_macos
        source "$MACRIFT_DIR/security/menu.sh"
        precheck_cli
        exit $?
        ;;
    drift)
        check_macos
        journal_drift_cli
        exit $?
        ;;
    undo)
        check_macos
        journal_undo_cli "${MACRIFT_SUBCMD_ARGS[@]+"${MACRIFT_SUBCMD_ARGS[@]}"}"
        exit $?
        ;;
    apply)
        check_macos
        manifest_apply_cli "${MACRIFT_SUBCMD_ARGS[@]+"${MACRIFT_SUBCMD_ARGS[@]}"}"
        exit $?
        ;;
    save)
        check_macos
        manifest_save_cli "${MACRIFT_SUBCMD_ARGS[@]+"${MACRIFT_SUBCMD_ARGS[@]}"}"
        exit $?
        ;;
    *)
        log_err "Unknown command: $MACRIFT_SUBCMD"
        printf '  Run %bmacrift --help%b for usage\n' "$BOLD" "$RESET" >&2
        exit 1
        ;;
esac


main_menu() {
    crumb_push "macrift"
    while true; do
        clear

        # Build title with version, update hint, and flags
        # Short version (YY.MM) in title — full version (YY.MM.N) lives in footer
        local title="macrift $MACRIFT_VERSION_SHORT"
        if [[ -n "$MACRIFT_UPDATE" ]]; then
            local update_short="$MACRIFT_UPDATE"
            [[ "$MACRIFT_UPDATE" =~ ^([0-9]+\.[0-9]+) ]] && update_short="${BASH_REMATCH[1]}"
            # Only show arrow for major bumps — patch-only updates would
            # render as "26.05 → 26.05" since both short to YY.MM
            [[ "$update_short" != "$MACRIFT_VERSION_SHORT" ]] && title+=" → $update_short"
        fi
        # Flags ([dry-run]/[auto]/[log]) render in the menu footer, not the title.

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
            2) source "$MACRIFT_DIR/apps/menu.sh" && apps_menu ;;
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
