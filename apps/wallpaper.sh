#!/usr/bin/env bash
# macrift — wallpaper links

wallpaper_menu() {
    while true; do
        clear
        set_title "macrift > wallpaper"
        local choice
        choice=$(show_menu "Wallpaper" \
            "Personal collection (Raindrop)" \
            "Catppuccin wallpapers (GitHub)" \
            "Gruvbox wallpapers (GitHub)" \
            "wallhaven.cc (browse wallpapers)" \
            "Back")

        case "$choice" in
            1) open "https://raindrop.io/emalfai/wallpaper-69077386" ;;
            2) open "https://github.com/zhichaoh/catppuccin-wallpapers" ;;
            3) open "https://github.com/AngelJumworworbo/gruvbox-wallpapers" ;;
            4) open "https://wallhaven.cc" ;;
            0) return ;;
            *) ;;
        esac
    done
}
