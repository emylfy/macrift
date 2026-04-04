#!/usr/bin/env bash
# macrift — customize menu

customize_menu() {
    crumb_push "Customize"
    while true; do
        clear
        set_title "macrift > customize"
        local choice
        choice=$(show_menu "Customize" \
            "Profile" \
            "---" \
            "Terminal Emulator" \
            "Shell" \
            "FastFetch" \
            "Code Editor" \
            "Dock Layout" \
            "---" \
            "Wallpaper" \
            "Back")

        case "$choice" in
            1) source "$MACRIFT_DIR/customize/profile.sh" && profile_menu ;;
            2) source "$MACRIFT_DIR/customize/terminal.sh" && terminal_menu ;;
            3) source "$MACRIFT_DIR/customize/terminal.sh" && shell_menu ;;
            4) source "$MACRIFT_DIR/customize/terminal.sh" && fastfetch_menu ;;
            5) source "$MACRIFT_DIR/customize/editor.sh" && editor_menu ;;
            6) source "$MACRIFT_DIR/customize/dock_layout.sh" && dock_layout_menu ;;
            7) source "$MACRIFT_DIR/customize/wallpaper.sh" && wallpaper_menu ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}
