#!/usr/bin/env bash
# macrift — Dock layout management via dockutil

dock_layout_menu() {
    while true; do
        clear
        set_title "macrift > dock layout"
        local choice
        choice=$(show_menu "Dock Layout" \
            "Apply dock layout" \
            "Clear Dock" \
            "Add spacer" \
            "Reset Dock to macOS default" \
            "Back")

        case "$choice" in
            1) apply_dock_layout ;;
            2) clear_dock ;;
            3) add_dock_spacer ;;
            4) reset_dock ;;
            0) return ;;
            *) ;;
        esac
    done
}

apply_dock_layout() {
    clear

    local config_file="$MACRIFT_DIR/config/dock.txt"

    if [[ ! -f "$config_file" ]]; then
        log_err "No dock layout found"
        log_info "Add app names to config/dock.txt (one per line)"
        log_info "Example:"
        echo ""
        printf '  %bSafari%b\n' "$DIM" "$RESET"
        printf '  %bVisual Studio Code%b\n' "$DIM" "$RESET"
        printf '  %biTerm%b\n' "$DIM" "$RESET"
        printf '  %bDiscord%b\n' "$DIM" "$RESET"
        printf '  %bSpotify%b\n' "$DIM" "$RESET"
        echo ""
        wait_enter
        return
    fi

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

    # Parse config, skip comments and empty lines
    local apps=()
    while IFS= read -r line; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue
        apps+=("$line")
    done < "$config_file"

    if [[ ${#apps[@]} -eq 0 ]]; then
        log_err "config/dock.txt is empty"
        wait_enter
        return
    fi

    # Show what will be applied
    log_info "Dock layout from config/dock.txt:"
    echo ""
    for app in "${apps[@]}"; do
        printf '  %b·%b %s\n' "$CYAN" "$RESET" "$app"
    done
    echo ""

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would replace Dock with above apps"
        wait_enter
        return
    fi

    if ! confirm "Apply this layout?"; then return; fi

    # Remove all current items
    dockutil --remove all --no-restart 2>/dev/null

    # Add each app
    local found=0 missing=0
    for app in "${apps[@]}"; do
        local app_path
        app_path=$(find /Applications /System/Applications -maxdepth 2 -name "${app}.app" 2>/dev/null | head -1)
        if [[ -n "$app_path" ]]; then
            dockutil --add "$app_path" --no-restart 2>/dev/null
            log_ok "$app"
            found=$((found + 1))
        else
            log_warn "$app — not found in Applications"
            missing=$((missing + 1))
        fi
    done

    killall Dock 2>/dev/null || true
    echo ""
    log_info "$found added, $missing not found"

    wait_enter
}

clear_dock() {
    clear
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would remove all apps from Dock"
    elif confirm "Remove all apps from Dock?"; then
        dockutil --remove all 2>/dev/null || \
            defaults write com.apple.dock persistent-apps -array
        killall Dock 2>/dev/null || true
        log_ok "Dock cleared"
    fi

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
