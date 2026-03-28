#!/usr/bin/env bash
# macrift — Terminal setup (iTerm2 / Ghostty / Shell)

terminal_menu() {
    while true; do
        clear
        set_title "macrift > terminal"
        local choice
        choice=$(show_menu "Terminal" \
            "iTerm2" \
            "Ghostty" \
            "Back")

        case "$choice" in
            1) setup_iterm2 ;;
            2) setup_ghostty ;;
            0) return ;;
            *) ;;
        esac
    done
}

setup_iterm2() {
    divider "iTerm2"

    if ! brew_install "iterm2" "cask"; then return; fi

    local config_dir="$MACRIFT_DIR/config/iterm2"
    local config_plist="$config_dir/iterm2.plist"

    mkdir -p "$config_dir"

    local choice
    choice=$(show_menu "iTerm2" \
        "Export current settings to macrift config" \
        "Import settings from macrift config" \
        "Back")

    case "$choice" in
        1)
            defaults export com.googlecode.iterm2 "$config_plist"
            log_ok "Settings exported to config/iterm2/iterm2.plist"
            ;;
        2)
            if [[ ! -f "$config_plist" ]]; then
                log_err "No settings found in config/iterm2/iterm2.plist"
                log_info "Run export first to save your current settings"
                return
            fi
            if confirm "Import iTerm2 settings? (restart iTerm2 to apply)"; then
                defaults import com.googlecode.iterm2 "$config_plist"
                # Remove stale custom folder setting that causes startup errors
                defaults delete com.googlecode.iterm2 PrefsCustomFolder 2>/dev/null || true
                defaults delete com.googlecode.iterm2 LoadPrefsFromCustomFolder 2>/dev/null || true
                log_ok "Settings imported — restart iTerm2 to apply"
            fi
            ;;
        0) return ;;
    esac
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

shell_menu() {
    while true; do
        clear
        set_title "macrift > shell"

        local choice
        choice=$(show_menu "Shell" \
            "Starship prompt" \
            "Copy .zshrc" \
            "Both" \
            "Back")

        case "$choice" in
            1) install_starship ;;
            2) install_zshrc ;;
            3) install_starship; install_zshrc ;;
            0) return ;;
            *) ;;
        esac
    done
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

    local config_source="$MACRIFT_DIR/config/shell/config.jsonc"
    local config_target="$HOME/.config/fastfetch/config.jsonc"

    if [[ -f "$config_source" ]]; then
        if confirm "Copy FastFetch config?"; then
            copy_config "$config_source" "$config_target"
        fi
    else
        log_info "Add your config.jsonc to config/shell/ to auto-import"
    fi
}

fastfetch_menu() {
    while true; do
        clear
        set_title "macrift > fastfetch"
        local choice
        choice=$(show_menu "FastFetch" \
            "Install FastFetch" \
            "Apply config from macrift" \
            "Back")

        case "$choice" in
            1) install_fastfetch ;;
            2) apply_fastfetch_config ;;
            0) return ;;
            *) ;;
        esac
    done
}

apply_fastfetch_config() {
    divider "FastFetch Config"

    local config_source="$MACRIFT_DIR/config/shell/config.jsonc"
    local config_target="$HOME/.config/fastfetch/config.jsonc"

    if [[ ! -f "$config_source" ]]; then
        log_err "No config found at config/shell/config.jsonc"
        return
    fi

    # Warn if host format is hardcoded to a specific model
    if grep -q '"format"' "$config_source" && grep -A1 '"type": "host"' "$config_source" | grep -q '"format"'; then
        local host_format
        host_format=$(grep -A2 '"type": "host"' "$config_source" | grep '"format"' | sed 's/.*"format": *"\(.*\)".*/\1/')
        if [[ "$host_format" != "{name}" && -n "$host_format" ]]; then
            log_warn "Host is hardcoded to: $host_format"
            if confirm "Replace with dynamic {name}?"; then
                sed -i '' "s|\"format\": \"$host_format\"|\"format\": \"{name}\"|" "$config_source"
                log_ok "Fixed — will now show actual model name"
            fi
        fi
    fi

    if confirm "Copy FastFetch config?"; then
        copy_config "$config_source" "$config_target"
        # Copy logo file if present
        local logo_source="$MACRIFT_DIR/config/shell/cat.txt"
        local logo_target="$HOME/.config/fastfetch/cat.txt"
        if [[ -f "$logo_source" ]]; then
            copy_config "$logo_source" "$logo_target"
        fi
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
