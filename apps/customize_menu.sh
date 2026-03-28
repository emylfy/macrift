#!/usr/bin/env bash
# macrift — customize menu

customize_menu() {
    while true; do
        clear
        set_title "macrift > customize"
        local choice
        choice=$(show_menu "Customize" \
            "Terminal (iTerm2 / Ghostty)" \
            "Code Editor" \
            "Spicetify (restore marketplace)" \
            "Wallpaper" \
            "Back")

        case "$choice" in
            1) source "$MACRIFT_DIR/apps/terminal.sh" && terminal_menu ;;
            2) source "$MACRIFT_DIR/apps/editor.sh" && editor_menu ;;
            3) source "$MACRIFT_DIR/apps/spicetify.sh" && restore_marketplace ;;
            4) source "$MACRIFT_DIR/apps/wallpaper.sh" && wallpaper_menu ;;
            0) return ;;
            *) ;;
        esac
    done
}
