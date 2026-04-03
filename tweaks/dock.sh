#!/usr/bin/env bash
# macrift — Dock tweaks

dock_tweaks() {
    [[ "$MACRIFT_BATCH_TWEAKS" != true ]] && audit_reset

    audit_default "com.apple.dock" "autohide" "-bool" "true" "Autohide"
    audit_default "com.apple.dock" "autohide-delay" "-float" "0" "Autohide delay"
    audit_default "com.apple.dock" "autohide-time-modifier" "-float" "0.3" "Animation speed"

    audit_sep

    audit_default "com.apple.dock" "tilesize" "-int" "36" "Icon size"
    audit_default "com.apple.dock" "minimize-to-application" "-bool" "true" "Minimize to app"
    audit_default "com.apple.dock" "mineffect" "-string" "scale" "Minimize effect"

    audit_sep

    audit_default "com.apple.dock" "show-recents" "-bool" "false" "Recent apps"
    audit_default "com.apple.dock" "showhidden" "-bool" "true" "Dim hidden apps"
    audit_default "com.apple.dock" "mru-spaces" "-bool" "false" "Rearrange Spaces"
    audit_default "com.apple.dock" "static-only" "-bool" "false" "Only running apps"

    [[ "$MACRIFT_BATCH_TWEAKS" == true ]] && return 0

    if show_audit_table "Dock"; then
        apply_audited_defaults
        if confirm "Restart Dock?"; then
            killall Dock 2>/dev/null || true
            log_ok "Dock restarted"
        fi
        wait_enter
    fi
}

_corner_name() {
    case "$1" in
        0)  echo "None" ;;
        2)  echo "Mission Control" ;;
        3)  echo "App Windows" ;;
        4)  echo "Desktop" ;;
        5)  echo "Screen Saver" ;;
        6)  echo "Disable Screen Saver" ;;
        10) echo "Display Sleep" ;;
        11) echo "Launchpad" ;;
        12) echo "Notification Center" ;;
        13) echo "Lock Screen" ;;
        14) echo "Quick Note" ;;
        *)  echo "$1" ;;
    esac
}

_CORNER_IDS=(0 2 3 4 5 6 10 11 12 13 14)

_pick_corner() {
    local label="$1" current="$2"

    local actions=("Keep current")
    for id in "${_CORNER_IDS[@]}"; do
        local name
        name=$(_corner_name "$id")
        actions+=("$name")
    done

    local choice
    MENU_NO_NUMBERS=true
    choice=$(show_menu "$label — $(_corner_name "$current")" "${actions[@]}")
    MENU_NO_NUMBERS=false

    if [[ "$choice" == "0" || "$choice" == "1" ]]; then
        echo "$current"
    else
        echo "${_CORNER_IDS[$((choice - 2))]}"
    fi
}

hot_corners_tweaks() {
    local cur_tl cur_tr cur_bl cur_br
    cur_tl=$(defaults read com.apple.dock wvous-tl-corner 2>/dev/null || echo "0")
    cur_tr=$(defaults read com.apple.dock wvous-tr-corner 2>/dev/null || echo "0")
    cur_bl=$(defaults read com.apple.dock wvous-bl-corner 2>/dev/null || echo "0")
    cur_br=$(defaults read com.apple.dock wvous-br-corner 2>/dev/null || echo "0")

    crumb_push "Hot Corners"

    local tl tr bl br
    local _tl_name _tr_name _bl_name _br_name
    _tl_name=$(_corner_name "$cur_tl")
    _tr_name=$(_corner_name "$cur_tr")
    _bl_name=$(_corner_name "$cur_bl")
    _br_name=$(_corner_name "$cur_br")

    _hot_corners_status() {
        printf '\n  %b◤%b %-20s %b◥%b %s\n' "$CYAN" "$RESET" "$_tl_name" "$CYAN" "$RESET" "$_tr_name"
        printf '  %b◣%b %-20s %b◢%b %s\n\n' "$CYAN" "$RESET" "$_bl_name" "$CYAN" "$RESET" "$_br_name"
    }

    clear; _hot_corners_status
    tl=$(_pick_corner "Top-left" "$cur_tl")
    _tl_name=$(_corner_name "$tl")

    clear; _hot_corners_status
    tr=$(_pick_corner "Top-right" "$cur_tr")
    _tr_name=$(_corner_name "$tr")

    clear; _hot_corners_status
    bl=$(_pick_corner "Bottom-left" "$cur_bl")
    _bl_name=$(_corner_name "$bl")

    clear; _hot_corners_status
    br=$(_pick_corner "Bottom-right" "$cur_br")
    _br_name=$(_corner_name "$br")

    crumb_pop

    # Summary
    local corners=("Top-left:$cur_tl:$tl" "Top-right:$cur_tr:$tr" "Bottom-left:$cur_bl:$bl" "Bottom-right:$cur_br:$br")
    local has_changes=false
    for c in "${corners[@]}"; do
        IFS=':' read -r _label cur new <<< "$c"
        [[ "$cur" != "$new" ]] && has_changes=true
    done

    if ! $has_changes; then
        clear
        printf '\n'
        log_ok "Hot corners unchanged"
        wait_enter
        return
    fi

    clear
    printf '\n'
    for c in "${corners[@]}"; do
        IFS=':' read -r label cur new <<< "$c"
        if [[ "$cur" == "$new" ]]; then
            printf '    %-18s %b%s%b\n' "$label" "$DIM" "$(_corner_name "$cur")" "$RESET"
        else
            printf '    %-18s %b%s%b → %b%s%b\n' "$label" "$DIM" "$(_corner_name "$cur")" "$RESET" "$GREEN" "$(_corner_name "$new")" "$RESET"
        fi
    done
    printf '\n'

    if ! confirm "Apply?"; then return; fi

    defaults write com.apple.dock wvous-tl-corner -int "$tl"
    defaults write com.apple.dock wvous-tr-corner -int "$tr"
    defaults write com.apple.dock wvous-bl-corner -int "$bl"
    defaults write com.apple.dock wvous-br-corner -int "$br"
    defaults write com.apple.dock wvous-tl-modifier -int 0
    defaults write com.apple.dock wvous-tr-modifier -int 0
    defaults write com.apple.dock wvous-bl-modifier -int 0
    defaults write com.apple.dock wvous-br-modifier -int 0
    log_ok "Hot corners applied"
    if confirm "Restart Dock?"; then
        killall Dock 2>/dev/null || true
        log_ok "Dock restarted"
    fi
    wait_enter
}
