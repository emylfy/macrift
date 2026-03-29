#!/usr/bin/env bash
# macrift — Terminal setup (iTerm2 / Ghostty / Shell)

ITERM2_DOMAIN="com.googlecode.iterm2"

terminal_menu() {
    while true; do
        clear
        set_title "macrift > terminal"
        local choice
        choice=$(show_menu "Terminal Emulator" \
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
    if ! brew_install "iterm2" "cask"; then return; fi

    local config_dir="$MACRIFT_DIR/config/iterm2"
    local config_plist="$config_dir/iterm2.plist"
    local dyn_profiles_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"

    mkdir -p "$config_dir"

    local choice
    choice=$(show_menu "iTerm2" \
        "Apply theme profile" \
        "Apply iTerm2 defaults" \
        "---" \
        "Export current settings to plist" \
        "Import settings from plist" \
        "Back")

    case "$choice" in
        1) _iterm2_install_profile "$config_dir" "$dyn_profiles_dir" ;;
        2) _iterm2_system_tweaks ;;
        3)
            if [[ "$MACRIFT_DRY_RUN" == true ]]; then
                log_info "Dry run — would export iTerm2 settings"
            else
                defaults export "$domain" "$config_plist"
                log_ok "Settings exported to config/iterm2/iterm2.plist"
            fi
            ;;
        4)
            if [[ ! -f "$config_plist" ]]; then
                log_err "No settings found in config/iterm2/iterm2.plist"
                log_info "Run export first to save your current settings"
                return
            fi
            if [[ "$MACRIFT_DRY_RUN" == true ]]; then
                log_info "Dry run — would import iTerm2 settings"
            elif confirm "Import iTerm2 settings? (restart iTerm2 to apply)"; then
                defaults import "$domain" "$config_plist"
                defaults delete "$domain" PrefsCustomFolder 2>/dev/null || true
                defaults delete "$domain" LoadPrefsFromCustomFolder 2>/dev/null || true
                log_ok "Settings imported — restart iTerm2 to apply"
            fi
            ;;
        0) return ;;
    esac
}

_iterm2_install_profile() {
    local config_dir="$1"
    local dyn_dir="$2"

    # Discover available profile JSONs
    local profiles=()
    local descriptions=()
    for f in "$config_dir"/*.json; do
        [[ -f "$f" ]] || continue
        local name
        name=$(grep -m1 '"Name"' "$f" | sed 's/.*"Name"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/' || basename "$f" .json)
        profiles+=("$f")
        descriptions+=("$name")
    done

    if [[ ${#profiles[@]} -eq 0 ]]; then
        log_err "No profile JSONs found in config/iterm2/"
        return
    fi

    local choice
    choice=$(show_menu "Choose Profile" "${descriptions[@]}" "Back")

    if [[ "$choice" == "0" || -z "$choice" ]]; then return; fi

    local idx=$((choice - 1))
    local selected="${profiles[$idx]}"
    local selected_name="${descriptions[$idx]}"

    # Install font if missing
    if ! fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font" && \
       ! ls "$HOME/Library/Fonts"/JetBrainsMonoNerdFont* &>/dev/null && \
       ! ls "/Library/Fonts"/JetBrainsMonoNerdFont* &>/dev/null; then
        log_info "JetBrainsMono Nerd Font not found"
        if confirm "Install font-jetbrains-mono-nerd-font via Homebrew?"; then
            brew_install "font-jetbrains-mono-nerd-font" "cask"
        else
            log_warn "Profile may fall back to Menlo without the Nerd Font"
        fi
    fi

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install '$selected_name' to DynamicProfiles"
        return
    fi

    mkdir -p "$dyn_dir"
    cp "$selected" "$dyn_dir/macrift-$(basename "$selected")"
    log_ok "'$selected_name' installed as Dynamic Profile"
    log_info "Restart iTerm2 to apply"

    # Set as default — iTerm2 overwrites defaults on quit,
    # so a background process writes the GUID after iTerm2 exits
    local guid
    guid=$(grep -m1 '"Guid"' "$selected" | sed 's/.*"Guid"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/')
    if [[ -n "$guid" ]]; then
        defaults write "$ITERM2_DOMAIN" "Default Bookmark Guid" -string "$guid"
        # Persist after iTerm2 quits (it overwrites defaults on exit)
        (while pgrep -q "iTerm2"; do sleep 2; done
         sleep 1
         defaults write "$ITERM2_DOMAIN" "Default Bookmark Guid" -string "$guid"
        ) &>/dev/null &
        disown
        log_ok "'$selected_name' set as default — restart iTerm2 to apply"
    fi
}

_iterm2_system_tweaks() {
    log_info "This applies recommended system-level iTerm2 preferences:"
    echo "  - Minimal UI chrome (no per-tab close, compact tabs)"
    echo "  - GPU renderer enabled"
    echo "  - Scroll wheel sends arrow keys in alternate screen"
    echo "  - Quit prompt disabled (sessions auto-close)"
    echo "  - Focus follows mouse"
    echo ""

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would apply system tweaks"
        return
    fi

    if ! confirm "Apply iTerm2 system tweaks?"; then return; fi

    local domain="$ITERM2_DOMAIN"

    # Appearance
    defaults write "$domain" TabStyleWithAutomaticOption -int 5
    defaults write "$domain" HideTab -bool false
    defaults write "$domain" ShowFullScreenTabBar -bool false
    defaults write "$domain" HideScrollbar -bool true
    defaults write "$domain" HideMenuBarInFullscreen -bool true

    # Performance
    defaults write "$domain" GPURendering -bool true
    defaults write "$domain" DisableWindowSizeSnap -bool true

    # Behavior
    defaults write "$domain" FocusFollowsMouse -bool true
    defaults write "$domain" QuitWhenAllWindowsClosed -bool false
    defaults write "$domain" PromptOnQuit -bool false
    defaults write "$domain" OnlyWhenMoreTabs -bool false
    defaults write "$domain" AlternateMouseScroll -bool true

    # Window
    defaults write "$domain" UseBorder -bool false
    defaults write "$domain" HideFromDockAndAppSwitcher -bool false

    log_ok "System tweaks applied — restart iTerm2"
}

setup_ghostty() {
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
        _ghostty_install_themes
        log_ok "Ghostty configured"
    fi
}

_ghostty_install_themes() {
    local themes_dir="$HOME/.config/ghostty/themes"
    local base_url="https://raw.githubusercontent.com/catppuccin/ghostty/main/themes"
    local needed=(catppuccin-mocha catppuccin-latte)

    mkdir -p "$themes_dir"

    for theme in "${needed[@]}"; do
        if [[ -f "$themes_dir/$theme" ]]; then
            continue
        fi
        if [[ "$MACRIFT_DRY_RUN" == true ]]; then
            log_info "Would download $theme"
            continue
        fi
        if curl -fsSL "$base_url/${theme}.conf" -o "$themes_dir/$theme"; then
            log_ok "Theme $theme installed"
        else
            log_err "Failed to download $theme"
        fi
    done
}

shell_menu() {
    while true; do
        clear
        set_title "macrift > shell"

        local choice
        choice=$(show_menu "Shell" \
            "Starship prompt" \
            "Copy .zshrc" \
            "Starship + .zshrc" \
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
            "Apply config" \
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
                # Escape regex metacharacters in the value before sed substitution
                local escaped_format
                escaped_format=$(printf '%s' "$host_format" | sed 's/[&/\.*^$[]/\\&/g')
                sed -i '' "s|\"format\": \"${escaped_format}\"|\"format\": \"{name}\"|" "$config_source"
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
