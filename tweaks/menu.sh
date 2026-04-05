#!/usr/bin/env bash
# shellcheck disable=SC2218
# macrift — tweaks menu

TWEAK_SELECTION=()
TWEAK_RESETS=()

# Wizard: one category per screen, three states per item.
# States: 0=skip, 1=apply, 2=reset (defaults delete)
# Keys: space=toggle apply, d=toggle reset, a=all apply
_tweak_wizard() {
    local specs=("$@")
    local cat_count=${#specs[@]}

    local cat_names=() cat_starts=() cat_ends=() cat_sizes=()
    local ci
    for ci in "${specs[@]}"; do
        cat_names+=("${ci%%:*}")
        local bounds="${ci#*:}"
        cat_starts+=("${bounds%%:*}")
        cat_ends+=("${bounds#*:}")
        cat_sizes+=("$(( ${bounds#*:} - ${bounds%%:*} ))")
    done

    # State per entry: 0=skip, 1=apply (pre-set for pending), 2=reset
    # pending[i]=1 means current != new_val (space/a allowed), 0 means match (only d allowed)
    local state=() pending=()
    local sel_idx=() cat_sel_offsets=() cat_sel_counts=()
    local i _l _c _n _rest
    for ((c=0; c<cat_count; c++)); do
        cat_sel_offsets+=("${#sel_idx[@]}")
        local cs="${cat_starts[$c]}" ce="${cat_ends[$c]}" cnt=0
        for ((i=cs; i<ce; i++)); do
            [[ -z "${AUDIT_ENTRIES[$i]+x}" ]] && continue
            IFS='|' read -r _l _c _n _rest <<< "${AUDIT_ENTRIES[$i]}"
            [[ "$_l" == "---" ]] && continue
            sel_idx+=("$i")
            if [[ "$_c" != "$_n" ]]; then
                state[i]="1"; pending[i]=1
            else
                state[i]="0"; pending[i]=0
            fi
            cnt=$(( cnt + 1 ))
        done
        cat_sel_counts+=("$cnt")
    done

    local cursors=()
    for ((i=0; i<cat_count; i++)); do cursors[i]=0; done

    local cat_idx=0 wizard_done=false
    local R="${RESET}"

    stty -echo 2>/dev/null
    printf "\033[?25l" >&2

    while ! $wizard_done; do
        local cname="${cat_names[$cat_idx]}"
        local cstart="${cat_starts[$cat_idx]}"
        local cend="${cat_ends[$cat_idx]}"
        local csize="${cat_sizes[$cat_idx]}"
        local cursor="${cursors[$cat_idx]}"
        local sel_off="${cat_sel_offsets[$cat_idx]}"
        local sel_cnt="${cat_sel_counts[$cat_idx]}"

        # Count extra warning lines in this category
        local warn_lines=0
        for ((i=cstart; i<cend; i++)); do
            [[ -z "${AUDIT_ENTRIES[$i]+x}" ]] && continue
            IFS='|' read -r _l _rest <<< "${AUDIT_ENTRIES[$i]}"
            [[ "$_l" == *"~"* ]] && warn_lines=$(( warn_lines + 1 ))
        done
        local total_lines=$(( 1 + 1 + csize + warn_lines + 1 ))
        local first_draw=true

        while true; do
            printf "\033[?2026h" >&2
            if $first_draw; then
                first_draw=false
                clear
            else
                printf "\033[%dA\r" "$total_lines" >&2
            fi

            printf "\033[K\n" >&2

            # Progress dots — filled for visited/current, empty for remaining
            local dots="" p
            for ((p=0; p<cat_count; p++)); do
                if [[ $p -le $cat_idx ]]; then dots+="●"; else dots+="○"; fi
            done

            printf '  %b%s%b  %b%s%b\033[K\n' \
                "${BOLD}${ICE}" "$cname" "${RESET}" \
                "$DIM" "$dots" "$R" >&2

            local si=0
            for ((i=cstart; i<cend; i++)); do
                [[ -z "${AUDIT_ENTRIES[$i]+x}" ]] && continue
                IFS='|' read -r label current new_val _rest <<< "${AUDIT_ENTRIES[$i]}"

                if [[ "$label" == "---" ]]; then
                    printf '\033[K\n' >&2
                    continue
                fi

                # Extract warning hint if present (label~hint format)
                local warn=""
                if [[ "$label" == *"~"* ]]; then
                    warn="${label#*~}"
                    label="${label%%~*}"
                fi

                local fc fn
                fc=$(_friendly_val "$current")
                fn=$(_friendly_val "$new_val")
                local s="${state[$i]}"

                # Build display: "Label: value"
                local display=""
                local cursor_char="" icon_color=""
                if [[ "$s" == "2" ]]; then
                    display=$(printf '%s: %b%s%b → %b%s%b' "$label" "$DIM" "$fc" "$R" "$YELLOW" "reset" "$R")
                    cursor_char="[✗]"; icon_color="$RED"
                elif [[ "$s" == "1" ]]; then
                    if [[ "$current" == "$new_val" ]]; then
                        display=$(printf '%s: %b%s%b' "$label" "$DIM" "$fc" "$R")
                    elif [[ "$current" == "default" ]]; then
                        display=$(printf '%s: %b%s%b' "$label" "$GREEN" "$fn" "$R")
                    else
                        display=$(printf '%s: %b%s%b → %b%s%b' "$label" "$DIM" "$fc" "$R" "$GREEN" "$fn" "$R")
                    fi
                    cursor_char="[*]"; icon_color="$GREEN"
                else
                    if [[ "$current" == "$new_val" ]]; then
                        display=$(printf '%s: %b%s%b' "$label" "$DIM" "$fc" "$R")
                    elif [[ "$current" == "default" ]]; then
                        display=$(printf '%s: %b%s%b' "$label" "$DIM" "$fn" "$R")
                    else
                        display=$(printf '%s: %b%s%b → %b%s%b' "$label" "$DIM" "$fc" "$R" "$GREEN" "$fn" "$R")
                    fi
                    cursor_char=" ·"; icon_color="$DIM"
                fi

                if [[ $si -eq $cursor ]]; then
                    printf '  %b›%b %b%s%b %s\033[K\n' \
                        "$CYAN" "$R" "$icon_color" "$cursor_char" "$R" "$display" >&2
                else
                    printf '    %b%s%b %s\033[K\n' \
                        "$icon_color" "$cursor_char" "$R" "$display" >&2
                fi
                if [[ -n "$warn" ]]; then
                    if [[ "$s" != "0" ]]; then
                        printf '  %b      ! %s%b\033[K\n' "$YELLOW" "$warn" "$R" >&2
                    else
                        printf '  %b      %s%b\033[K\n' "$DIM" "$warn" "$R" >&2
                    fi
                fi
                si=$(( si + 1 ))
            done

            local hint="↑↓ move  ␣ apply  d reset  a all"
            if [[ $cat_count -eq 1 ]]; then
                hint+="  ↵ review"
            elif [[ $cat_idx -eq 0 ]]; then
                hint+="  →/↵ next"
            elif [[ $cat_idx -eq $(( cat_count - 1 )) ]]; then
                hint+="  ← prev  ↵ review"
            else
                hint+="  ←/→ prev/next"
            fi

            # Count totals across all categories
            local _ta=0 _tr=0 _ti
            for ((_ti=0; _ti<${#sel_idx[@]}; _ti++)); do
                local _si_idx="${sel_idx[$_ti]}"
                [[ "${state[$_si_idx]}" == "1" && "${pending[$_si_idx]}" == "1" ]] && _ta=$((_ta + 1))
                [[ "${state[$_si_idx]}" == "2" ]] && _tr=$((_tr + 1))
            done
            local _count=""
            [[ $_ta -gt 0 ]] && _count="${_ta} apply"
            [[ $_tr -gt 0 ]] && { [[ -n "$_count" ]] && _count+=", "; _count+="${_tr} reset"; }

            if [[ -n "$_count" ]]; then
                printf '  %b%s%b  %b· %s%b\033[K\n' "$DIM" "$hint" "$R" "$CYAN" "$_count" "$R" >&2
            else
                printf '  %b%s%b\033[K\n' "$DIM" "$hint" "$R" >&2
            fi

            printf "\033[?2026l" >&2

            local key=""
            IFS= read -rsn1 key < /dev/tty || true

            if [[ "$key" == $'\x1b' ]]; then
                local seq=""
                read -rsn2 -t 1 seq < /dev/tty || true
                case "$seq" in
                    '[A') [[ $cursor -gt 0 ]] && cursor=$(( cursor - 1 )) ;;
                    '[B') [[ $cursor -lt $(( sel_cnt - 1 )) ]] && cursor=$(( cursor + 1 )) ;;
                    '[C')
                        cursors[cat_idx]=$cursor
                        if [[ $cat_idx -lt $(( cat_count - 1 )) ]]; then
                            cat_idx=$(( cat_idx + 1 ))
                        else wizard_done=true; fi
                        break ;;
                    '[D')
                        cursors[cat_idx]=$cursor
                        if [[ $cat_idx -gt 0 ]]; then
                            cat_idx=$(( cat_idx - 1 ))
                            break
                        else
                            stty echo 2>/dev/null; printf "\033[?25h" >&2
                            TWEAK_SELECTION=(); TWEAK_RESETS=()
                            return 1
                        fi
                        ;;
                esac
            elif [[ "$key" == ' ' ]]; then
                local gsi=$(( sel_off + cursor ))
                local idx="${sel_idx[$gsi]}"
                # Only toggle apply for entries with pending changes
                if [[ "${pending[$idx]}" == 1 ]]; then
                    if [[ "${state[$idx]}" == "1" ]]; then state[idx]="0"; else state[idx]="1"; fi
                fi
            elif [[ "$key" == 'd' || "$key" == 'D' ]]; then
                local gsi=$(( sel_off + cursor ))
                local idx="${sel_idx[$gsi]}"
                # Toggle: 0→2, 1→2, 2→0
                if [[ "${state[$idx]}" == "2" ]]; then state[idx]="0"; else state[idx]="2"; fi
            elif [[ "$key" == 'a' || "$key" == 'A' ]]; then
                # Toggle all pending entries only
                local all_apply=true k
                for ((k=0; k<sel_cnt; k++)); do
                    local idx="${sel_idx[$((sel_off + k))]}"
                    [[ "${pending[$idx]}" == 0 ]] && continue
                    if [[ "${state[$idx]}" != "1" ]]; then all_apply=false; break; fi
                done
                local val="1"; if $all_apply; then val="0"; fi
                for ((k=0; k<sel_cnt; k++)); do
                    local idx="${sel_idx[$((sel_off + k))]}"
                    [[ "${pending[$idx]}" == 0 ]] && continue
                    state[idx]="$val"
                done
            elif [[ "$key" == '' ]]; then
                cursors[cat_idx]=$cursor
                if [[ $cat_idx -lt $(( cat_count - 1 )) ]]; then
                    cat_idx=$(( cat_idx + 1 ))
                else wizard_done=true; fi
                break
            fi
        done
    done

    stty echo 2>/dev/null
    printf "\033[?25h" >&2

    # Summary
    clear
    printf "\n"

    local total_apply=0 total_reset=0 cats_active=0
    for ((c=0; c<cat_count; c++)); do
        local off="${cat_sel_offsets[$c]}" cnt="${cat_sel_counts[$c]}"
        local cat_apply=0 cat_reset=0 k
        for ((k=0; k<cnt; k++)); do
            local idx="${sel_idx[$((off + k))]}"
            if [[ "${state[$idx]}" == "1" ]]; then cat_apply=$(( cat_apply + 1 )); fi
            if [[ "${state[$idx]}" == "2" ]]; then cat_reset=$(( cat_reset + 1 )); fi
        done
        if [[ $cat_apply -gt 0 || $cat_reset -gt 0 ]]; then
            local detail=""
            if [[ $cat_apply -gt 0 ]]; then detail="${cat_apply} apply"; fi
            if [[ $cat_reset -gt 0 ]]; then
                if [[ -n "$detail" ]]; then detail+=", "; fi
                detail+="${cat_reset} reset"
            fi
            printf '  %b✓%b %s — %s\n' "$GREEN" "$RESET" "${cat_names[$c]}" "$detail"
            total_apply=$(( total_apply + cat_apply ))
            total_reset=$(( total_reset + cat_reset ))
            cats_active=$(( cats_active + 1 ))
        else
            printf '  %b-%b %s\n' "$DIM" "$RESET" "${cat_names[$c]}"
        fi
    done

    printf "\n"

    local total=$(( total_apply + total_reset ))
    if [[ $total -eq 0 ]]; then
        log_info "Nothing selected"
        wait_enter
        TWEAK_SELECTION=(); TWEAK_RESETS=()
        return
    fi

    local summary=""
    if [[ $total_apply -gt 0 ]]; then summary="${total_apply} apply"; fi
    if [[ $total_reset -gt 0 ]]; then
        if [[ -n "$summary" ]]; then summary+=", "; fi
        summary+="${total_reset} reset"
    fi
    printf '  %b%s from %d categories%b\n\n' "$BOLD" "$summary" "$cats_active" "$RESET"

    if ! confirm "Apply?"; then
        TWEAK_SELECTION=(); TWEAK_RESETS=()
        return
    fi

    TWEAK_SELECTION=(); TWEAK_RESETS=()
    for ci in "${specs[@]}"; do
        local bounds="${ci#*:}"
        local cs="${bounds%%:*}" ce="${bounds#*:}"
        for ((i=cs; i<ce; i++)); do
            [[ -z "${AUDIT_ENTRIES[$i]+x}" ]] && continue
            IFS='|' read -r _l _rest <<< "${AUDIT_ENTRIES[$i]}"
            [[ "$_l" == "---" ]] && continue
            if [[ "${state[$i]}" == "1" ]]; then TWEAK_SELECTION+=("${AUDIT_ENTRIES[$i]}"); fi
            if [[ "${state[$i]}" == "2" ]]; then TWEAK_RESETS+=("${AUDIT_ENTRIES[$i]}"); fi
        done
    done
}

select_tweaks() {
    clear

    local cat_names=("Dock" "Finder" "Keyboard & Text" "Trackpad & Mouse" "Screenshots" "Misc" "Hot Corners")

    while true; do
        audit_reset
        MACRIFT_BATCH_TWEAKS=true

        local dock_s=0
        source "$MACRIFT_DIR/tweaks/dock.sh" && dock_tweaks
        local dock_e=${#AUDIT_ENTRIES[@]}

        local finder_s=$dock_e
        source "$MACRIFT_DIR/tweaks/finder.sh" && finder_tweaks
        local finder_e=${#AUDIT_ENTRIES[@]}

        local keyboard_s=$finder_e
        source "$MACRIFT_DIR/tweaks/keyboard.sh" && keyboard_tweaks
        local keyboard_e=${#AUDIT_ENTRIES[@]}

        local input_s=$keyboard_e
        source "$MACRIFT_DIR/tweaks/input.sh" && input_tweaks
        local input_e=${#AUDIT_ENTRIES[@]}

        local screenshots_s=$input_e
        source "$MACRIFT_DIR/tweaks/screenshots.sh" && screenshots_tweaks
        local screenshots_e=${#AUDIT_ENTRIES[@]}

        local misc_s=$screenshots_e
        source "$MACRIFT_DIR/tweaks/misc.sh" && misc_tweaks
        local misc_e=${#AUDIT_ENTRIES[@]}

        MACRIFT_BATCH_TWEAKS=false

        MULTISELECT_HINT="↑↓ move  space toggle  a all  enter → view tweaks"
        local selected_cats
        selected_cats=$(show_multiselect "System Tweaks" "${cat_names[@]}")
        MULTISELECT_HINT=""
        [[ -z "$selected_cats" ]] && { audit_reset; return; }

        local do_hot_corners=false
        echo "$selected_cats" | grep -qxF "Hot Corners" && do_hot_corners=true

        local specs=()
        echo "$selected_cats" | grep -qxF "Dock"             && specs+=("Dock:${dock_s}:${dock_e}")
        echo "$selected_cats" | grep -qxF "Finder"           && specs+=("Finder:${finder_s}:${finder_e}")
        echo "$selected_cats" | grep -qxF "Keyboard & Text"  && specs+=("Keyboard & Text:${keyboard_s}:${keyboard_e}")
        echo "$selected_cats" | grep -qxF "Trackpad & Mouse" && specs+=("Trackpad & Mouse:${input_s}:${input_e}")
        echo "$selected_cats" | grep -qxF "Screenshots"      && specs+=("Screenshots:${screenshots_s}:${screenshots_e}")
        echo "$selected_cats" | grep -qxF "Misc"             && specs+=("Misc:${misc_s}:${misc_e}")

        # Run tweak wizard if any defaults-based categories selected
        if [[ ${#specs[@]} -gt 0 ]]; then
            if ! _tweak_wizard "${specs[@]}"; then
                clear
                continue
            fi

            if [[ ${#TWEAK_SELECTION[@]} -gt 0 || ${#TWEAK_RESETS[@]} -gt 0 ]]; then
                clear

                local need_dock=false need_finder=false

                if [[ ${#TWEAK_SELECTION[@]} -gt 0 ]]; then
                    AUDIT_ENTRIES=("${TWEAK_SELECTION[@]}")
                    apply_audited_defaults
                fi

                if [[ ${#TWEAK_RESETS[@]} -gt 0 ]]; then
                    RESET_ENTRIES=("${TWEAK_RESETS[@]}")
                    apply_reset_defaults
                fi

                local domain
                for domain in "${MACRIFT_CHANGED_DOMAINS[@]:+${MACRIFT_CHANGED_DOMAINS[@]}}"; do
                    [[ "$domain" == *"dock"* ]]                                       && need_dock=true
                    [[ "$domain" == *"finder"* || "$domain" == *"desktopservices"* ]] && need_finder=true
                done
                MACRIFT_CHANGED_DOMAINS=()

                TWEAK_SELECTION=(); TWEAK_RESETS=()

                if $need_dock || $need_finder; then
                    printf '\n'
                    if confirm "Restart affected services?"; then
                        $need_dock   && { killall Dock 2>/dev/null || true;   log_ok "Dock restarted"; }
                        $need_finder && { killall Finder 2>/dev/null || true; log_ok "Finder restarted"; }
                    else
                        log_info "Restart skipped — changes apply after logout"
                    fi
                fi

                wait_enter
            fi
        fi

        # Run Hot Corners if selected
        if $do_hot_corners; then
            source "$MACRIFT_DIR/tweaks/dock.sh" && hot_corners_tweaks
        fi

        clear
    done

    audit_reset
}

tweaks_menu() {
    crumb_push "System Tweaks"
    set_title "macrift > tweaks"
    select_tweaks
    crumb_pop
}
