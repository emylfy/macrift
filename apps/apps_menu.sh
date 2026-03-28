#!/usr/bin/env bash
# macrift — apps menu

apps_menu() {
    while true; do
        clear
        set_title "macrift > apps"
        local choice
        choice=$(show_menu "Apps & Packages" \
            "Homebrew Bundles" \
            "Spotify" \
            "Back")

        case "$choice" in
            1) source "$MACRIFT_DIR/apps/brew.sh" && brew_menu ;;
            2) source "$MACRIFT_DIR/apps/spotify.sh" && spotify_menu ;;
            0) return ;;
            *) ;;
        esac
    done
}
