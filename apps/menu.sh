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

    if ! confirm "Install Xcode Command Line Tools?" "y"; then return; fi

    xcode-select --install 2>/dev/null || true
    printf '  %bWaiting for the Apple installer...%b' "$DIM" "$RESET"
    local waited=0
    until xcode-select -p &>/dev/null; do
        # If the user cancelled Apple's dialog this would spin forever — give up
        # after 10 minutes instead of hanging
        if [[ $waited -ge 600 ]]; then
            printf '\n'
            log_warn "Not installed after 10 minutes — stopped waiting"
            log_hint "finish the Apple installer, then re-run this item"
            wait_enter
            return
        fi
        printf '.'
        sleep 5
        waited=$((waited + 5))
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
            "Homebrew ›"
            "App Store ›"
        )
        # Spotify (SpotX + Spicetify) now ships as the bundled `misc` plugin and
        # injects itself here via menu.parent=apps (see _plugin_attach_builtin).
        # Only offer CLT install if it isn't already present
        if ! xcode-select -p &>/dev/null; then
            items+=("---" "Xcode Command Line Tools")
        fi

        # Plugins targeting menu.parent=apps append below the built-ins.
        local _nb; _nb=$(_menu_selectable_count items)
        local -a _pf=()
        _plugin_attach_builtin apps items _pf
        items+=("Back")

        local choice
        choice=$(show_menu "Apps & Packages" "${items[@]}")

        if (( choice > _nb )); then
            "${_pf[$((choice - _nb - 1))]}" || true
            continue
        fi
        case "$choice" in
            1) source "$MACRIFT_DIR/apps/brew.sh" && brew_menu ;;
            2) source "$MACRIFT_DIR/apps/appstore.sh" && appstore_menu ;;
            3) install_xcode_clt ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}
