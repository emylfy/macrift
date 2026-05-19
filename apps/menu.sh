#!/usr/bin/env bash
# macrift — apps menu

install_xcode_clt() {
    clear
    if xcode-select -p &>/dev/null; then
        log_ok "Xcode Command Line Tools already installed"
        printf '  %b%s%b\n' "$DIM" "$(xcode-select -p)" "$RESET"
        wait_enter
        return
    fi

    log_info "Xcode CLT provides: git, clang, make, developer headers"
    printf '\n'

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would run: xcode-select --install"
        wait_enter
        return
    fi

    if ! confirm "Install Xcode Command Line Tools?"; then return; fi

    xcode-select --install 2>/dev/null || true
    printf '  %bWaiting for installation...%b' "$DIM" "$RESET"
    until xcode-select -p &>/dev/null; do
        printf '.'
        sleep 5
    done
    printf '\n'
    log_ok "Xcode Command Line Tools installed"
    wait_enter
}

apps_menu() {
    crumb_push "Apps & Packages"
    while true; do
        clear

        local -a items=(
            "Homebrew Bundles"
            "Mac App Store"
            "Spotify (SpotX + Spicetify)"
        )
        # Only offer CLT install if it isn't already present
        if ! xcode-select -p &>/dev/null; then
            items+=("---" "Xcode Command Line Tools")
        fi
        items+=("Back")

        local choice
        choice=$(show_menu "Apps & Packages" "${items[@]}")

        case "$choice" in
            1) source "$MACRIFT_DIR/apps/brew.sh" && brew_menu ;;
            2) source "$MACRIFT_DIR/apps/appstore.sh" && appstore_menu ;;
            3) source "$MACRIFT_DIR/apps/spotify.sh" && spotify_menu ;;
            4) install_xcode_clt ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}
