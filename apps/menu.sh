#!/usr/bin/env bash
# macrift — apps menu

apps_menu() {
    crumb_push "Apps & Packages"
    while true; do
        clear

        local choice
        choice=$(show_menu "Apps & Packages" \
            "Homebrew Bundles" \
            "Mac App Store" \
            "Spotify (SpotX + Spicetify)" \
            "Back")

        case "$choice" in
            1) source "$MACRIFT_DIR/apps/brew.sh" && brew_menu ;;
            2) source "$MACRIFT_DIR/apps/appstore.sh" && appstore_menu ;;
            3) source "$MACRIFT_DIR/apps/spotify.sh" && spotify_menu ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}
