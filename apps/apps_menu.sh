#!/usr/bin/env bash
# macrift — apps menu

apps_menu() {
    while true; do
        clear
        set_title "macrift > apps"
        local choice
        choice=$(show_menu "Apps & Packages" \
            "Homebrew Bundles" \
            "Mac App Store" \
            "Dock Layout" \
            "Spotify" \
            "Back")

        case "$choice" in
            1) source "$MACRIFT_DIR/apps/brew.sh" && brew_menu ;;
            2) source "$MACRIFT_DIR/apps/appstore.sh" && appstore_menu ;;
            3) source "$MACRIFT_DIR/apps/dock_layout.sh" && dock_layout_menu ;;
            4) source "$MACRIFT_DIR/apps/spotify.sh" && spotify_menu ;;
            0) return ;;
            *) ;;
        esac
    done
}
