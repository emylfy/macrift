#!/usr/bin/env bash
# macrift — customize menu

customize_menu() {
    crumb_push "Customize"

    # Apple removed Launchpad.app in macOS 26 (Tahoe) — hide the menu item there
    local is_tahoe=false
    [[ "$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)" -ge 26 ]] && is_tahoe=true

    while true; do
        clear

        local -a items=(
            "## Backup"
            "Profile ›"
            "---"
            "## Terminal"
            "Terminal Emulator ›"
            "Shell ›"
            "FastFetch"
            "---"
            "## Editors"
            "Code Editor ›"
            "Claude Code ›"
            "---"
            "## Desktop"
            "Dock Layout ›"
        )
        $is_tahoe || items+=("Launchpad ›")
        items+=(
            "Wallpaper ›"
            "Back"
        )

        local choice
        choice=$(show_menu "Customize" "${items[@]}")

        case "$choice" in
            1) source "$MACRIFT_DIR/customize/profile.sh" && profile_menu ;;
            2) source "$MACRIFT_DIR/customize/terminal.sh" && terminal_menu ;;
            3) source "$MACRIFT_DIR/customize/terminal.sh" && shell_menu ;;
            4) source "$MACRIFT_DIR/customize/terminal.sh" && setup_fastfetch ;;
            5) source "$MACRIFT_DIR/customize/editor.sh" && editor_menu ;;
            6) source "$MACRIFT_DIR/customize/claude_code.sh" && claude_code_menu ;;
            7) source "$MACRIFT_DIR/customize/dock_layout.sh" && dock_layout_menu ;;
            8)
                # On Tahoe, Launchpad is hidden so position 8 = Wallpaper
                if $is_tahoe; then
                    source "$MACRIFT_DIR/customize/wallpaper.sh" && wallpaper_menu
                else
                    source "$MACRIFT_DIR/customize/launchpad.sh" && launchpad_menu
                fi
                ;;
            9) source "$MACRIFT_DIR/customize/wallpaper.sh" && wallpaper_menu ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}
