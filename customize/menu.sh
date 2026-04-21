#!/usr/bin/env bash
# macrift — customize menu

customize_menu() {
    crumb_push "Customize"
    while true; do
        clear

        local choice
        choice=$(show_menu "Customize" \
            "Profile" \
            "---" \
            "Terminal Emulator" \
            "Shell" \
            "FastFetch" \
            "Code Editor" \
            "Claude Code" \
            "Dock Layout" \
            "Launchpad" \
            "---" \
            "Wallpaper" \
            "Back")

        case "$choice" in
            1) source "$MACRIFT_DIR/customize/profile.sh" && profile_menu ;;
            2) source "$MACRIFT_DIR/customize/terminal.sh" && terminal_menu ;;
            3) source "$MACRIFT_DIR/customize/terminal.sh" && shell_menu ;;
            4) source "$MACRIFT_DIR/customize/terminal.sh" && setup_fastfetch ;;
            5) source "$MACRIFT_DIR/customize/editor.sh" && editor_menu ;;
            6) source "$MACRIFT_DIR/customize/claude_code.sh" && claude_code_menu ;;
            7) source "$MACRIFT_DIR/customize/dock_layout.sh" && dock_layout_menu ;;
            8) source "$MACRIFT_DIR/customize/launchpad.sh" && launchpad_menu ;;
            9) source "$MACRIFT_DIR/customize/wallpaper.sh" && wallpaper_menu ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}
