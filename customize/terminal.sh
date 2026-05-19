#!/usr/bin/env bash
# macrift — Terminal setup (iTerm2 / Ghostty / Shell)

ITERM2_DOMAIN="com.googlecode.iterm2"

terminal_menu() {
    crumb_push "Terminal"
    while true; do
        clear

        local choice
        choice=$(show_menu "Terminal" \
            "iTerm2" \
            "Ghostty" \
            "Back")

        case "$choice" in
            1) setup_iterm2 ;;
            2) setup_ghostty ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

setup_iterm2() {
    crumb_push "iTerm2"
    if ! brew_install "iterm2" "cask"; then crumb_pop; return; fi

    local config_dir="$MACRIFT_DIR/config/iterm2"
    local config_plist="$config_dir/iterm2.plist"
    local dyn_profiles_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
    local domain="$ITERM2_DOMAIN"

    mkdir -p "$config_dir"

    while true; do
        clear


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
            2) _iterm2_system_tweaks; wait_enter ;;
            3)
                if [[ "$MACRIFT_DRY_RUN" == true ]]; then
                    log_info "Dry run — would export iTerm2 settings"
                else
                    defaults export "$domain" "$config_plist"
                    log_ok "Settings exported to config/iterm2/iterm2.plist"
                fi
                wait_enter
                ;;
            4)
                if [[ ! -f "$config_plist" ]]; then
                    log_err "No settings found in config/iterm2/iterm2.plist"
                    log_info "Run export first to save your current settings"
                    wait_enter
                    continue
                fi
                if [[ "$MACRIFT_DRY_RUN" == true ]]; then
                    log_info "Dry run — would import iTerm2 settings"
                elif confirm "Import iTerm2 settings? (restart iTerm2 to apply)"; then
                    defaults import "$domain" "$config_plist"
                    defaults delete "$domain" PrefsCustomFolder 2>/dev/null || true
                    defaults delete "$domain" LoadPrefsFromCustomFolder 2>/dev/null || true
                    log_ok "Settings imported — restart iTerm2 to apply"
                fi
                wait_enter
                ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
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

    _ensure_nerd_font

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
        disown  # detach subprocess so it survives macrift's exit
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
        wait_enter
        return
    fi

    if confirm "Copy Ghostty config?"; then
        copy_config "$config_source" "$config_target"
        _ghostty_install_themes
        log_ok "Ghostty configured"
    fi
    wait_enter
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
    crumb_push "Shell"
    while true; do
        clear


        local choice
        choice=$(show_menu "Shell" \
            "Full setup (Zinit + Starship + .zshrc)" \
            "---" \
            "Starship prompt only" \
            "Starship preset" \
            "Copy .zshrc only" \
            "Catppuccin theme" \
            "Back")

        case "$choice" in
            1) _ensure_nerd_font; install_zinit; install_starship; starship_preset; install_zshrc ;;
            2) install_starship ;;
            3) starship_preset ;;
            4) install_zshrc ;;
            5) apply_catppuccin ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

_ensure_nerd_font() {
    if fc-list 2>/dev/null | grep -qi "FiraCode Nerd Font" || \
       ls "$HOME/Library/Fonts"/FiraCodeNerdFont* &>/dev/null || \
       ls "/Library/Fonts"/FiraCodeNerdFont* &>/dev/null; then
        return
    fi
    log_warn "FiraCode Nerd Font not found (required for icons)"
    if confirm "Install font-fira-code-nerd-font via Homebrew?"; then
        brew_install "font-fira-code-nerd-font" "cask"
    fi
}

install_zinit() {
    local zinit_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"

    if [[ -d "$zinit_dir" ]]; then
        log_skip "Zinit already installed"
        return
    fi

    log_info "Zinit — fast Zsh plugin manager"
    log_info "Manages autosuggestions, syntax highlighting, and completions"

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install Zinit"
        return
    fi

    if ! confirm "Install Zinit?"; then return; fi

    if ! command -v git &>/dev/null; then
        log_err "Git required — install Xcode Command Line Tools first"
        return
    fi

    mkdir -p "$(dirname "$zinit_dir")"
    if run_with_spinner "Installing Zinit..." git clone https://github.com/zdharma-continuum/zinit.git "$zinit_dir"; then
        log_ok "Zinit installed"
    else
        log_err "Zinit installation failed"
    fi
}

install_starship() {
    if ! brew_install "starship"; then return; fi

    # Ensure starship init is in .zshrc
    if ! grep -q 'eval "$(starship init zsh)"' "$HOME/.zshrc" 2>/dev/null; then
        echo 'eval "$(starship init zsh)"' >> "$HOME/.zshrc"
        log_ok "Added Starship init to .zshrc"
    else
        log_skip "Starship already in .zshrc"
    fi
}

starship_preset() {
    if ! command -v starship &>/dev/null; then
        log_warn "Starship not installed"
        if confirm "Install Starship?"; then
            brew_install "starship" || return 0
        else
            return 0
        fi
    fi

    local config_target="$HOME/.config/starship.toml"

    # preset_id:label
    local presets=(
        "nerd-font:Nerd Font Symbols"
        "no-nerd-font:No Nerd Fonts"
        "bracketed-segments:Bracketed Segments"
        "plain-text:Plain Text Symbols"
        "no-runtimes:No Runtime Versions"
        "no-empty-icons:No Empty Icons"
        "pure-preset:Pure Prompt"
        "pastel-powerline:Pastel Powerline"
        "tokyo-night:Tokyo Night"
        "gruvbox-rainbow:Gruvbox Rainbow"
        "jetpack:Jetpack"
        "catppuccin-powerline:Catppuccin Powerline"
    )

    local labels=()
    local ids=()
    for entry in "${presets[@]}"; do
        ids+=("${entry%%:*}")
        labels+=("${entry#*:}")
    done

    local choice
    choice=$(show_menu "Starship Presets" "${labels[@]}" "Back")
    [[ "$choice" == "0" || -z "$choice" ]] && return

    local idx=$((choice - 1))
    local preset_id="${ids[$idx]}"
    local preset_label="${labels[$idx]}"

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would apply preset '$preset_label'"
        wait_enter
        return
    fi

    if confirm "Apply '$preset_label'? (current config will be backed up)"; then
        backup_file "$config_target"
        if starship preset "$preset_id" > "$config_target" 2>/dev/null; then
            log_ok "'$preset_label' applied"
            log_info "Restart shell to see changes"
        else
            log_err "Failed to apply preset"
        fi
    fi
    wait_enter
}

setup_fastfetch() {
    clear

    if ! command -v fastfetch &>/dev/null; then
        log_warn "FastFetch not found"
        if ! brew_install "fastfetch"; then return; fi
    fi

    apply_fastfetch_config
    wait_enter
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
                escaped_format=$(printf '%s' "$host_format" | sed 's/[&/\.*^$[\]]/\\&/g')
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

apply_catppuccin() {
    crumb_push "Catppuccin"
    clear
    printf '\n'
    printf '  %bApply Catppuccin Mocha to shell tools:%b\n\n' "$BOLD" "$RESET"
    printf '  %b›%b  Starship prompt colors\n' "$CYAN" "$RESET"
    printf '  %b›%b  fzf / fzf-tab search colors\n' "$CYAN" "$RESET"
    printf '  %b›%b  bat syntax highlighting\n' "$CYAN" "$RESET"
    printf '  %b›%b  zsh-autosuggestions hint color\n' "$CYAN" "$RESET"
    printf '  %b›%b  eza file colors\n' "$CYAN" "$RESET"
    printf '\n'

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would apply Catppuccin theme"
        wait_enter
    elif ! confirm "Apply Catppuccin Mocha?"; then
        :
    else
        local applied=0

        # Shell colors (fzf, bat, autosuggestions, eza)
        local theme_source="$MACRIFT_DIR/config/shell/catppuccin.zsh"
        local theme_target="$HOME/.config/zsh/catppuccin.zsh"
        if [[ -f "$theme_source" ]]; then
            mkdir -p "$HOME/.config/zsh"
            copy_config "$theme_source" "$theme_target"
            log_ok "Shell colors (fzf, bat, autosuggestions, eza)"
            applied=$((applied + 1))
        else
            log_err "catppuccin.zsh not found in config/shell/"
        fi

        # Starship palette
        local starship_target="$HOME/.config/starship.toml"
        if [[ -f "$starship_target" ]]; then
            if grep -q 'catppuccin_mocha' "$starship_target"; then
                log_skip "Starship already has Catppuccin palette"
            else
                _starship_apply_catppuccin "$starship_target"
                log_ok "Starship prompt"
                applied=$((applied + 1))
            fi
        else
            log_warn "No starship.toml found — install Starship first"
        fi

        printf '\n'
        log_ok "Catppuccin applied to $applied components (restart shell)"
        wait_enter
    fi
    crumb_pop
}

_starship_apply_catppuccin() {
    local target="$1"

    # Set palette directive
    if grep -q '^palette' "$target"; then
        sed -i '' 's/^palette.*/palette = "catppuccin_mocha"/' "$target"
    else
        sed -i '' '1s/^/palette = "catppuccin_mocha"\n/' "$target"
    fi

    # Update module styles
    sed -i '' 's/style = "bold cyan"/style = "bold lavender"/' "$target"
    sed -i '' 's/style = "bold purple"/style = "bold mauve"/' "$target"
    sed -i '' 's/style = "bold red"/style = "bold maroon"/' "$target"
    sed -i '' 's/style = "bold yellow"/style = "bold peach"/' "$target"

    # Append palette if not present
    cat >> "$target" << 'PALETTE'

[palettes.catppuccin_mocha]
rosewater = "#f5e0dc"
flamingo = "#f2cdcd"
pink = "#f5c2e7"
mauve = "#cba6f7"
red = "#f38ba8"
maroon = "#eba0ac"
peach = "#fab387"
yellow = "#f9e2af"
green = "#a6e3a1"
teal = "#94e2d5"
sky = "#89dceb"
sapphire = "#74c7ec"
blue = "#89b4fa"
lavender = "#b4befe"
text = "#cdd6f4"
subtext1 = "#bac2de"
subtext0 = "#a6adc8"
overlay2 = "#9399b2"
overlay1 = "#7f849c"
overlay0 = "#6c7086"
surface2 = "#585b70"
surface1 = "#45475a"
surface0 = "#313244"
base = "#1e1e2e"
mantle = "#181825"
crust = "#11111b"
PALETTE
}
