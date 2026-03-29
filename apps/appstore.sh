#!/usr/bin/env bash
# macrift — Mac App Store installer via mas

appstore_menu() {
    while true; do
        clear
        set_title "macrift > app store"
        local choice
        choice=$(show_menu "Mac App Store" \
            "Install from list" \
            "Show installed" \
            "Back")

        case "$choice" in
            1) install_appstore ;;
            2) show_installed_apps ;;
            0) return ;;
            *) ;;
        esac
    done
}

_ensure_mas() {
    if command -v mas &>/dev/null; then
        return 0
    fi
    log_warn "mas (Mac App Store CLI) not found"
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install mas"
        return 1
    fi
    if confirm "Install mas via Homebrew?"; then
        brew install mas
        return 0
    fi
    return 1
}

install_appstore() {
    clear

    _ensure_mas || return

    local path="$MACRIFT_DIR/config/Brewfile.appstore"
    if [[ ! -f "$path" ]]; then
        log_err "Brewfile.appstore not found"
        return 1
    fi

    # Get installed app ids
    local installed_ids
    installed_ids=$(mas list 2>/dev/null | awk '{print $1}')

    # Parse mas entries
    local new_labels=()
    local new_ids=()
    local installed_count=0

    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*#.*$ || -z "${line// /}" ]] && continue
        if [[ "$line" =~ ^mas[[:space:]]+\"([^\"]+)\".*id:[[:space:]]*([0-9]+) ]]; then
            local name="${BASH_REMATCH[1]}"
            local id="${BASH_REMATCH[2]}"
            if echo "$installed_ids" | grep -qxF "$id"; then
                installed_count=$((installed_count + 1))
            else
                new_labels+=("$name")
                new_ids+=("$id")
            fi
        fi
    done < "$path"

    if [[ $installed_count -gt 0 ]]; then
        log_ok "$installed_count already installed"
    fi

    if [[ ${#new_labels[@]} -eq 0 ]]; then
        log_ok "Everything installed"
        wait_enter
        return 0
    fi

    local selected
    selected=$(show_multiselect "App Store" "${new_labels[@]}")

    if [[ -z "$selected" ]]; then
        log_info "Nothing selected"
        return 0
    fi

    log_warn "VPN must be disabled for App Store downloads to work"
    printf "\n"
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install from App Store:"
        for ((i=0; i<${#new_labels[@]}; i++)); do
            if echo "$selected" | grep -qxF "${new_labels[$i]}"; then
                printf '  %b· %s (id: %s)%b\n' "$DIM" "${new_labels[$i]}" "${new_ids[$i]}" "$RESET"
            fi
        done
    else
        for ((i=0; i<${#new_labels[@]}; i++)); do
            if echo "$selected" | grep -qxF "${new_labels[$i]}"; then
                log_info "Installing ${new_labels[$i]}..."
                if mas install "${new_ids[$i]}"; then
                    log_ok "${new_labels[$i]} installed"
                else
                    log_warn "Failed: ${new_labels[$i]}"
                fi
            fi
        done
    fi

    wait_enter
}

show_installed_apps() {
    clear

    _ensure_mas || return

    mas list 2>/dev/null | while IFS= read -r line; do
        printf '  %b%s%b\n' "$DIM" "$line" "$RESET"
    done

    wait_enter
}
