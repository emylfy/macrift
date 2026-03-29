#!/usr/bin/env bash
# macrift — Homebrew bundle installer

brew_menu() {
    while true; do
        clear
        set_title "macrift > brew"
        local choice
        choice=$(show_menu "Homebrew Bundles" \
            "Development" \
            "Utilities" \
            "Browsers" \
            "---" \
            "Communication" \
            "Media" \
            "Games" \
            "Fonts (Nerd Fonts)" \
            "---" \
            "Install ALL bundles" \
            "Backup (.brewbak)" \
            "Back")

        case "$choice" in
            1) install_bundle "Brewfile.dev" ;;
            2) install_bundle "Brewfile.utils" ;;
            3) install_bundle "Brewfile.browsers" ;;
            4) install_bundle "Brewfile.comm" ;;
            5) install_bundle "Brewfile.media" ;;
            6) install_bundle "Brewfile.games" ;;
            7) install_bundle "Brewfile.fonts" ;;
            8) install_all_bundles ;;
            9) brewbak_menu ;;
            0) return ;;
            *) ;;
        esac
    done
}

brewbak_menu() {
    while true; do
        clear
        set_title "macrift > brew > backup"
        local choice
        choice=$(show_menu "Backup (.brewbak)" \
            "Import from .brewbak" \
            "Export to .brewbak" \
            "Back")

        case "$choice" in
            1) import_brewbak ;;
            2) export_brewbak ;;
            0) return ;;
            *) ;;
        esac
    done
}

install_bundle() {
    local brewfile="$1"
    local path="$MACRIFT_DIR/config/$brewfile"

    if [[ ! -f "$path" ]]; then
        log_err "Brewfile not found: $path"
        return 1
    fi

    clear

    # Get installed packages once
    local installed
    installed=$(brew list --formula -1 2>/dev/null; brew list --cask -1 2>/dev/null)

    # Parse Brewfile — split into new, broken, and already installed
    local new_lines=()
    local new_labels=()
    local broken_casks=()
    local installed_count=0
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*#.*$ || -z "${line// /}" ]] && continue
        local name="" label=""
        if [[ "$line" =~ ^brew[[:space:]]+\"([^\"]+)\" ]]; then
            name="${BASH_REMATCH[1]}"
            label="$name"
        elif [[ "$line" =~ ^cask[[:space:]]+\"([^\"]+)\" ]]; then
            name="${BASH_REMATCH[1]}"
            label="$name (cask)"
        else
            continue
        fi
        if echo "$installed" | grep -qxF "$name"; then
            # For casks, verify the .app actually exists in /Applications
            if [[ "$line" =~ ^cask ]]; then
                # || true prevents set -e from triggering if find exits non-zero
                app_path=$(find "$(brew --prefix)/Caskroom"/"$name" -name "*.app" -maxdepth 3 2>/dev/null | head -1) || true
                if [[ -n "$app_path" ]]; then
                    appname=$(basename "$app_path")
                    if [[ ! -e "/Applications/$appname" ]]; then
                        # Registered in brew but .app is missing — queue for silent reinstall
                        broken_casks+=("$name")
                        continue
                    fi
                fi
            fi
            installed_count=$((installed_count + 1))
        else
            new_lines+=("$line")
            new_labels+=("$label")
        fi
    done < "$path"

    if [[ $installed_count -gt 0 ]]; then
        log_ok "$installed_count already installed"
    fi

    # Handle missing apps separately — ask user once, then fix silently
    if [[ ${#broken_casks[@]} -gt 0 ]]; then
        printf "\n"
        log_warn "${#broken_casks[@]} app(s) are missing from Applications"
        for cask in "${broken_casks[@]}"; do
            printf '  %b· %s%b\n' "$DIM" "$cask" "$RESET"
        done
        printf "\n"
        printf '  %bThis will reinstall the apps listed above.%b\n' "$DIM" "$RESET"
        printf "\n"
        if [[ "$MACRIFT_DRY_RUN" == true ]]; then
            log_info "Dry run — would reinstall broken casks"
        elif confirm "Fix them now?"; then
            printf "\n"
            for cask in "${broken_casks[@]}"; do
                log_info "Reinstalling $cask..."
                if brew reinstall --cask "$cask"; then
                    log_ok "$cask reinstalled"
                else
                    log_warn "Failed to reinstall $cask"
                fi
                printf "\n"
            done
            wait_enter
        fi
        printf "\n"
    fi

    if [[ ${#new_labels[@]} -eq 0 ]]; then
        log_ok "Everything installed"
        printf "\n"
        confirm "Back" || true
        return 0
    fi

    # Multiselect for new packages only
    local selected
    selected=$(show_multiselect "$brewfile" "${new_labels[@]}")

    if [[ -z "$selected" ]]; then
        log_info "Nothing selected"
        return 0
    fi

    # Build temp Brewfile with selected packages
    local tmp
    tmp=$(mktemp /tmp/macrift_brew_XXXXXX)

    for ((i=0; i<${#new_labels[@]}; i++)); do
        if echo "$selected" | grep -qxF "${new_labels[$i]}"; then
            echo "${new_lines[$i]}" >> "$tmp"
        fi
    done

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install:"
        while IFS= read -r line; do
            printf '  %b· %s%b\n' "$DIM" "$line" "$RESET"
        done < "$tmp"
        rm -f "$tmp"
        return 0
    fi

    log_info "Installing selected packages..."
    if brew bundle --file="$tmp"; then
        log_ok "All packages installed"
    else
        log_warn "Some packages failed to install"
    fi
    rm -f "$tmp"
    wait_enter
}

install_all_bundles() {
    if ! confirm "Install all bundles? (select packages in each)"; then
        return
    fi

    for brewfile in "$MACRIFT_DIR"/config/Brewfile.*; do
        if [[ -f "$brewfile" ]]; then
            install_bundle "$(basename "$brewfile")"
        fi
    done

    log_ok "All bundles done"
}

import_brewbak() {
    clear

    printf '  %bDrag file into terminal or type path%b\n' "$DIM" "$RESET"
    prompt_path
    read -r filepath

    # Strip quotes if dragged in
    filepath="${filepath//\'/}"
    filepath="${filepath//\"/}"
    # Strip trailing whitespace
    filepath="${filepath%% }"

    if [[ ! -f "$filepath" ]]; then
        log_err "File not found: $filepath"
        wait_enter
        return
    fi

    clear

    # Get installed packages
    local installed
    installed=$(brew list --formula -1 2>/dev/null; brew list --cask -1 2>/dev/null)

    # Parse brewbak — same format as Brewfile
    local new_lines=()
    local new_labels=()
    local installed_count=0
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*#.*$ || -z "${line// /}" ]] && continue
        local name="" label=""
        if [[ "$line" =~ ^brew[[:space:]]+\"([^\"]+)\" ]]; then
            name="${BASH_REMATCH[1]}"
            label="$name"
        elif [[ "$line" =~ ^cask[[:space:]]+\"([^\"]+)\" ]]; then
            name="${BASH_REMATCH[1]}"
            label="$name (cask)"
        elif [[ "$line" =~ ^tap[[:space:]]+\"([^\"]+)\" ]]; then
            name="${BASH_REMATCH[1]}"
            label="$name (tap)"
            new_lines+=("$line")
            new_labels+=("$label")
            continue
        else
            continue
        fi
        if echo "$installed" | grep -qxF "$name"; then
            # For casks, verify the .app actually exists in /Applications
            if [[ "$line" =~ ^cask ]]; then
                # || true prevents set -e from triggering if find exits non-zero
                app_path=$(find "$(brew --prefix)/Caskroom"/"$name" -name "*.app" -maxdepth 3 2>/dev/null | head -1) || true
                if [[ -n "$app_path" ]]; then
                    appname=$(basename "$app_path")
                    if [[ ! -e "/Applications/$appname" ]]; then
                        # Registered in brew but .app is missing — treat as broken
                        new_lines+=("$line")
                        new_labels+=("$label [broken]")
                        continue
                    fi
                fi
            fi
            installed_count=$((installed_count + 1))
        else
            new_lines+=("$line")
            new_labels+=("$label")
        fi
    done < "$filepath"

    if [[ $installed_count -gt 0 ]]; then
        log_ok "$installed_count already installed"
    fi

    if [[ ${#new_labels[@]} -eq 0 ]]; then
        log_ok "Everything from backup is already installed"
        wait_enter
        return
    fi

    local selected
    selected=$(show_multiselect "Import" "${new_labels[@]}")

    if [[ -z "$selected" ]]; then
        log_info "Nothing selected"
        return
    fi

    local tmp
    tmp=$(mktemp /tmp/macrift_import_XXXXXX)

    for ((i=0; i<${#new_labels[@]}; i++)); do
        if echo "$selected" | grep -qxF "${new_labels[$i]}"; then
            echo "${new_lines[$i]}" >> "$tmp"
        fi
    done

    log_info "Installing selected packages..."
    if brew bundle --file="$tmp"; then
        log_ok "Import complete"
    else
        log_warn "Some packages failed to install"
    fi
    rm -f "$tmp"
    wait_enter
}

export_brewbak() {
    clear

    local default_path
    default_path="$HOME/Desktop/macrift-$(date +%Y%m%d).brewbak"
    printf '  %bSave path (enter for default):%b\n' "$DIM" "$RESET"
    printf '  %b%s%b\n' "$DIM" "$default_path" "$RESET"
    prompt_path
    read -r filepath

    if [[ -z "$filepath" ]]; then
        filepath="$default_path"
    fi
    filepath="${filepath//\'/}"
    filepath="${filepath//\"/}"
    filepath="${filepath%% }"

    log_info "Exporting..."
    if brew bundle dump --file="$filepath" --force; then
        log_ok "Exported to $filepath"
    else
        log_err "Export failed"
    fi
    wait_enter
}
