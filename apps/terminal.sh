#!/usr/bin/env bash
# macrift — Terminal setup (iTerm2 / Ghostty / Shell)

terminal_menu() {
    while true; do
        clear
        set_title "macrift > terminal"
        local choice
        choice=$(show_menu "Terminal Setup" \
            "iTerm2 — install + import config" \
            "Ghostty — install + copy config" \
            "Shell setup (Starship + FastFetch)" \
            "Back")

        case "$choice" in
            1) setup_iterm2 ;;
            2) setup_ghostty ;;
            3) setup_shell ;;
            0) return ;;
            *) ;;
        esac
    done
}

setup_iterm2() {
    divider "iTerm2"

    if ! brew_install "iterm2" "cask"; then return; fi

    local config_source="$MACRIFT_DIR/config/iterm2/profile.json"
    if [[ ! -f "$config_source" ]]; then
        log_warn "No iTerm2 profile found in config/iterm2/profile.json"
        log_info "You can add your profile there and re-run this"
        return
    fi

    if confirm "Import iTerm2 profile?"; then
        # Tell iTerm2 to use custom prefs folder
        defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$MACRIFT_DIR/config/iterm2"
        defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
        log_ok "iTerm2 configured to load profile from macrift config"
    fi
}

setup_ghostty() {
    divider "Ghostty"

    if ! brew_install "ghostty" "cask"; then return; fi

    local config_source="$MACRIFT_DIR/config/ghostty/config"
    local config_target="$HOME/.config/ghostty/config"

    if [[ ! -f "$config_source" ]]; then
        log_warn "No Ghostty config found in config/ghostty/config"
        log_info "You can add your config there and re-run this"
        return
    fi

    if confirm "Copy Ghostty config?"; then
        copy_config "$config_source" "$config_target"
        log_ok "Ghostty configured"
    fi
}

setup_shell() {
    divider "Shell Setup"

    local choice
    choice=$(show_menu "Shell Components" \
        "Starship prompt" \
        "FastFetch" \
        "Copy .zshrc" \
        "All of the above" \
        "Back")

    case "$choice" in
        1) install_starship ;;
        2) install_fastfetch ;;
        3) install_zshrc ;;
        4) install_starship; install_fastfetch; install_zshrc ;;
        0) return ;;
        *) ;;
    esac
}

install_starship() {
    if ! brew_install "starship"; then return; fi

    local config_source="$MACRIFT_DIR/config/shell/starship.toml"
    local config_target="$HOME/.config/starship.toml"

    if [[ -f "$config_source" ]]; then
        if confirm "Copy Starship config?"; then
            copy_config "$config_source" "$config_target"
        fi
    else
        log_info "Add your starship.toml to config/shell/ to auto-import"
    fi

    # Ensure starship init is in .zshrc
    if ! grep -q 'eval "$(starship init zsh)"' "$HOME/.zshrc" 2>/dev/null; then
        echo 'eval "$(starship init zsh)"' >> "$HOME/.zshrc"
        log_ok "Added Starship init to .zshrc"
    else
        log_skip "Starship already in .zshrc"
    fi
}

install_fastfetch() {
    if ! brew_install "fastfetch"; then return; fi

    local config_source="$MACRIFT_DIR/config/shell/fastfetch.jsonc"
    local config_target="$HOME/.config/fastfetch/config.jsonc"

    if [[ -f "$config_source" ]]; then
        if confirm "Copy FastFetch config?"; then
            copy_config "$config_source" "$config_target"
        fi
    else
        log_info "Add your fastfetch.jsonc to config/shell/ to auto-import"
    fi
}

install_zshrc() {
    local config_source="$MACRIFT_DIR/config/shell/.zshrc"
    local config_target="$HOME/.zshrc"

    if [[ ! -f "$config_source" ]]; then
        log_warn "No .zshrc found in config/shell/.zshrc"
        log_info "Add your .zshrc there and re-run this"
        return
    fi

    if confirm "Replace .zshrc? (current will be backed up)"; then
        copy_config "$config_source" "$config_target"
        log_ok ".zshrc installed (restart shell to apply)"
    fi
}
