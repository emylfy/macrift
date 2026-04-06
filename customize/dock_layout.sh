#!/usr/bin/env bash
# macrift — Dock layout management via dockutil

dock_layout_menu() {
    crumb_push "Dock Layout"
    while true; do
        clear

        local choice
        choice=$(show_menu "Dock Layout" \
            "Clear Dock" \
            "Add spacer" \
            "Reset to default" \
            "Back")

        case "$choice" in
            1) clear_dock ;;
            2) add_dock_spacer ;;
            3) reset_dock ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
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
