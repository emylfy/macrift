#!/usr/bin/env bash
# wallpaper-links — minimal macrift plugin example.
#
# Demonstrates the smallest workable plugin: a single function that uses
# macrift's show_menu helper and `open` to launch URLs. No audit_default,
# no journaled state mutation — opening URLs is reversible by closing the
# tab, so the plugin doesn't need macrift's heavier machinery.
#
# Use this as a template for any "links / bookmarks / shortcuts" plugin:
# replace the URLs, retitle the entries, ship it.

wallpaper_links_menu() {
    crumb_push "Wallpaper links"
    while true; do
        clear
        local choice
        choice=$(show_menu "Wallpaper links" \
            "Wallhaven" \
            "Catppuccin wallpapers" \
            "Gruvbox wallpapers" \
            "Curated collection (Raindrop)" \
            "Back")

        case "$choice" in
            1) open "https://wallhaven.cc"                                      || log_warn "Could not open browser"; log_ok "Opened in browser" ;;
            2) open "https://github.com/zhichaoh/catppuccin-wallpapers"         || log_warn "Could not open browser"; log_ok "Opened in browser" ;;
            3) open "https://github.com/AngelJumworworbo/gruvbox-wallpapers"    || log_warn "Could not open browser"; log_ok "Opened in browser" ;;
            4) open "https://raindrop.io/emalfai/wallpaper-69077386"            || log_warn "Could not open browser"; log_ok "Opened in browser" ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}
