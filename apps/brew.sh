#!/usr/bin/env bash
# macrift — Homebrew bundle installer

# Speed up brew: skip auto-update, analytics, cleanup, dependents check
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1

brew_menu() {
    crumb_push "Homebrew"
    while true; do
        clear
        set_title "macrift > brew"
        local choice
        choice=$(show_menu "Homebrew" \
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
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

brewbak_menu() {
    crumb_push "Backup"
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
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
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
    local had_items=false
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*#.*$ ]] && continue
        if [[ -z "${line// /}" ]]; then
            if $had_items; then
                new_lines+=("")
                new_labels+=("---")
            fi
            continue
        fi
        had_items=true
        local name="" label=""
        if [[ "$line" =~ ^brew[[:space:]]+\"([^\"]+)\" ]]; then
            name="${BASH_REMATCH[1]}"
            label="$name"
        elif [[ "$line" =~ ^cask[[:space:]]+\"([^\"]+)\" ]]; then
            name="${BASH_REMATCH[1]}"
            label="$name"
        elif [[ "$line" =~ ^mas[[:space:]]+\"([^\"]+)\",[[:space:]]*id:[[:space:]]*([0-9]+) ]]; then
            name="${BASH_REMATCH[1]}"
            local mas_id="${BASH_REMATCH[2]}"
            label="$name"
            if mas list 2>/dev/null | awk '{print $1}' | grep -qx "$mas_id"; then
                installed_count=$((installed_count + 1))
            else
                new_lines+=("$line")
                new_labels+=("$label")
            fi
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

    # Clean up separators: remove leading, trailing, and consecutive
    local clean_lines=() clean_labels=()
    local prev_sep=true
    for ((i=0; i<${#new_labels[@]}; i++)); do
        if [[ "${new_labels[$i]}" == "---" ]]; then
            $prev_sep && continue
            prev_sep=true
        else
            prev_sep=false
        fi
        clean_lines+=("${new_lines[$i]}")
        clean_labels+=("${new_labels[$i]}")
    done
    # Remove trailing separator
    while [[ ${#clean_labels[@]} -gt 0 && "${clean_labels[-1]}" == "---" ]]; do
        unset 'clean_lines[-1]'
        unset 'clean_labels[-1]'
    done
    new_lines=("${clean_lines[@]}")
    new_labels=("${clean_labels[@]}")

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
            local cask_idx=0
            for cask in "${broken_casks[@]}"; do
                ((cask_idx++))
                show_progress "$cask_idx" "${#broken_casks[@]}" "$cask"
                if brew reinstall --cask "$cask" &>/dev/null; then
                    log_ok "$cask reinstalled"
                else
                    log_warn "Failed to reinstall $cask"
                fi
            done
            wait_enter
        fi
        printf "\n"
    fi

    # Check if there are any real (non-separator) items
    local has_real=false
    for lbl in "${new_labels[@]}"; do
        [[ "$lbl" != "---" ]] && { has_real=true; break; }
    done
    if ! $has_real; then
        log_ok "Everything installed"
        wait_enter
        return 0
    fi

    # Multiselect for new packages only
    local selected
    selected=$(show_multiselect "$brewfile" "${new_labels[@]}")

    if [[ -z "$selected" ]]; then
        return 0
    fi

    # Build temp Brewfile with selected packages
    local tmp
    tmp=$(mktemp /tmp/macrift_brew_XXXXXX)

    local mas_install_lines=()
    for ((i=0; i<${#new_labels[@]}; i++)); do
        [[ "${new_labels[$i]}" == "---" ]] && continue
        if echo "$selected" | grep -qxF "${new_labels[$i]}"; then
            if [[ "${new_lines[$i]}" =~ ^mas[[:space:]] ]]; then
                mas_install_lines+=("${new_lines[$i]}")
            else
                echo "${new_lines[$i]}" >> "$tmp"
            fi
        fi
    done

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install:"
        [[ -s "$tmp" ]] && while IFS= read -r line; do
            printf '  %b· %s%b\n' "$DIM" "$line" "$RESET"
        done < "$tmp"
        for mas_line in "${mas_install_lines[@]}"; do
            if [[ "$mas_line" =~ ^mas[[:space:]]+\"([^\"]+)\" ]]; then
                printf '  %b· %s (App Store)%b\n' "$DIM" "${BASH_REMATCH[1]}" "$RESET"
            fi
        done
        rm -f "$tmp"
        wait_enter
        return 0
    fi

    local all_ok=true

    if [[ -s "$tmp" ]]; then
        log_info "Installing selected packages..."
        brew bundle --quiet --no-upgrade --file="$tmp" || all_ok=false
    fi
    rm -f "$tmp"

    local mas_idx=0 mas_total=${#mas_install_lines[@]}
    for mas_line in "${mas_install_lines[@]}"; do
        ((mas_idx++))
        if [[ "$mas_line" =~ ^mas[[:space:]]+\"([^\"]+)\",[[:space:]]*id:[[:space:]]*([0-9]+) ]]; then
            local mas_name="${BASH_REMATCH[1]}"
            local mas_id="${BASH_REMATCH[2]}"
            [[ $mas_total -gt 1 ]] && show_progress "$mas_idx" "$mas_total" "$mas_name"
            local mas_out
            if mas_out=$(mas install "$mas_id" 2>&1); then
                log_ok "$mas_name installed"
            elif echo "$mas_out" | grep -qi "Redownload Unavailable"; then
                log_warn "$mas_name: not purchased with this account — opening App Store"
                open "https://apps.apple.com/app/id$mas_id"
                all_ok=false
            else
                log_warn "Failed to install $mas_name"
                all_ok=false
            fi
        fi
    done

    if $all_ok; then
        log_ok "All packages installed"
    else
        log_warn "Some packages failed to install"
    fi
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
    wait_enter
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
            label="$name"
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
    if brew bundle --quiet --no-upgrade --file="$tmp"; then
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
