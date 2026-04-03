#!/usr/bin/env bash
# macrift — Full profile export/import

profile_menu() {
    crumb_push "Profile"
    while true; do
        clear
        set_title "macrift > profile"
        local choice
        choice=$(show_menu "Profile Backup" \
            "Export profile" \
            "Import profile" \
            "Back")

        case "$choice" in
            1) export_profile ;;
            2) import_profile ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

export_profile() {
    clear

    local default_path
    default_path="$HOME/Desktop/macrift-profile-$(date +%Y%m%d)"
    printf '  %bSave directory (enter for default):%b\n' "$DIM" "$RESET"
    printf '  %b%s%b\n' "$DIM" "$default_path" "$RESET"
    prompt_path
    read -r profile_dir
    profile_dir="${profile_dir:-$default_path}"
    profile_dir="${profile_dir//\'/}"
    profile_dir="${profile_dir//\"/}"
    profile_dir="${profile_dir%% }"

    mkdir -p "$profile_dir"

    local exported=0

    # 1. Brew packages
    log_info "Exporting Homebrew packages..."
    if brew bundle dump --file="$profile_dir/Brewfile" --force 2>/dev/null; then
        log_ok "Brewfile exported"
        exported=$((exported + 1))
    else
        log_warn "Brewfile export failed"
    fi

    # 2. macOS defaults (key domains)
    log_info "Exporting macOS defaults..."
    local defaults_dir="$profile_dir/defaults"
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
        if defaults export "$domain" "$defaults_dir/$domain.plist" 2>/dev/null; then
            exported=$((exported + 1))
        fi
    done
    log_ok "Defaults exported (${#domains[@]} domains)"

    # 3. Dotfiles
    log_info "Exporting dotfiles..."
    local dotfiles_dir="$profile_dir/dotfiles"
    mkdir -p "$dotfiles_dir"

    [[ -f "$HOME/.zshrc" ]] && cp "$HOME/.zshrc" "$dotfiles_dir/.zshrc" && exported=$((exported + 1))
    [[ -f "$HOME/.config/starship.toml" ]] && mkdir -p "$dotfiles_dir/.config" && \
        cp "$HOME/.config/starship.toml" "$dotfiles_dir/.config/starship.toml" && exported=$((exported + 1))
    [[ -d "$HOME/.config/fastfetch" ]] && mkdir -p "$dotfiles_dir/.config/fastfetch" && \
        cp -r "$HOME/.config/fastfetch/"* "$dotfiles_dir/.config/fastfetch/" 2>/dev/null && exported=$((exported + 1))
    [[ -f "$HOME/.config/ghostty/config" ]] && mkdir -p "$dotfiles_dir/.config/ghostty" && \
        cp "$HOME/.config/ghostty/config" "$dotfiles_dir/.config/ghostty/config" && exported=$((exported + 1))
    log_ok "Dotfiles exported"

    # 4. Editor settings
    log_info "Exporting editor settings..."
    local editors_dir="$profile_dir/editors"
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
    log_ok "Editor settings exported"

    # 5. iTerm2 settings
    if defaults read com.googlecode.iterm2 &>/dev/null 2>&1; then
        log_info "Exporting iTerm2 settings..."
        defaults export com.googlecode.iterm2 "$profile_dir/iterm2.plist" 2>/dev/null && exported=$((exported + 1))
        log_ok "iTerm2 exported"
    fi

    # 6. Dock layout
    if command -v dockutil &>/dev/null; then
        dockutil --list > "$profile_dir/dock-layout.txt" 2>/dev/null && exported=$((exported + 1))
        log_ok "Dock layout exported"
    fi

    printf "\n"
    log_ok "Profile exported: $exported items → $profile_dir"
    wait_enter
}

import_profile() {
    clear

    printf '  %bDrag profile folder or type path%b\n' "$DIM" "$RESET"
    prompt_path
    read -r profile_dir
    profile_dir="${profile_dir//\'/}"
    profile_dir="${profile_dir//\"/}"
    profile_dir="${profile_dir%% }"

    if [[ ! -d "$profile_dir" ]]; then
        log_err "Directory not found: $profile_dir"
        wait_enter
        return
    fi

    # Show what's available
    local available=()
    [[ -f "$profile_dir/Brewfile" ]] && available+=("Homebrew packages")
    [[ -d "$profile_dir/defaults" ]] && available+=("macOS defaults")
    [[ -d "$profile_dir/dotfiles" ]] && available+=("Dotfiles (.zshrc, starship, etc.)")
    [[ -d "$profile_dir/editors" ]] && available+=("Editor settings")
    [[ -f "$profile_dir/iterm2.plist" ]] && available+=("iTerm2 settings")

    if [[ ${#available[@]} -eq 0 ]]; then
        log_err "No recognizable profile data found"
        wait_enter
        return
    fi

    local selected
    selected=$(show_multiselect "Import" "${available[@]}")

    if [[ -z "$selected" ]]; then
        log_info "Nothing selected"
        return
    fi

    local restored=0

    # Homebrew
    if echo "$selected" | grep -qF "Homebrew"; then
        log_info "Restoring Homebrew packages..."
        if brew bundle --file="$profile_dir/Brewfile"; then
            log_ok "Homebrew packages restored"
            restored=$((restored + 1))
        else
            log_warn "Some Homebrew packages failed"
        fi
    fi

    # Defaults
    if echo "$selected" | grep -qF "macOS defaults"; then
        log_info "Restoring macOS defaults..."
        for plist in "$profile_dir/defaults/"*.plist; do
            [[ -f "$plist" ]] || continue
            local domain
            domain=$(basename "$plist" .plist)
            if defaults import "$domain" "$plist" 2>/dev/null; then
                log_ok "$domain restored"
                restored=$((restored + 1))
            else
                log_warn "Failed: $domain"
            fi
        done
        killall Dock Finder SystemUIServer 2>/dev/null || true
    fi

    # Dotfiles
    if echo "$selected" | grep -qF "Dotfiles"; then
        log_info "Restoring dotfiles..."
        local df="$profile_dir/dotfiles"
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
        restored=$((restored + 1))
    fi

    # Editors
    if echo "$selected" | grep -qF "Editor settings"; then
        log_info "Restoring editor settings..."
        local ed="$profile_dir/editors"
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
                restored=$((restored + 1))
            fi
        done
    fi

    # iTerm2
    if echo "$selected" | grep -qF "iTerm2"; then
        log_info "Restoring iTerm2 settings..."
        if defaults import com.googlecode.iterm2 "$profile_dir/iterm2.plist" 2>/dev/null; then
            log_ok "iTerm2 settings restored"
            restored=$((restored + 1))
        else
            log_warn "iTerm2 import failed"
        fi
    fi

    printf "\n"
    log_ok "Profile import complete: $restored items restored"
    wait_enter
}
