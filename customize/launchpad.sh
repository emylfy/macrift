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

    log_info "Scanning app categories..."
    local preview
    preview=$(python3 "$_LP_SCRIPT" preview 2>&1)

    if [[ -z "$preview" ]]; then
        log_warn "No third-party apps found to organize"
        wait_enter
        return
    fi

    local -a cat_items=() cat_names=()
    while IFS='|' read -r cat_name count; do
        cat_items+=("$(printf '%s (%d apps)' "$cat_name" "$count")")
        cat_names+=("$cat_name")
    done <<< "$preview"

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        echo ""
        log_info "Folders to create:"
        local item
        for item in "${cat_items[@]}"; do
            printf '    %s\n' "$item"
        done
        log_info "Dry run — would create ${#cat_items[@]} folders"
        wait_enter
        return
    fi

    clear
    local selected_display
    selected_display=$(show_multiselect "Folders to create" "${cat_items[@]}")

    if [[ -z "$selected_display" ]]; then
        log_info "Nothing selected"
        wait_enter
        return
    fi

    local -a selected_cats=()
    while IFS= read -r line; do
        local i
        for i in "${!cat_items[@]}"; do
            if [[ "${cat_items[$i]}" == "$line" ]]; then
                selected_cats+=("${cat_names[$i]}")
                break
            fi
        done
    done <<< "$selected_display"

    log_info "Reset to default gives a clean starting layout (recommended)"
    if confirm "Reset Launchpad before sorting?" "n"; then
        local lp_db darwin_dir
        darwin_dir=$(getconf DARWIN_USER_DIR)
        lp_db="${darwin_dir}com.apple.dock.launchpad/db/db"
        defaults write com.apple.dock ResetLaunchPad -bool true
        rm -f "$lp_db"
        killall Dock 2>/dev/null || true
        local tries=0
        while [[ ! -s "$lp_db" && $tries -lt 30 ]]; do
            sleep 0.2
            tries=$((tries + 1))
        done
        sleep 0.5
        log_ok "Launchpad reset"
    fi

    local result
    result=$(python3 "$_LP_SCRIPT" apply "${selected_cats[@]}" 2>&1)

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
