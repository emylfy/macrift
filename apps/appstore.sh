#!/usr/bin/env bash
# macrift — Mac App Store installer via mas

appstore_menu() {
    if ! check_homebrew; then wait_enter; return; fi
    crumb_push "App Store"
    while true; do
        clear

        local choice
        choice=$(show_menu "App Store" \
            "Install from list" \
            "Show installed" \
            "Back")

        case "$choice" in
            1) install_appstore ;;
            2) show_installed_apps ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

install_appstore() {
    clear

    _ensure_mas || return 0

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
    local new_optional=()
    local installed_count=0

    while IFS= read -r line; do
        _brewfile_parse_line "$line" || continue
        [[ "$BF_KIND" == "mas" ]] || continue
        if echo "$installed_ids" | grep -qxF "$BF_ID"; then
            installed_count=$((installed_count + 1))
        else
            new_labels+=("$BF_NAME")
            new_ids+=("$BF_ID")
            new_optional+=("$BF_OPTIONAL")
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

    MULTISELECT_OPTIONAL=""
    for ((i=0; i<${#new_optional[@]}; i++)); do
        [[ "${new_optional[$i]}" == "1" ]] && MULTISELECT_OPTIONAL+="$i "
    done
    local selected
    selected=$(show_multiselect "App Store" "${new_labels[@]}")

    if [[ -z "$selected" ]]; then
        return 0
    fi

    log_hint "if downloads hang, try disabling VPN"
    printf "\n"
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install from App Store:"
        for ((i=0; i<${#new_labels[@]}; i++)); do
            if echo "$selected" | grep -qxF "${new_labels[$i]}"; then
                printf '  %b· %s (id: %s)%b\n' "$DIM" "${new_labels[$i]}" "${new_ids[$i]}" "$RESET"
            fi
        done
    else
        local as_idx=0
        local as_total
        as_total=$(echo "$selected" | wc -l | tr -d ' ')
        for ((i=0; i<${#new_labels[@]}; i++)); do
            if echo "$selected" | grep -qxF "${new_labels[$i]}"; then
                as_idx=$((as_idx + 1))
                show_progress "$as_idx" "$as_total" "${new_labels[$i]}"
                local mas_out
                if mas_out=$(mas install "${new_ids[$i]}" 2>&1); then
                    _journal_append_brew "${new_labels[$i]}" "mas" "${new_ids[$i]}" "absent"
                    log_ok "${new_labels[$i]} installed"
                else
                    log_warn "Failed: ${new_labels[$i]}"
                    [[ -n "$mas_out" ]] && log_hint "$(printf '%s\n' "$mas_out" | tail -1)"
                    if confirm "Open App Store page?"; then
                        open "macappstore://apps.apple.com/app/id${new_ids[$i]}"
                    fi
                fi
            fi
        done
    fi

    wait_enter
}

show_installed_apps() {
    clear

    _ensure_mas || return 0

    mas list 2>/dev/null | while IFS= read -r line; do
        printf '  %b%s%b\n' "$DIM" "$line" "$RESET"
    done

    wait_enter
}
