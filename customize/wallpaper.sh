#!/usr/bin/env bash
# macrift — wallpaper links

wallpaper_menu() {
    crumb_push "Wallpaper"
    while true; do
        clear
        set_title "macrift > wallpaper"
        local choice
        choice=$(show_menu "Wallpaper" \
            "Wallhaven" \
            "Catppuccin" \
            "Gruvbox" \
            "Curated Collection" \
            "Back")

        case "$choice" in
            1) open "https://wallhaven.cc"; log_ok "Opened in browser" ;;
            2) open "https://github.com/zhichaoh/catppuccin-wallpapers"; log_ok "Opened in browser" ;;
            3) open "https://github.com/AngelJumworworbo/gruvbox-wallpapers"; log_ok "Opened in browser" ;;
            4) open "https://raindrop.io/emalfai/wallpaper-69077386"; log_ok "Opened in browser" ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}
