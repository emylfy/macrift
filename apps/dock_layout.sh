#!/usr/bin/env bash
# macrift — Dock layout management via dockutil

dock_layout_menu() {
    while true; do
        clear
        set_title "macrift > dock layout"
        local choice
        choice=$(show_menu "Dock Layout" \
            "Set up Dock apps" \
            "Add spacer to Dock" \
            "Reset Dock to default" \
            "Back")

        case "$choice" in
            1) setup_dock_apps ;;
            2) add_dock_spacer ;;
            3) reset_dock ;;
            0) return ;;
            *) ;;
        esac
    done
}

setup_dock_apps() {
    clear

    # Ensure dockutil is installed
    if ! command -v dockutil &>/dev/null; then
        log_warn "dockutil not found"
        if [[ "$MACRIFT_DRY_RUN" == true ]]; then
            log_info "Dry run — would install dockutil"
            return
        fi
        if confirm "Install dockutil via Homebrew?"; then
            brew install dockutil
        else
            return
        fi
    fi

    # Scan /Applications for .app bundles
    local apps=()
    while IFS= read -r app; do
        apps+=("$(basename "$app" .app)")
    done < <(find /Applications -maxdepth 2 -name "*.app" -not -path "*/Utilities/*" 2>/dev/null | sort)

    if [[ ${#apps[@]} -eq 0 ]]; then
        log_err "No applications found"
        return
    fi

    # Get currently docked apps
    local docked
    docked=$(dockutil --list 2>/dev/null | cut -f1)

    # Mark currently docked apps
    local labels=()
    local is_docked=()
    for app in "${apps[@]}"; do
        if echo "$docked" | grep -qxF "$app"; then
            labels+=("$app (in dock)")
            is_docked+=("1")
        else
            labels+=("$app")
            is_docked+=("0")
        fi
    done

    printf "\n"
    log_info "Select apps for your Dock (replaces current layout)"
    printf "\n"

    local selected
    selected=$(show_multiselect "Dock Apps" "${labels[@]}")

    if [[ -z "$selected" ]]; then
        log_info "Nothing selected"
        return
    fi

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would replace Dock with selected apps"
        wait_enter
        return
    fi

    if ! confirm "Replace Dock with selected apps?"; then
        return
    fi

    # Remove all current items
    dockutil --remove all --no-restart 2>/dev/null

    # Add selected apps
    for ((i=0; i<${#apps[@]}; i++)); do
        local label="${labels[$i]}"
        if echo "$selected" | grep -qxF "$label"; then
            local app_path
            app_path=$(find /Applications -maxdepth 2 -name "${apps[$i]}.app" 2>/dev/null | head -1)
            if [[ -n "$app_path" ]]; then
                dockutil --add "$app_path" --no-restart 2>/dev/null
            fi
        fi
    done

    killall Dock 2>/dev/null || true
    log_ok "Dock layout updated"

    wait_enter
}

add_dock_spacer() {
    clear
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would add spacer to Dock"
    else
        dockutil --add '' --type spacer --section apps 2>/dev/null || \
            defaults write com.apple.dock persistent-apps -array-add '{"tile-type"="spacer-tile";}'
        killall Dock 2>/dev/null || true
        log_ok "Spacer added to Dock"
    fi

    wait_enter
}

reset_dock() {
    clear
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would reset Dock to defaults"
    elif confirm "Reset Dock to macOS defaults?"; then
        defaults delete com.apple.dock 2>/dev/null || true
        killall Dock 2>/dev/null || true
        log_ok "Dock reset to defaults"
    fi

    wait_enter
}
