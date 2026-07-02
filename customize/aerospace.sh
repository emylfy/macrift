#!/usr/bin/env bash
# macrift — AeroSpace tiling window manager setup

aerospace_menu() {
    if ! check_homebrew; then wait_enter; return; fi
    crumb_push "AeroSpace"
    while true; do
        clear

        local choice
        choice=$(show_menu "AeroSpace" \
            "Install AeroSpace + apply config" \
            "Reload config" \
            "Back")

        case "$choice" in
            1) setup_aerospace ;;
            2) aerospace_reload ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

setup_aerospace() {
    if ! brew_install "aerospace" "cask"; then return; fi

    local config_source="$MACRIFT_DIR/config/aerospace/aerospace.toml"
    local config_target="$HOME/.config/aerospace/aerospace.toml"

    if [[ ! -f "$config_source" ]]; then
        log_warn "No AeroSpace config found in config/aerospace/aerospace.toml"
        log_info "Add your config there and re-run this"
        wait_enter
        return
    fi

    if confirm "Copy AeroSpace config?" "y"; then
        copy_config "$config_source" "$config_target"
        log_ok "AeroSpace configured"
        log_hint "Launch AeroSpace, then use ⌥+hjkl to focus and ⌥+1-9 for workspaces"
    fi
    wait_enter
}

aerospace_reload() {
    clear
    if ! command -v aerospace &>/dev/null; then
        log_warn "AeroSpace not installed — run 'Install AeroSpace + apply config' first"
        wait_enter
        return
    fi
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would run 'aerospace reload-config'"
        wait_enter
        return
    fi
    if aerospace reload-config 2>/dev/null; then
        log_ok "AeroSpace config reloaded"
    else
        log_warn "Could not reload — is AeroSpace running?"
    fi
    wait_enter
}
