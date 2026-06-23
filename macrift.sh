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
    echo "  apply [<file.json>]          Apply a declarative manifest (settings, packages, dotfiles, configs)"
    echo "  save [<file.json>]           Snapshot current settings + packages to a manifest"
    echo "  plugin <subcommand>          Manage plugins (see 'macrift plugin help')"
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
            # A Homebrew install is owned by brew — delegate to it (rm -rf'ing the
            # Cellar would leave brew's records dangling). common.sh isn't sourced
            # yet, so detect brew from the path; exec so brew runs after this script
            # exits and can safely remove the Cellar files out from under it.
            if [[ "${BASH_SOURCE[0]}" == */Cellar/macrift/* || "${BASH_SOURCE[0]}" == */opt/macrift/* ]]; then
                printf '\n  Uninstall macrift (installed via Homebrew)?\n\n'
                printf '  Runs: brew uninstall macrift\n'
                printf '  Your data in ~/.macrift (journal, plugins) is left untouched.\n\n'
                printf '  [y/n] '
                read -r answer
                [[ "$answer" =~ ^[Yy]$ ]] && exec brew uninstall macrift
                exit 0
            fi
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
# shellcheck source=plugins.sh
source "$MACRIFT_DIR/plugins.sh"

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
    plugin)
        check_macos
        _plugin_cli "${MACRIFT_SUBCMD_ARGS[@]+"${MACRIFT_SUBCMD_ARGS[@]}"}"
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

        # Title: version + optional "→ <newer>" arrow on major bump.
        local title="macrift $MACRIFT_VERSION_SHORT"
        if [[ -n "$MACRIFT_UPDATE" ]]; then
            local update_short="$MACRIFT_UPDATE"
            [[ "$MACRIFT_UPDATE" =~ ^([0-9]+\.[0-9]+) ]] && update_short="${BASH_REMATCH[1]}"
            [[ "$update_short" != "$MACRIFT_VERSION_SHORT" ]] && title+=" → $update_short"
        fi
        local update_label="Update"
        [[ -n "$MACRIFT_UPDATE" ]] && update_label="Update → $MACRIFT_UPDATE"

        # Build items + a parallel actions array.
        # When no plugins are installed this yields exactly the menu shape we
        # had before — feature-flagged so existing users see zero change.
        local -a items=(
            "System Tweaks ›"
            "Apps & Packages ›"
            "Customize ›"
            "Security & Privacy ›"
            "Cleanup ›"
        )
        local -a actions=(tweaks apps customize security cleanup)

        if (( ${#MACRIFT_PLUGIN_REGISTRY[@]} > 0 )); then
            # Group top-level plugin entries by section (first-seen order).
            # Records with a non-empty parent inject into a built-in submenu
            # instead (handled by the submenu functions), so skip them here.
            local -A _seen=()
            local -a _sections=()
            local rec _target _s _e _f
            for rec in "${MACRIFT_PLUGIN_REGISTRY[@]}"; do
                IFS=$'\t' read -r _target _e _f <<<"$rec"
                [[ "$_target" == p:* ]] && continue   # injected into a submenu, not root
                _s="${_target#s:}"
                if [[ -z "${_seen[$_s]+x}" ]]; then
                    _sections+=("$_s")
                    _seen[$_s]=1
                fi
            done
            if (( ${#_sections[@]} > 0 )); then
                items+=("---")
                for _s in "${_sections[@]}"; do
                    items+=("## $_s")
                    for rec in "${MACRIFT_PLUGIN_REGISTRY[@]}"; do
                        IFS=$'\t' read -r _target entry func <<<"$rec"
                        [[ "$_target" == p:* ]] && continue
                        [[ "${_target#s:}" == "$_s" ]] || continue
                        items+=("$entry")
                        actions+=("plugin:$func")
                    done
                done
            fi
        fi

        items+=("---" "Manage Plugins ›" "Snapshots & Undo ›" "$update_label" "Exit")
        actions+=(plugins snapshots update)
        # No action for trailing "Exit" — show_menu returns 0 for it.

        local choice
        choice=$(show_menu "$title" "${items[@]}")

        if [[ "$choice" == "0" ]]; then
            printf '\n  %bbye%b\n\n' "$DIM" "$RESET"
            exit 0
        fi

        local action="${actions[$((choice - 1))]:-}"
        case "$action" in
            tweaks)    source "$MACRIFT_DIR/tweaks/menu.sh"    && tweaks_menu ;;
            apps)      source "$MACRIFT_DIR/apps/menu.sh"      && apps_menu ;;
            customize) source "$MACRIFT_DIR/customize/menu.sh" && customize_menu ;;
            security)  source "$MACRIFT_DIR/security/menu.sh"  && privacy_menu ;;
            cleanup)   source "$MACRIFT_DIR/cleanup/menu.sh"   && cleanup_menu ;;
            snapshots) source "$MACRIFT_DIR/snapshots/menu.sh" && snapshots_menu ;;
            update)
                if macrift_update; then
                    log_info "Restarting..."
                    sleep 1
                    exec "$MACRIFT_DIR/macrift.sh"
                else
                    wait_enter
                fi
                ;;
            plugins)   plugins_menu || true ;;
            plugin:*)
                # Guard with `|| true`: a plugin handler returning non-zero
                # must not abort the main menu (set -e is live here).
                "${action#plugin:}" || true
                ;;
            "") ;;  # out-of-bounds — show_menu shouldn't return one, but be safe
        esac
    done
}

#
check_macos
check_update
# Discover + source any compatible plugins under ~/.macrift/plugins/ so their
# entries can appear in the main menu. Incompatible / broken plugins are
# skipped with a log_warn — they never abort macrift startup.
_plugin_load_all

main_menu
