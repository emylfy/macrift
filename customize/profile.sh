#!/usr/bin/env bash
# macrift — Profile save/restore

profile_menu() {
    crumb_push "Profile"
    while true; do
        clear
        set_title "macrift > profile"
        local choice
        choice=$(show_menu "Profile" \
            "Save setup" \
            "Restore setup" \
            "Back")

        case "$choice" in
            1) save_profile ;;
            2) restore_profile ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

# Save profile to chosen location
save_profile() {
    clear
    printf '\n'
    printf '  %bSave your current setup to use on another Mac.%b\n\n' "$DIM" "$RESET"

    _profile_detect

    if ! confirm "Save all detected items?"; then return; fi

    local icloud_dir="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
    local dest_name="macrift-profile"

    local choice
    choice=$(show_menu "Save to" \
        "Desktop" \
        "Documents" \
        "iCloud Drive" \
        "Back")

    local save_dir=""
    case "$choice" in
        1) save_dir="$HOME/Desktop/$dest_name" ;;
        2) save_dir="$HOME/Documents/$dest_name" ;;
        3)
            if [[ -d "$icloud_dir" ]]; then
                save_dir="$icloud_dir/$dest_name"
            else
                log_err "iCloud Drive not available"
                wait_enter
                return
            fi
            ;;
        0) return ;;
        *) return ;;
    esac

    mkdir -p "$save_dir"
    printf '\n'
    _profile_export "$save_dir"
    wait_enter
}

# Restore from saved profile
restore_profile() {
    clear
    printf '\n'
    printf '  %bRestore settings from a saved profile.%b\n\n' "$DIM" "$RESET"

    local icloud_dir="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
    local dest_name="macrift-profile"

    # Find which locations have a profile
    local locations=() location_paths=()
    if [[ -d "$HOME/Desktop/$dest_name" ]] && [[ -n "$(ls -A "$HOME/Desktop/$dest_name" 2>/dev/null)" ]]; then
        locations+=("Desktop")
        location_paths+=("$HOME/Desktop/$dest_name")
    fi
    if [[ -d "$HOME/Documents/$dest_name" ]] && [[ -n "$(ls -A "$HOME/Documents/$dest_name" 2>/dev/null)" ]]; then
        locations+=("Documents")
        location_paths+=("$HOME/Documents/$dest_name")
    fi
    if [[ -d "$icloud_dir/$dest_name" ]] && [[ -n "$(ls -A "$icloud_dir/$dest_name" 2>/dev/null)" ]]; then
        locations+=("iCloud Drive")
        location_paths+=("$icloud_dir/$dest_name")
    fi

    if [[ ${#locations[@]} -eq 0 ]]; then
        log_warn "No saved profile found"
        log_info "Save your setup first (Desktop, Documents, or iCloud Drive)"
        wait_enter
        return
    fi

    local restore_dir=""
    if [[ ${#locations[@]} -eq 1 ]]; then
        restore_dir="${location_paths[0]}"
        log_info "Found profile in ${locations[0]}"
    else
        local choice
        choice=$(show_menu "Restore from" "${locations[@]}" "Back")
        [[ "$choice" == "0" ]] && return
        restore_dir="${location_paths[$((choice - 1))]}"
    fi

    printf '\n'
    _profile_import "$restore_dir"
    wait_enter
}

# --- Helpers ---

# Show what's available to export
_profile_detect() {
    printf '  %bDetected on this Mac:%b\n' "$BOLD" "$RESET"

    command -v brew &>/dev/null \
        && printf '  %b✓%b  Homebrew packages\n' "$GREEN" "$RESET" \
        || printf '  %b-%b  Homebrew (not installed)\n' "$DIM" "$RESET"

    printf '  %b✓%b  macOS defaults (Dock, Finder, Keyboard, Screenshots)\n' "$GREEN" "$RESET"

    [[ -f "$HOME/.zshrc" ]] \
        && printf '  %b✓%b  Dotfiles (.zshrc, starship, ghostty, fastfetch)\n' "$GREEN" "$RESET" \
        || printf '  %b-%b  Dotfiles (none found)\n' "$DIM" "$RESET"

    local has_editor=false
    for p in "$HOME/Library/Application Support/Code/User/settings.json" \
             "$HOME/Library/Application Support/Cursor/User/settings.json" \
             "$HOME/.config/zed/settings.json"; do
        [[ -f "$p" ]] && has_editor=true && break
    done
    $has_editor && printf '  %b✓%b  Editor settings (VSCode, Cursor, Zed)\n' "$GREEN" "$RESET" \
                || printf '  %b-%b  Editor settings (none found)\n' "$DIM" "$RESET"

    defaults read com.googlecode.iterm2 &>/dev/null 2>&1 \
        && printf '  %b✓%b  iTerm2 settings\n' "$GREEN" "$RESET"

    command -v dockutil &>/dev/null \
        && printf '  %b✓%b  Dock layout\n' "$GREEN" "$RESET"

    [[ -d "/Applications/Raycast.app" ]] \
        && printf '  %b✓%b  Raycast extensions\n' "$GREEN" "$RESET" \
        || printf '  %b-%b  Raycast (not installed)\n' "$DIM" "$RESET"

    printf '\n'
}

# Export everything to a target directory
_profile_export() {
    local target="$1"
    local exported=0

    # Brew
    if command -v brew &>/dev/null; then
        log_info "Homebrew packages..."
        if brew bundle dump --file="$target/Brewfile" --force 2>/dev/null; then
            log_ok "Brewfile"
            exported=$((exported + 1))
        else
            log_warn "Brewfile export failed"
        fi
    fi

    # Defaults
    log_info "macOS defaults..."
    local defaults_dir="$target/defaults"
    mkdir -p "$defaults_dir"
    local domains=(
        "com.apple.dock"
        "com.apple.finder"
        "com.apple.screencapture"
        "com.apple.desktopservices"
        "com.apple.LaunchServices"
        "NSGlobalDomain"
    )
    for domain in "${domains[@]}"; do
        defaults export "$domain" "$defaults_dir/$domain.plist" 2>/dev/null && exported=$((exported + 1))
    done
    log_ok "Defaults (${#domains[@]} domains)"

    # Dotfiles
    log_info "Dotfiles..."
    local dotfiles_dir="$target/dotfiles"
    mkdir -p "$dotfiles_dir"
    [[ -f "$HOME/.zshrc" ]] && cp "$HOME/.zshrc" "$dotfiles_dir/.zshrc" && exported=$((exported + 1))
    if [[ -f "$HOME/.config/starship.toml" ]]; then
        mkdir -p "$dotfiles_dir/.config"
        cp "$HOME/.config/starship.toml" "$dotfiles_dir/.config/starship.toml" && exported=$((exported + 1))
    fi
    if [[ -d "$HOME/.config/fastfetch" ]]; then
        mkdir -p "$dotfiles_dir/.config/fastfetch"
        cp -r "$HOME/.config/fastfetch/"* "$dotfiles_dir/.config/fastfetch/" 2>/dev/null && exported=$((exported + 1))
    fi
    if [[ -f "$HOME/.config/ghostty/config" ]]; then
        mkdir -p "$dotfiles_dir/.config/ghostty"
        cp "$HOME/.config/ghostty/config" "$dotfiles_dir/.config/ghostty/config" && exported=$((exported + 1))
    fi
    log_ok "Dotfiles"

    # Editors
    log_info "Editor settings..."
    local editors_dir="$target/editors"
    mkdir -p "$editors_dir"
    local editor_names=("vscode" "cursor" "zed")
    local editor_paths=(
        "$HOME/Library/Application Support/Code/User/settings.json"
        "$HOME/Library/Application Support/Cursor/User/settings.json"
        "$HOME/.config/zed/settings.json"
    )
    for ((i=0; i<${#editor_names[@]}; i++)); do
        if [[ -f "${editor_paths[$i]}" ]]; then
            cp "${editor_paths[$i]}" "$editors_dir/${editor_names[$i]}-settings.json"
            exported=$((exported + 1))
        fi
    done
    log_ok "Editor settings"

    # iTerm2
    if defaults read com.googlecode.iterm2 &>/dev/null 2>&1; then
        log_info "iTerm2..."
        defaults export com.googlecode.iterm2 "$target/iterm2.plist" 2>/dev/null && exported=$((exported + 1))
        log_ok "iTerm2"
    fi

    # Dock layout
    if command -v dockutil &>/dev/null; then
        dockutil --list > "$target/dock-layout.txt" 2>/dev/null && exported=$((exported + 1))
        log_ok "Dock layout"
    fi

    # Raycast
    if [[ -d "/Applications/Raycast.app" ]]; then
        log_info "Raycast..."
        local latest_rayconfig
        latest_rayconfig=$(find "$HOME/Desktop" "$HOME/Downloads" "$HOME/Documents" \
            -maxdepth 1 -name "*.rayconfig" 2>/dev/null | sort -t/ -k1 | tail -1)
        if [[ -n "$latest_rayconfig" ]]; then
            cp "$latest_rayconfig" "$target/raycast.rayconfig"
            log_ok "Raycast ($(basename "$latest_rayconfig"))"
            exported=$((exported + 1))
        else
            log_warn "No .rayconfig found — export from Raycast: Cmd+Space → Export Settings & Data"
        fi
    fi

    printf '\n'
    log_ok "Saved $exported items → $target"
}

# Import from a source directory (with multiselect)
_profile_import() {
    local source="$1"

    printf '  %bFound in profile:%b\n' "$BOLD" "$RESET"

    local available=()
    if [[ -f "$source/Brewfile" ]]; then
        available+=("Homebrew packages")
        printf '  %b✓%b  Homebrew packages (Brewfile)\n' "$GREEN" "$RESET"
    fi
    if [[ -d "$source/defaults" ]]; then
        available+=("macOS defaults")
        local plist_count
        plist_count=$(find "$source/defaults" -name "*.plist" 2>/dev/null | wc -l | tr -d ' ')
        printf '  %b✓%b  macOS defaults (%s domains)\n' "$GREEN" "$RESET" "$plist_count"
    fi
    if [[ -d "$source/dotfiles" ]]; then
        available+=("Dotfiles")
        printf '  %b✓%b  Dotfiles (.zshrc, starship, ghostty, fastfetch)\n' "$GREEN" "$RESET"
    fi
    if [[ -d "$source/editors" ]]; then
        available+=("Editor settings")
        local editors_found=""
        [[ -f "$source/editors/vscode-settings.json" ]] && editors_found+="VSCode "
        [[ -f "$source/editors/cursor-settings.json" ]] && editors_found+="Cursor "
        [[ -f "$source/editors/zed-settings.json" ]] && editors_found+="Zed "
        printf '  %b✓%b  Editor settings (%s)\n' "$GREEN" "$RESET" "${editors_found% }"
    fi
    if [[ -f "$source/iterm2.plist" ]]; then
        available+=("iTerm2 settings")
        printf '  %b✓%b  iTerm2 settings\n' "$GREEN" "$RESET"
    fi
    if [[ -f "$source/raycast.rayconfig" ]]; then
        available+=("Raycast extensions")
        printf '  %b✓%b  Raycast extensions\n' "$GREEN" "$RESET"
    fi

    if [[ ${#available[@]} -eq 0 ]]; then
        printf '\n'
        log_err "No recognizable profile data found"
        return
    fi

    printf '\n'
    printf '  %bSelect what to restore:%b\n\n' "$DIM" "$RESET"

    local selected
    selected=$(show_multiselect "Restore" "${available[@]}")
    [[ -z "$selected" ]] && return

    # Homebrew
    if echo "$selected" | grep -qF "Homebrew"; then
        log_info "Restoring Homebrew packages..."
        if brew bundle --file="$source/Brewfile"; then
            log_ok "Homebrew packages restored"
        else
            log_warn "Some Homebrew packages failed"
        fi
    fi

    # Defaults
    if echo "$selected" | grep -qF "macOS defaults"; then
        log_info "Restoring macOS defaults..."
        for plist in "$source/defaults/"*.plist; do
            [[ -f "$plist" ]] || continue
            local domain
            domain=$(basename "$plist" .plist)
            if defaults import "$domain" "$plist" 2>/dev/null; then
                log_ok "$domain"
            else
                log_warn "Failed: $domain"
            fi
        done
        if confirm "Restart Dock, Finder, SystemUIServer?"; then
            killall Dock Finder SystemUIServer 2>/dev/null || true
            log_ok "Services restarted"
        fi
    fi

    # Dotfiles
    if echo "$selected" | grep -qF "Dotfiles"; then
        log_info "Restoring dotfiles..."
        local df="$source/dotfiles"
        [[ -f "$df/.zshrc" ]] && backup_file "$HOME/.zshrc" && cp "$df/.zshrc" "$HOME/.zshrc"
        if [[ -f "$df/.config/starship.toml" ]]; then
            mkdir -p "$HOME/.config"
            backup_file "$HOME/.config/starship.toml"
            cp "$df/.config/starship.toml" "$HOME/.config/starship.toml"
        fi
        if [[ -d "$df/.config/fastfetch" ]]; then
            mkdir -p "$HOME/.config/fastfetch"
            cp -r "$df/.config/fastfetch/"* "$HOME/.config/fastfetch/"
        fi
        if [[ -f "$df/.config/ghostty/config" ]]; then
            mkdir -p "$HOME/.config/ghostty"
            backup_file "$HOME/.config/ghostty/config"
            cp "$df/.config/ghostty/config" "$HOME/.config/ghostty/config"
        fi
        log_ok "Dotfiles restored"
    fi

    # Editors
    if echo "$selected" | grep -qF "Editor settings"; then
        log_info "Restoring editor settings..."
        local ed="$source/editors"
        local editor_names=("vscode" "cursor" "zed")
        local editor_targets=(
            "$HOME/Library/Application Support/Code/User/settings.json"
            "$HOME/Library/Application Support/Cursor/User/settings.json"
            "$HOME/.config/zed/settings.json"
        )
        for ((i=0; i<${#editor_names[@]}; i++)); do
            if [[ -f "$ed/${editor_names[$i]}-settings.json" ]]; then
                mkdir -p "$(dirname "${editor_targets[$i]}")"
                backup_file "${editor_targets[$i]}"
                cp "$ed/${editor_names[$i]}-settings.json" "${editor_targets[$i]}"
                log_ok "${editor_names[$i]} settings restored"
            fi
        done
    fi

    # iTerm2
    if echo "$selected" | grep -qF "iTerm2"; then
        log_info "Restoring iTerm2 settings..."
        if defaults import com.googlecode.iterm2 "$source/iterm2.plist" 2>/dev/null; then
            log_ok "iTerm2 settings restored"
        else
            log_warn "iTerm2 import failed"
        fi
    fi

    # Raycast
    if echo "$selected" | grep -qF "Raycast"; then
        log_info "Importing Raycast extensions..."
        if open "$source/raycast.rayconfig" 2>/dev/null; then
            log_ok "Raycast import opened — confirm in Raycast"
        else
            log_warn "Raycast import failed — is Raycast installed?"
        fi
    fi

    printf '\n'
    log_ok "Restore complete"
}
