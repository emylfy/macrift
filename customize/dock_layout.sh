#!/usr/bin/env bash
# macrift — Dock layout management via dockutil

DOCK_LAYOUT_DIR="$HOME/.macrift"

dock_layout_menu() {
    crumb_push "Dock Layout"
    while true; do
        clear

        local choice
        choice=$(show_menu "Dock Layout" \
            "Save layout" \
            "Restore layout" \
            "---" \
            "Clear Dock" \
            "Add spacer" \
            "Reset to default" \
            "Back")

        case "$choice" in
            1) save_dock_layout ;;
            2) restore_dock_layout ;;
            3) clear_dock ;;
            4) add_dock_spacer ;;
            5) reset_dock ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

save_dock_layout() {
    clear
    local layout_file="$DOCK_LAYOUT_DIR/dock-layout.txt"

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would save dock layout to $layout_file"
        wait_enter
        return
    fi

    mkdir -p "$DOCK_LAYOUT_DIR"

    if command -v dockutil &>/dev/null; then
        dockutil --list > "$layout_file" 2>/dev/null
    else
        # Fallback: extract app paths from defaults
        defaults read com.apple.dock persistent-apps 2>/dev/null \
            | grep '"file-label"' \
            | sed 's/.*= "\(.*\)";/\1/' > "$layout_file"
    fi

    local count
    count=$(wc -l < "$layout_file" | tr -d ' ')
    log_ok "Saved $count items → $layout_file"
    wait_enter
}

restore_dock_layout() {
    clear
    local layout_file="$DOCK_LAYOUT_DIR/dock-layout.txt"

    if [[ ! -f "$layout_file" ]]; then
        log_err "No saved layout found"
        log_info "Save your current layout first"
        wait_enter
        return
    fi

    local count
    count=$(wc -l < "$layout_file" | tr -d ' ')
    log_info "Saved layout: $count items"

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would restore dock layout"
        wait_enter
        return
    fi

    if ! confirm "Restore saved dock layout?"; then return; fi

    if command -v dockutil &>/dev/null; then
        # Clear current dock
        dockutil --remove all --no-restart 2>/dev/null || \
            defaults write com.apple.dock persistent-apps -array

        # Restore each app from saved layout
        local added=0 failed=0
        while IFS=$'\t' read -r label _ path; do
            # dockutil --list format: "Label\ttype\tpath"
            [[ -z "$path" ]] && continue
            # Strip file:// prefix if present
            path="${path#file://}"
            if [[ -e "$path" ]]; then
                dockutil --add "$path" --no-restart 2>/dev/null && added=$((added + 1)) || failed=$((failed + 1))
            else
                failed=$((failed + 1))
            fi
        done < "$layout_file"

        killall Dock 2>/dev/null || true
        log_ok "$added apps restored"
        [[ $failed -gt 0 ]] && log_warn "$failed apps not found (uninstalled?)"
    else
        log_err "dockutil required for restore"
        if confirm "Install dockutil via Homebrew?"; then
            brew_install "dockutil"
        fi
    fi
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
