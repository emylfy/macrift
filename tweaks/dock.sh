#!/usr/bin/env bash
# macrift — Dock tweaks

dock_tweaks() {
    audit_reset

    audit_default "com.apple.dock" "autohide" "-bool" "true" "Autohide Dock"
    audit_default "com.apple.dock" "autohide-delay" "-float" "0" "Autohide delay"
    audit_default "com.apple.dock" "autohide-time-modifier" "-float" "0.3" "Autohide animation speed"
    audit_default "com.apple.dock" "tilesize" "-int" "36" "Icon size"
    audit_default "com.apple.dock" "minimize-to-application" "-bool" "true" "Minimize to app icon"
    audit_default "com.apple.dock" "mineffect" "-string" "scale" "Minimize effect"
    audit_default "com.apple.dock" "show-recents" "-bool" "false" "Show recent apps"
    audit_default "com.apple.dock" "showhidden" "-bool" "true" "Show hidden apps dimmed"
    audit_default "com.apple.dock" "mru-spaces" "-bool" "false" "Auto-rearrange Spaces"
    audit_default "com.apple.dock" "static-only" "-bool" "false" "Show only running apps"

    if show_audit_table "Dock"; then
        apply_audited_defaults
        killall Dock 2>/dev/null || true
        log_ok "Dock restarted"
    fi
}

hot_corners_tweaks() {
    clear
    divider "Hot Corners"

    show_info_box "Corner Actions" \
        "0  — No action" \
        "2  — Mission Control" \
        "3  — Application Windows" \
        "4  — Desktop" \
        "5  — Start Screen Saver" \
        "6  — Disable Screen Saver" \
        "10 — Put Display to Sleep" \
        "11 — Launchpad" \
        "12 — Notification Center" \
        "13 — Lock Screen" \
        "14 — Quick Note"

    local tl tr bl br
    local cur_tl cur_tr cur_bl cur_br
    cur_tl=$(defaults read com.apple.dock wvous-tl-corner 2>/dev/null || echo "not set")
    cur_tr=$(defaults read com.apple.dock wvous-tr-corner 2>/dev/null || echo "not set")
    cur_bl=$(defaults read com.apple.dock wvous-bl-corner 2>/dev/null || echo "not set")
    cur_br=$(defaults read com.apple.dock wvous-br-corner 2>/dev/null || echo "not set")

    printf "\n  ${DIM}Current: TL=%s  TR=%s  BL=%s  BR=%s${RESET}\n\n" "$cur_tl" "$cur_tr" "$cur_bl" "$cur_br"

    printf "  ${CYAN}Top-left${RESET} [%s]: " "$cur_tl"
    read -r tl < /dev/tty
    printf "  ${CYAN}Top-right${RESET} [%s]: " "$cur_tr"
    read -r tr < /dev/tty
    printf "  ${CYAN}Bottom-left${RESET} [%s]: " "$cur_bl"
    read -r bl < /dev/tty
    printf "  ${CYAN}Bottom-right${RESET} [%s]: " "$cur_br"
    read -r br < /dev/tty

    # Use current values if empty
    tl="${tl:-$cur_tl}"
    tr="${tr:-$cur_tr}"
    bl="${bl:-$cur_bl}"
    br="${br:-$cur_br}"

    printf "\n"
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would set TL=$tl TR=$tr BL=$bl BR=$br"
    elif confirm "Apply corners: TL=$tl TR=$tr BL=$bl BR=$br?"; then
        defaults write com.apple.dock wvous-tl-corner -int "$tl"
        defaults write com.apple.dock wvous-tl-modifier -int 0
        defaults write com.apple.dock wvous-tr-corner -int "$tr"
        defaults write com.apple.dock wvous-tr-modifier -int 0
        defaults write com.apple.dock wvous-bl-corner -int "$bl"
        defaults write com.apple.dock wvous-bl-modifier -int 0
        defaults write com.apple.dock wvous-br-corner -int "$br"
        defaults write com.apple.dock wvous-br-modifier -int 0
        killall Dock 2>/dev/null || true
        log_ok "Hot corners applied"
    fi

    printf "\n  ${DIM}press enter to continue${RESET} "
    read -r < /dev/tty || true
}
