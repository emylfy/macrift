#!/usr/bin/env bash
# macrift — Television (tv) fuzzy picker setup

television_menu() {
    if ! check_homebrew; then wait_enter; return; fi
    crumb_push "television"
    while true; do
        clear

        local choice
        choice=$(show_menu "television" \
            "Install television + channels" \
            "Back")

        case "$choice" in
            1) setup_television ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

setup_television() {
    if ! brew_install "television"; then return; fi

    local config_source="$MACRIFT_DIR/config/television/config.toml"
    local config_target="$HOME/.config/television/config.toml"

    if [[ ! -f "$config_source" ]]; then
        log_warn "No television config found in config/television/config.toml"
        log_info "Add your config there and re-run this"
        wait_enter
        return
    fi

    if confirm "Copy television config + channels?" "y"; then
        copy_config "$config_source" "$config_target"
        _television_install_cable
        _television_shell_init
        log_ok "television configured"
        log_hint "Run 'tv' to pick files; try 'tv git-log' or 'tv procs'"
    fi
    wait_enter
}

# Cable channels are a bundled dataset (18 curated inert .toml files). Placed like
# Ghostty's themes: copied directly, NOT journaled — so `undo`/`drift` stay
# readable. `undo` won't remove them (same as ghostty themes).
_television_install_cable() {
    local cable_source="$MACRIFT_DIR/config/television/cable"
    local cable_target="$HOME/.config/television/cable"

    if [[ ! -d "$cable_source" ]]; then
        log_warn "No cable channels found in config/television/cable/"
        return
    fi
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install cable channels → ~/.config/television/cable/"
        return
    fi

    mkdir -p "$cable_target"
    local n=0
    for ch in "$cable_source"/*.toml; do
        [[ -f "$ch" ]] || continue
        cp "$ch" "$cable_target/$(basename "$ch")"
        n=$((n + 1))
    done
    log_ok "Installed $n cable channels"
}

# Television's shell integration (Ctrl-T smart complete, Ctrl-R history) needs
# `tv init zsh` in the live shell. Append to ~/.zshrc if absent — same approach
# as install_starship. If atuin is also used, it should load after this line so
# it keeps Ctrl-R (see config/shell/.zshrc ordering).
_television_shell_init() {
    local rc="$HOME/.zshrc"
    if grep -q 'tv init zsh' "$rc" 2>/dev/null; then
        log_skip "tv shell init already in .zshrc"
        return
    fi
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would add 'tv init zsh' to .zshrc"
        return
    fi
    if confirm "Add television shell integration (Ctrl-T) to .zshrc?" "y"; then
        printf '\n# Television shell integration\ncommand -v tv &>/dev/null && eval "$(tv init zsh)"\n' >> "$rc"
        log_ok "Added tv shell init to .zshrc (restart shell to apply)"
    fi
}
