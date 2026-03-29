#!/usr/bin/env bash
# macrift — wallpaper links

wallpaper_menu() {
    while true; do
        clear
        set_title "macrift > wallpaper"
        local choice
        choice=$(show_menu "Wallpaper" \
            "Catppuccin wallpapers (GitHub)" \
            "Gruvbox wallpapers (GitHub)" \
            "wallhaven.cc (browse wallpapers)" \
            "Curated collection (Raindrop)" \
            "Back")

        case "$choice" in
            1) open "https://github.com/zhichaoh/catppuccin-wallpapers" ;;
            2) open "https://github.com/AngelJumworworbo/gruvbox-wallpapers" ;;
            3) open "https://wallhaven.cc" ;;
            4) open "https://raindrop.io/emalfai/wallpaper-69077386" ;;
            0) return ;;
            *) ;;
        esac
    done
}
