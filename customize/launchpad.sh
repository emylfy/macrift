#!/usr/bin/env bash
# macrift — Launchpad layout management

_LP_SCRIPT="$MACRIFT_DIR/customize/launchpad_sort.py"

launchpad_menu() {
    crumb_push "Launchpad"
    while true; do
        clear

        local choice
        choice=$(show_menu "Launchpad" \
            "Sort by category (folders)" \
            "---" \
            "Reset to default" \
            "Back")

        case "$choice" in
            1) _lp_sort_by_category ;;
            2) _lp_reset ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

_lp_reset() {
    clear

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would reset Launchpad to defaults"
        wait_enter
        return
    fi

    if ! confirm "Reset Launchpad to default layout?"; then return; fi

    local lp_db darwin_dir
    darwin_dir=$(getconf DARWIN_USER_DIR)
    lp_db="${darwin_dir}com.apple.dock.launchpad/db/db"
    defaults write com.apple.dock ResetLaunchPad -bool true
    rm -f "$lp_db"
    killall Dock 2>/dev/null || true

    log_ok "Launchpad reset to defaults"
    wait_enter
}

_lp_sort_by_category() {
    clear

    if ! command -v python3 &>/dev/null; then
        log_err "python3 required"
        wait_enter
        return
    fi

    # Preview: get folder names and counts
    log_info "Scanning app categories..."
    local preview
    preview=$(python3 "$_LP_SCRIPT" preview 2>&1)

    if [[ -z "$preview" ]]; then
        log_warn "No third-party apps found to organize"
        wait_enter
        return
    fi

    echo ""
    log_info "Folders to create:"
    local folder_count=0
    while IFS='|' read -r cat_name count; do
        printf '    %s (%d apps)\n' "$cat_name" "$count"
        folder_count=$((folder_count + 1))
    done <<< "$preview"
    echo ""

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would create $folder_count folders"
        wait_enter
        return
    fi

    if ! confirm "Create $folder_count category folders?"; then return; fi

    local result
    result=$(python3 "$_LP_SCRIPT" apply 2>&1)

    if [[ "$result" == OK* ]]; then
        local created
        created=$(echo "$result" | cut -d'|' -f2)
        log_ok "Launchpad sorted into $created category folders"
    else
        log_err "Failed: $result"
    fi

    log_info "Reset: macrift > Customize > Launchpad > Reset to default"
    wait_enter
}
