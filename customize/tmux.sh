#!/usr/bin/env bash
# macrift — tmux setup (config + TPM)

TPM_DIR="$HOME/.config/tmux/plugins/tpm"

tmux_menu() {
    if ! check_homebrew; then wait_enter; return; fi
    crumb_push "tmux"
    while true; do
        clear

        local choice
        choice=$(show_menu "tmux" \
            "Install tmux + apply config" \
            "Install plugins now" \
            "Back")

        case "$choice" in
            1) setup_tmux ;;
            2) tmux_install_plugins ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

setup_tmux() {
    if ! brew_install "tmux"; then return; fi

    local conf_source="$MACRIFT_DIR/config/tmux/tmux.conf"
    local reset_source="$MACRIFT_DIR/config/tmux/tmux.reset.conf"
    local conf_target="$HOME/.config/tmux/tmux.conf"
    local reset_target="$HOME/.config/tmux/tmux.reset.conf"

    if [[ ! -f "$conf_source" ]]; then
        log_warn "No tmux config found in config/tmux/tmux.conf"
        log_info "Add your config there and re-run this"
        wait_enter
        return
    fi

    if confirm "Copy tmux config?"; then
        copy_config "$conf_source" "$conf_target"
        [[ -f "$reset_source" ]] && copy_config "$reset_source" "$reset_target"
        tmux_install_tpm
        log_ok "tmux configured"
        log_hint "Start it with 'tmux'; detach with <prefix> d, return with 'tmux attach'"
    fi
    wait_enter
}

# Clone TPM (Tmux Plugin Manager). The config's @plugin lines only work once
# TPM is present. Idempotent — skips if already cloned.
tmux_install_tpm() {
    if [[ -d "$TPM_DIR" ]]; then
        log_skip "TPM already installed"
        return
    fi
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would clone TPM into ~/.config/tmux/plugins/tpm"
        return
    fi
    if ! command -v git &>/dev/null; then
        log_err "Git required — install Xcode Command Line Tools first"
        return
    fi
    mkdir -p "$(dirname "$TPM_DIR")"
    if run_with_spinner "Installing TPM..." git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"; then
        log_ok "TPM installed"
    else
        log_err "TPM installation failed"
    fi
}

# Install the plugins declared in tmux.conf without making the user press
# <prefix> + I inside tmux — TPM ships a non-interactive installer.
tmux_install_plugins() {
    clear
    if [[ ! -d "$TPM_DIR" ]]; then
        log_warn "TPM not installed — run 'Install tmux + apply config' first"
        wait_enter
        return
    fi
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would run TPM's install_plugins"
        wait_enter
        return
    fi
    if run_with_spinner "Installing tmux plugins..." "$TPM_DIR/bin/install_plugins"; then
        log_ok "tmux plugins installed"
    else
        log_warn "Plugin install failed — open tmux and press <prefix> + I to retry"
    fi
    wait_enter
}
