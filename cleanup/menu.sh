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
            2) run_mole_cleanup || true ;; # guard set -e: interactive mole may exit non-zero
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

run_brew_cleanup() {
    clear

    if ! command -v brew &>/dev/null; then
        log_skip "Homebrew not installed"
        log_hint "get it at https://brew.sh"
        wait_enter
        return
    fi

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Would run: brew cleanup --prune=all && brew autoremove"
        wait_enter
        return
    fi

    log_info "Running Homebrew cleanup..."
    local tmp; tmp=$(mktemp)

    # Cleanup — stream live, then summarize freed space (or note nothing to clear).
    # Guards: pipefail would surface a non-zero brew through tee, and grep exits 1
    # on no match (the "already clean" case) — both abort under set -e without || true.
    brew cleanup --prune=all 2>&1 | tee "$tmp" || true
    local freed
    freed=$(grep -oE 'freed approximately [0-9.]+[KMGT]?B' "$tmp" | tail -1 || true)
    freed="${freed#freed approximately }"
    if [[ -n "$freed" && "$freed" != 0B ]]; then
        log_ok "Homebrew cleanup — freed $freed"
    else
        log_skip "Caches already clean"
    fi

    # Autoremove — report orphaned dependencies removed, else stay quiet.
    : > "$tmp"
    brew autoremove 2>&1 | tee "$tmp" || true
    local removed
    removed=$(grep -c '^Uninstalling ' "$tmp" || true)
    if [[ "$removed" -gt 0 ]]; then
        log_ok "Removed $removed orphaned $([[ $removed -eq 1 ]] && echo dependency || echo dependencies)"
    fi

    rm -f "$tmp"
    wait_enter
}

run_mole_cleanup() {
    clear
    if command -v mole &>/dev/null; then
        mole clean
        wait_enter
        return
    fi

    log_info "Mole — system cleanup tool"
    printf '  %bSource: %s%b\n\n' "$DIM" "$MOLE_REPO" "$RESET"

    if confirm "Install & run Mole?"; then
        log_info "Installing Mole..."
        if curl -fsSL "$MOLE_INSTALL" | bash; then
            log_ok "Mole installed"
            mole
        else
            log_err "Failed to install Mole"
            log_hint "install manually: curl -fsSL $MOLE_INSTALL | bash"
        fi
    fi
    wait_enter
}
