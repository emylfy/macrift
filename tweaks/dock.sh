#!/usr/bin/env bash
# macrift — Dock tweaks

dock_tweaks() {
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

_corner_count=${#_CORNER_IDS[@]}

# Show inline picker for corner action, returns selected ID
_pick_corner_action() {
    local current="$1"

    # Build labels and find current selection
    local action_labels=()
    local cur_sel=0
    local i
    for ((i=0; i<_corner_count; i++)); do
        action_labels+=("$(_corner_name "${_CORNER_IDS[$i]}")")
        [[ "${_CORNER_IDS[$i]}" == "$current" ]] && cur_sel=$i
    done

    local sel=$cur_sel
    local total=${#action_labels[@]}
    local R="$RESET"

    # Render picker as vertical list
    local list_lines=$((total + 2))  # items + blank + hint
    local first=true

    while true; do
        if $first; then
            first=false
            printf '\n' >&2
        else
            printf "\033[%dA\r" "$list_lines" >&2
        fi

        for ((i=0; i<total; i++)); do
            if [[ $i -eq $sel ]]; then
                printf '      %b› %s%b\033[K\n' "${BOLD}${ICE}" "${action_labels[$i]}" "$R" >&2
            else
                printf '        %b%s%b\033[K\n' "$DIM" "${action_labels[$i]}" "$R" >&2
            fi
        done
        printf '\033[K\n' >&2
        printf '      %b↑↓ pick  ↵ select  ← cancel%b\033[K\n' "$DIM" "$R" >&2

        local key
        key=$(_read_key)
        case "$key" in
            up)    [[ $sel -gt 0 ]] && sel=$((sel - 1)) ;;
            down)  [[ $sel -lt $((total - 1)) ]] && sel=$((sel + 1)) ;;
            enter|right|space)
                # Clear picker lines
                printf "\033[%dA\r" "$list_lines" >&2
                for ((i=0; i<list_lines; i++)); do printf '\033[K\n' >&2; done
                printf "\033[%dA\r" "$list_lines" >&2
                echo "${_CORNER_IDS[$sel]}"
                return ;;
            left)
                # Cancel — clear and return current
                printf "\033[%dA\r" "$list_lines" >&2
                for ((i=0; i<list_lines; i++)); do printf '\033[K\n' >&2; done
                printf "\033[%dA\r" "$list_lines" >&2
                echo "$current"
                return ;;
        esac
    done
}

hot_corners_tweaks() {
    local keys=("wvous-tl-corner" "wvous-tr-corner" "wvous-bl-corner" "wvous-br-corner")
    local labels=("◤ Top-left" "◥ Top-right" "◣ Bottom-left" "◢ Bottom-right")
    local orig=() vals=()
    local i

    for ((i=0; i<4; i++)); do
        orig[i]=$(defaults read com.apple.dock "${keys[$i]}" 2>/dev/null || echo "0")
        vals[i]="${orig[i]}"
    done

    crumb_push "Hot Corners"
    _ui_start

    # Grid navigation: 0=TL, 1=TR, 2=BL, 3=BR
    local cursor=0 first_draw=true
    # total_lines: blank + title + blank + TL/TR row + blank + BL/BR row + blank + hint
    local total_lines=8

    _fmt_corner() {
        local idx="$1"
        local icon="${labels[$idx]%% *}"  # ◤ ◥ ◣ ◢
        local name
        name=$(_corner_name "${vals[$idx]}")
        local color="$DIM"
        [[ "${vals[$idx]}" != "${orig[$idx]}" ]] && color="$GREEN"

        if [[ $idx -eq $cursor ]]; then
            printf '%b›%b %b%s%b %b%-18s%b' "$CYAN" "$RESET" "$BOLD" "$icon" "$RESET" "$color" "$name" "$RESET"
        else
            printf '  %b%s%b %b%-18s%b' "$DIM" "$icon" "$RESET" "$color" "$name" "$RESET"
        fi
    }

    while true; do
        if $first_draw; then
            first_draw=false
            clear
            printf "\033[K\n" >&2
        else
            printf "\033[?2026h" >&2
            printf "\033[%dA\r" "$total_lines" >&2
            printf "\033[K\n" >&2
        fi

        printf '  %b%bHot Corners%b\033[K\n\n' "${BOLD}" "${ICE}" "${RESET}" >&2

        # Top row: TL  TR
        printf '  %s    %s\033[K\n' "$(_fmt_corner 0)" "$(_fmt_corner 1)" >&2
        printf '\033[K\n' >&2
        # Bottom row: BL  BR
        printf '  %s    %s\033[K\n' "$(_fmt_corner 2)" "$(_fmt_corner 3)" >&2

        printf '\033[K\n' >&2
        printf '  %b↑↓←→ move  ↵/␣ pick action  → done%b\033[K\n' "$DIM" "$RESET" >&2
        printf "\033[?2026l" >&2

        local key
        key=$(_read_key)
        case "$key" in
            up)    [[ $cursor -ge 2 ]] && cursor=$((cursor - 2)) ;;     # BL→TL, BR→TR
            down)  [[ $cursor -le 1 ]] && cursor=$((cursor + 2)) ;;     # TL→BL, TR→BR
            left)  if [[ $((cursor % 2)) -eq 1 ]]; then cursor=$((cursor - 1)); else _ui_end; crumb_pop; return; fi ;;
            right) if [[ $((cursor % 2)) -eq 0 ]]; then cursor=$((cursor + 1)); else _ui_end; break; fi ;;
            space|enter)
                local picked
                picked=$(_pick_corner_action "${vals[cursor]}")
                vals[cursor]="$picked"
                first_draw=true
                ;;
        esac
    done

    # Check for changes
    local has_changes=false
    for ((i=0; i<4; i++)); do
        [[ "${vals[i]}" != "${orig[i]}" ]] && has_changes=true
    done

    if ! $has_changes; then
        log_ok "Hot corners unchanged"
        wait_enter
        crumb_pop
        return
    fi

    # Summary — grid layout with icons only
    clear
    printf '\n'
    local icons=("◤" "◥" "◣" "◢")
    for row in 0 2; do
        local left=$row right=$((row + 1))
        local l_str r_str
        if [[ "${vals[$left]}" == "${orig[$left]}" ]]; then
            l_str=$(printf '%s %b%-18s%b' "${icons[$left]}" "$DIM" "$(_corner_name "${orig[$left]}")" "$RESET")
        else
            l_str=$(printf '%s %b%s%b → %b%s%b' "${icons[$left]}" "$DIM" "$(_corner_name "${orig[$left]}")" "$RESET" "$GREEN" "$(_corner_name "${vals[$left]}")" "$RESET")
        fi
        if [[ "${vals[$right]}" == "${orig[$right]}" ]]; then
            r_str=$(printf '%s %b%-18s%b' "${icons[$right]}" "$DIM" "$(_corner_name "${orig[$right]}")" "$RESET")
        else
            r_str=$(printf '%s %b%s%b → %b%s%b' "${icons[$right]}" "$DIM" "$(_corner_name "${orig[$right]}")" "$RESET" "$GREEN" "$(_corner_name "${vals[$right]}")" "$RESET")
        fi
        printf '    %s    %s\n' "$l_str" "$r_str"
        [[ $row -eq 0 ]] && printf '\n'
    done
    printf '\n'

    if ! confirm "Apply?"; then crumb_pop; return; fi

    for ((i=0; i<4; i++)); do
        defaults write com.apple.dock "${keys[$i]}" -int "${vals[i]}"
        defaults write com.apple.dock "${keys[$i]%%-corner}-modifier" -int 0
    done
    log_ok "Hot corners applied"
    if confirm "Restart Dock?"; then
        killall Dock 2>/dev/null || true
        log_ok "Dock restarted"
    fi
    wait_enter
    crumb_pop
}
