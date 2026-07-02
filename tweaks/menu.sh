#!/usr/bin/env bash
# shellcheck disable=SC2218
# macrift — tweaks menu

# Output arrays populated by _tweak_wizard; read by select_tweaks after wizard returns
TWEAK_SELECTION=()
TWEAK_RESETS=()

# Tweak wizard: one category per screen, three actions per item.
# Each spec is "Name:start_idx:end_idx" pointing into AUDIT_ENTRIES[].
# Actions: 0=skip, 1=apply, 2=reset (defaults delete)
# has_diff[i]=1 means current != new (space/a toggles allowed), 0 means match (only d allowed)
_tweak_wizard() {
    local specs=("$@")
    local cat_count=${#specs[@]}

    # --- Parse specs ---
    local cat_names=() cat_starts=() cat_ends=()
    local ci bounds
    for ci in "${specs[@]}"; do
        cat_names+=("${ci%%:*}")
        bounds="${ci#*:}"
        local s_idx="${bounds%%:*}"
        local e_idx="${bounds#*:}"
        cat_starts+=("$s_idx")
        cat_ends+=("$e_idx")
    done

    # --- Init state ---
    local action=() has_diff=() init_action=()
    local sel_idx=() cat_sel_offsets=() cat_sel_counts=()
    local i c label current new_val rest
    for ((c=0; c<cat_count; c++)); do
        cat_sel_offsets+=("${#sel_idx[@]}")
        local cs="${cat_starts[$c]}" ce="${cat_ends[$c]}" cnt=0
        for ((i=cs; i<ce; i++)); do
            [[ -z "${AUDIT_ENTRIES[$i]+x}" ]] && continue
            IFS='|' read -r label current new_val rest <<< "${AUDIT_ENTRIES[$i]}"
            [[ "$label" == "---" ]] && continue
            sel_idx+=("$i")
            if [[ "$current" != "$new_val" ]]; then
                # Opt-in entries (index registered in AUDIT_OPTIONAL) stay unchecked even when current != new
                if [[ "$AUDIT_OPTIONAL" == *" $i "* ]]; then
                    action[i]="0"; has_diff[i]=1
                else
                    action[i]="1"; has_diff[i]=1
                fi
            else
                action[i]="0"; has_diff[i]=0
            fi
            init_action[i]="${action[i]}"
            cnt=$(( cnt + 1 ))
        done
        cat_sel_counts+=("$cnt")
    done

    local cursors=()
    for ((i=0; i<cat_count; i++)); do cursors[i]=0; done

    local cat_idx=0 wizard_done=false
    local R="${RESET}"
    local BAR="${BOLD}${CYAN}▌${R}"   # same cursor bar as the box widgets

    _ui_start

    # --- Interactive loop ---
    while ! $wizard_done; do
        # Category name may carry a dim subtitle after a US byte (\x1f),
        # mirroring show_menu's convention
        local cname="${cat_names[$cat_idx]}" csub=""
        if [[ "$cname" == *$'\x1f'* ]]; then
            csub="${cname#*$'\x1f'}"
            cname="${cname%%$'\x1f'*}"
        fi
        local cstart="${cat_starts[$cat_idx]}"
        local cend="${cat_ends[$cat_idx]}"
        local cursor="${cursors[$cat_idx]}"
        local sel_off="${cat_sel_offsets[$cat_idx]}"
        local sel_cnt="${cat_sel_counts[$cat_idx]}"

        # Render units: one per entry ("---" separators are height-1, entries
        # with a ~warning are height-2). Drives both frame height and the
        # viewport — tall categories (Finder is 25 body lines) must scroll or
        # the \033[NA reposition desyncs and smears frames.
        local units=() unit_h=() sel_unit=() body_h=0
        for ((i=cstart; i<cend; i++)); do
            [[ -z "${AUDIT_ENTRIES[$i]+x}" ]] && continue
            IFS='|' read -r label rest <<< "${AUDIT_ENTRIES[$i]}"
            if [[ "$label" == "---" ]]; then
                units+=("sep"); unit_h+=(1); body_h=$(( body_h + 1 ))
                continue
            fi
            local uh=1; [[ "$label" == *"~"* ]] && uh=2
            sel_unit+=("${#units[@]}")
            units+=("$i"); unit_h+=("$uh"); body_h=$(( body_h + uh ))
        done
        local unit_count=${#units[@]}

        # Viewport: chrome = lead blank + header + blank + blank + hint (5) + 2 slack
        local term_h; term_h=$(tput lines 2>/dev/null || echo 24)
        local avail=$(( term_h - 7 ))
        local w_scroll=false view_h=$body_h wvp=0
        if [[ $body_h -gt $avail ]]; then
            w_scroll=true
            view_h=$(( avail - 2 ))   # two indicator lines
            [[ $view_h -lt 4 ]] && view_h=4
        fi

        local body_render_h=$view_h
        $w_scroll && body_render_h=$(( body_render_h + 2 ))
        local total_lines=$(( 1 + 1 + 1 + body_render_h + 1 + 1 ))
        local first_draw=true

        while true; do
            # --- Render ---
            if $first_draw; then
                first_draw=false
                clear
                printf "\033[K\n" >&2
            else
                printf "\033[?2026h" >&2
                printf "\033[%dA\r" "$total_lines" >&2
                printf "\033[K\n" >&2
            fi

            # Progress dots + step counter
            local dots="" p
            for ((p=0; p<cat_count; p++)); do
                if [[ $p -le $cat_idx ]]; then dots+="●"; else dots+="○"; fi
            done
            printf '  %b%s%b  %b%s %d/%d%b\033[K\n' \
                "${BOLD}${ICE}" "$cname" "${RESET}" "$DIM" "$dots" "$((cat_idx + 1))" "$cat_count" "$R" >&2
            # The gap line doubles as the category subtitle slot
            if [[ -n "$csub" ]]; then
                printf '  %b%s%b\033[K\n' "$DIM" "$csub" "$R" >&2
            else
                printf '\033[K\n' >&2
            fi

            # Adjust viewport so the cursor's unit is fully visible
            if $w_scroll; then
                local cu="${sel_unit[$cursor]}"
                if [[ $cu -lt $wvp ]]; then
                    wvp=$cu
                    # Pull a directly preceding separator into view
                    [[ $wvp -gt 0 && "${units[$((wvp-1))]}" == "sep" ]] && wvp=$(( wvp - 1 ))
                fi
                local _h _u _ok
                while true; do
                    _h=0; _ok=false
                    for ((_u=wvp; _u<unit_count; _u++)); do
                        _h=$(( _h + ${unit_h[$_u]} ))
                        [[ $_h -gt $view_h ]] && break
                        [[ $_u -eq $cu ]] && { _ok=true; break; }
                    done
                    $_ok && break
                    wvp=$(( wvp + 1 ))
                done
            fi

            # Scroll-up indicator (slot reserved whenever scrolling)
            if $w_scroll; then
                if [[ $wvp -gt 0 ]]; then
                    printf '      %b▲ ···%b\033[K\n' "$DIM" "$R" >&2
                else
                    printf '\033[K\n' >&2
                fi
            fi

            # Render entries
            local si=0 drawn=0 u
            for ((u=0; u<unit_count; u++)); do
                if $w_scroll && [[ $u -lt $wvp ]]; then
                    # Off-screen above — still advances the selectable index
                    [[ "${units[$u]}" != "sep" ]] && si=$(( si + 1 ))
                    continue
                fi
                if $w_scroll && [[ $(( drawn + ${unit_h[$u]} )) -gt $view_h ]]; then
                    break
                fi
                if [[ "${units[$u]}" == "sep" ]]; then
                    printf '\033[K\n' >&2
                    drawn=$(( drawn + 1 ))
                    continue
                fi
                i=${units[$u]}
                IFS='|' read -r label current new_val rest <<< "${AUDIT_ENTRIES[$i]}"

                # Warning hint (label~hint format)
                local warn=""
                if [[ "$label" == *"~"* ]]; then
                    warn="${label#*~}"; label="${label%%~*}"
                fi

                local fc fn
                fc=$(_friendly_val "$current")
                fn=$(_friendly_val "$new_val")
                local act="${action[i]}"

                # Build display line
                local display="" cursor_char="" icon_color=""
                if [[ "$act" == "2" ]]; then
                    display=$(printf '%s: %b%s%b → %b%s%b' "$label" "$DIM" "$fc" "$R" "$YELLOW" "reset" "$R")
                    cursor_char="[↺]"; icon_color="$YELLOW"
                elif [[ "$act" == "1" ]]; then
                    if [[ "$current" == "$new_val" ]]; then
                        display=$(printf '%s: %b%s%b' "$label" "$DIM" "$fc" "$R")
                    elif [[ "$current" == "default" ]]; then
                        display=$(printf '%s: %b%s%b' "$label" "$GREEN" "$fn" "$R")
                    else
                        display=$(printf '%s: %b%s%b → %b%s%b' "$label" "$DIM" "$fc" "$R" "$GREEN" "$fn" "$R")
                    fi
                    cursor_char="[✓]"; icon_color="$GREEN"
                else
                    if [[ "$current" == "$new_val" ]]; then
                        display=$(printf '%s: %b%s%b' "$label" "$DIM" "$fc" "$R")
                    elif [[ "$current" == "default" ]]; then
                        display=$(printf '%s: %b%s%b' "$label" "$DIM" "$fn" "$R")
                    else
                        display=$(printf '%s: %b%s%b → %b%s%b' "$label" "$DIM" "$fc" "$R" "$GREEN" "$fn" "$R")
                    fi
                    cursor_char="[ ]"; icon_color="$DIM"
                fi

                if [[ $si -eq $cursor ]]; then
                    printf ' %b  %b%s%b %s\033[K\n' "$BAR" "$icon_color" "$cursor_char" "$R" "$display" >&2
                else
                    printf '    %b%s%b %s\033[K\n' "$icon_color" "$cursor_char" "$R" "$display" >&2
                fi
                if [[ -n "$warn" ]]; then
                    if [[ "$act" != "0" ]]; then
                        printf '  %b      ! %s%b\033[K\n' "$YELLOW" "$warn" "$R" >&2
                    else
                        printf '  %b      %s%b\033[K\n' "$DIM" "$warn" "$R" >&2
                    fi
                fi
                si=$(( si + 1 ))
                drawn=$(( drawn + ${unit_h[$u]} ))
            done

            # Pad to constant height, then scroll-down indicator
            if $w_scroll; then
                while [[ $drawn -lt $view_h ]]; do
                    printf '\033[K\n' >&2
                    drawn=$(( drawn + 1 ))
                done
                if [[ $u -lt $unit_count ]]; then
                    printf '      %b▼ ···%b\033[K\n' "$DIM" "$R" >&2
                else
                    printf '\033[K\n' >&2
                fi
            fi

            # Hint line
            printf '\033[K\n' >&2
            # space cycles the active item: skip [ ] → apply [✓] → reset [↺]
            local hint="↑↓ move  space skip→apply→reset  a all"
            if [[ $cat_count -eq 1 ]]; then hint+="  ↵ review  ← cancel"
            elif [[ $cat_idx -eq 0 ]]; then hint+="  →/↵ next  ← cancel"
            elif [[ $cat_idx -eq $(( cat_count - 1 )) ]]; then hint+="  ← prev  ↵ review"
            else hint+="  ←/→ prev/next"
            fi

            # Totals across all categories
            local total_apply=0 total_reset=0 ti si_idx
            for ((ti=0; ti<${#sel_idx[@]}; ti++)); do
                si_idx="${sel_idx[$ti]}"
                [[ "${action[$si_idx]}" == "1" && "${has_diff[$si_idx]}" == "1" ]] && total_apply=$((total_apply + 1))
                [[ "${action[$si_idx]}" == "2" ]] && total_reset=$((total_reset + 1))
            done
            local count_str=""
            [[ $total_apply -gt 0 ]] && count_str="${total_apply} apply"
            [[ $total_reset -gt 0 ]] && { [[ -n "$count_str" ]] && count_str+=", "; count_str+="${total_reset} reset"; }

            if [[ -n "$count_str" ]]; then
                printf '  %b%s%b  %b· %s%b\033[K\n' "$DIM" "$hint" "$R" "$CYAN" "$count_str" "$R" >&2
            else
                printf '  %b%s%b\033[K\n' "$DIM" "$hint" "$R" >&2
            fi
            printf "\033[?2026l" >&2

            # --- Input ---
            local key
            key=$(_read_key)
            case "$key" in
                up|k)   [[ $cursor -gt 0 ]] && cursor=$(( cursor - 1 )) ;;
                down|j) [[ $cursor -lt $(( sel_cnt - 1 )) ]] && cursor=$(( cursor + 1 )) ;;
                right|enter)
                    cursors[cat_idx]=$cursor
                    if [[ $cat_idx -lt $(( cat_count - 1 )) ]]; then
                        cat_idx=$(( cat_idx + 1 ))
                    else wizard_done=true; fi
                    break ;;
                left|esc)
                    cursors[cat_idx]=$cursor
                    if [[ $cat_idx -gt 0 ]]; then
                        cat_idx=$(( cat_idx - 1 )); break
                    else
                        # Cancelling from step 1 discards every category's marks —
                        # only ask when the user actually changed something.
                        local changed=false ci2
                        for ci2 in "${sel_idx[@]}"; do
                            [[ "${action[$ci2]}" != "${init_action[$ci2]}" ]] && { changed=true; break; }
                        done
                        if $changed; then
                            _ui_end
                            printf '\n'
                            if ! confirm "Discard changes and leave the wizard?" "n"; then
                                _ui_start
                                first_draw=true
                                continue
                            fi
                        fi
                        _ui_end
                        TWEAK_SELECTION=(); TWEAK_RESETS=()
                        return 1
                    fi ;;
                space)
                    # Single mutation key: skip(0) → apply(1) → reset(2) → skip.
                    # Items with no diff skip the apply step (nothing to apply).
                    local idx="${sel_idx[$((sel_off + cursor))]}"
                    case "${action[idx]}" in
                        0) if [[ "${has_diff[$idx]}" == 1 ]]; then action[idx]="1"; else action[idx]="2"; fi ;;
                        1) action[idx]="2" ;;
                        *) action[idx]="0" ;;
                    esac ;;
                a|A)
                    local all_apply=true k
                    for ((k=0; k<sel_cnt; k++)); do
                        local idx="${sel_idx[$((sel_off + k))]}"
                        [[ "${has_diff[$idx]}" == 0 ]] && continue
                        [[ "${action[idx]}" != "1" ]] && { all_apply=false; break; }
                    done
                    local val="1"; $all_apply && val="0"
                    for ((k=0; k<sel_cnt; k++)); do
                        local idx="${sel_idx[$((sel_off + k))]}"
                        [[ "${has_diff[$idx]}" == 0 ]] && continue
                        action[idx]="$val"
                    done ;;
            esac
        done
    done

    _ui_end

    # --- Summary ---
    clear
    printf "\n"

    local sum_apply=0 sum_reset=0 cats_active=0
    for ((c=0; c<cat_count; c++)); do
        local off="${cat_sel_offsets[$c]}" cnt="${cat_sel_counts[$c]}"
        local cat_apply=0 cat_reset=0 k
        for ((k=0; k<cnt; k++)); do
            local idx="${sel_idx[$((off + k))]}"
            [[ "${action[idx]}" == "1" ]] && cat_apply=$(( cat_apply + 1 ))
            [[ "${action[idx]}" == "2" ]] && cat_reset=$(( cat_reset + 1 ))
        done
        if [[ $cat_apply -gt 0 || $cat_reset -gt 0 ]]; then
            local detail=""
            [[ $cat_apply -gt 0 ]] && detail="${cat_apply} apply"
            if [[ $cat_reset -gt 0 ]]; then
                [[ -n "$detail" ]] && detail+=", "
                detail+="${cat_reset} reset"
            fi
            printf '  %b✓%b %s — %s\n' "$GREEN" "$RESET" "${cat_names[$c]%%$'\x1f'*}" "$detail"
            sum_apply=$(( sum_apply + cat_apply ))
            sum_reset=$(( sum_reset + cat_reset ))
            cats_active=$(( cats_active + 1 ))
        else
            printf '  %b-%b %s\n' "$DIM" "$RESET" "${cat_names[$c]%%$'\x1f'*}"
        fi
    done

    printf "\n"

    local total=$(( sum_apply + sum_reset ))
    if [[ $total -eq 0 ]]; then
        log_info "Nothing selected"
        wait_enter
        TWEAK_SELECTION=(); TWEAK_RESETS=()
        return 0
    fi

    local summary=""
    [[ $sum_apply -gt 0 ]] && summary="${sum_apply} apply"
    if [[ $sum_reset -gt 0 ]]; then
        [[ -n "$summary" ]] && summary+=", "
        summary+="${sum_reset} reset"
    fi
    local cats_word="categories"
    [[ $cats_active -eq 1 ]] && cats_word="category"
    printf '  %b%s from %d %s%b\n\n' "$BOLD" "$summary" "$cats_active" "$cats_word" "$RESET"
    if [[ $sum_reset -gt 0 ]]; then
        printf '  %breset = restore the macOS default (deletes the custom value)%b\n\n' "$DIM" "$RESET"
    fi

    if ! confirm "Apply?" "y"; then
        TWEAK_SELECTION=(); TWEAK_RESETS=()
        return 0
    fi

    # --- Collect results ---
    TWEAK_SELECTION=(); TWEAK_RESETS=()
    for ci in "${specs[@]}"; do
        bounds="${ci#*:}"
        local cs="${bounds%%:*}" ce="${bounds#*:}"
        for ((i=cs; i<ce; i++)); do
            [[ -z "${AUDIT_ENTRIES[$i]+x}" ]] && continue
            IFS='|' read -r label rest <<< "${AUDIT_ENTRIES[$i]}"
            [[ "$label" == "---" ]] && continue
            [[ "${action[i]}" == "1" ]] && TWEAK_SELECTION+=("${AUDIT_ENTRIES[$i]}")
            [[ "${action[i]}" == "2" ]] && TWEAK_RESETS+=("${AUDIT_ENTRIES[$i]}")
        done
    done
    return 0
}

select_tweaks() {
    audit_reset

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

    local privacy_s=$misc_e
    source "$MACRIFT_DIR/tweaks/privacy.sh"
    privacy_recommended
    local privacy_e=${#AUDIT_ENTRIES[@]}

    local strict_s=$privacy_e
    privacy_strict
    local strict_e=${#AUDIT_ENTRIES[@]}

    local specs=(
        "Dock:${dock_s}:${dock_e}"
        "Finder:${finder_s}:${finder_e}"
        "Keyboard & Text:${keyboard_s}:${keyboard_e}"
        "Trackpad & Mouse:${input_s}:${input_e}"
        "Screenshots:${screenshots_s}:${screenshots_e}"
        "Misc:${misc_s}:${misc_e}"
        "Privacy"$'\x1f'"Recommended opt-outs — telemetry, ads, diagnostics:${privacy_s}:${privacy_e}"
        "Privacy (Strict)"$'\x1f'"Adds Siri opt-outs + keeps Gatekeeper from auto-re-arming (needs sudo):${strict_s}:${strict_e}"
    )

    # Wizard: walk through all categories, skip/apply/reset per item
    _tweak_wizard "${specs[@]}" || { audit_reset; return; }

    if [[ ${TWEAK_SELECTION[*]+x} && ${#TWEAK_SELECTION[@]} -gt 0 ]] || \
       [[ ${TWEAK_RESETS[*]+x} && ${#TWEAK_RESETS[@]} -gt 0 ]]; then
        clear

        local need_dock=false need_finder=false

        if [[ ${#TWEAK_SELECTION[@]} -gt 0 ]]; then
            AUDIT_ENTRIES=("${TWEAK_SELECTION[@]}")
            apply_audited_defaults
        fi

        if [[ ${#TWEAK_RESETS[@]} -gt 0 ]]; then
            # shellcheck disable=SC2034  # read by apply_reset_defaults (common.sh)
            RESET_ENTRIES=("${TWEAK_RESETS[@]}")
            apply_reset_defaults
        fi

        local domain
        for domain in "${MACRIFT_CHANGED_DOMAINS[@]:+${MACRIFT_CHANGED_DOMAINS[@]}}"; do
            [[ "$domain" == *"dock"* ]]                                       && need_dock=true
            # NSGlobalDomain hosts Finder tweaks too (AppleShowAllExtensions, springing)
            [[ "$domain" == *"finder"* || "$domain" == *"desktopservices"* \
               || "$domain" == "NSGlobalDomain" ]]                            && need_finder=true
        done
        MACRIFT_CHANGED_DOMAINS=()

        TWEAK_SELECTION=(); TWEAK_RESETS=()

        if $need_dock || $need_finder; then
            printf '\n'
            if confirm "Restart affected services?" "y"; then
                $need_dock   && { killall Dock 2>/dev/null || true;   log_ok "Dock restarted"; }
                $need_finder && { killall Finder 2>/dev/null || true; log_ok "Finder restarted"; }
            else
                log_info "Restart skipped — changes apply after logout"
            fi
        fi

        wait_enter
    fi

    audit_reset
}

# The ⌘Space Spotlight shortcut is symbolic hotkey 64; "enabled = 0" once off
_spotlight_hotkey_disabled() {
    defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys 2>/dev/null |
        sed -n '/ 64 =/,/};/p' | grep -q 'enabled = 0'
}

tweaks_menu() {
    crumb_push "System Tweaks"
    while true; do
        clear

        local -a items=(
            "Tweak macOS defaults ›"
            "Hot Corners ↗"
        )
        # Toggle label follows the live state — always visible so the change
        # can be undone from the same place
        local spotlight_off=false
        if _spotlight_hotkey_disabled; then
            spotlight_off=true
            items+=("Enable Spotlight ⌘Space")
        else
            items+=("Disable Spotlight ⌘Space")
        fi
        items+=(
            "---"
            "Dithering ›"
            "Space Switcher ›"
            "FN Lang Switch ›"
        )

        # Plugins targeting menu.parent=tweaks append below the built-ins.
        local _nb; _nb=$(_menu_selectable_count items)
        local -a _pf=()
        _plugin_attach_builtin tweaks items _pf
        items+=("Back")

        local choice
        choice=$(show_menu "System Tweaks" "${items[@]}")

        if (( choice > _nb )); then
            "${_pf[$((choice - _nb - 1))]}" || true
            continue
        fi
        case "$choice" in
            1) select_tweaks ;;
            2) if open "x-apple.systempreferences:com.apple.Desktop-Settings.extension?HotCorners" 2>/dev/null; then
                 log_ok "Opened System Settings → Hot Corners"
               else
                 log_err "Failed to open System Settings"
                 log_hint "open it manually: System Settings → Desktop & Dock → Hot Corners"
               fi
               wait_enter ;;
            3) # Toggle Spotlight ⌘Space directly via prefs — no UI needed
               clear
               if $spotlight_off; then
                 if confirm "Re-enable the Spotlight ⌘Space shortcut?" "y"; then
                   if [[ "$MACRIFT_DRY_RUN" == true ]]; then
                     log_info "Dry run — would restore the default ⌘Space Spotlight shortcut"
                   # Restore the stock definition (⌘Space): the disable write
                   # replaced the whole hotkey dict, so enabled=true alone isn't enough
                   elif defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 \
                        '<dict><key>enabled</key><true/><key>value</key><dict><key>parameters</key><array><integer>65535</integer><integer>49</integer><integer>1048576</integer></array><key>type</key><string>standard</string></dict></dict>' 2>/dev/null; then
                     killall SystemUIServer 2>/dev/null
                     log_ok "⌘Space Spotlight shortcut restored"
                   else
                     log_err "Failed to modify shortcut — try System Settings → Keyboard → Keyboard Shortcuts → Spotlight"
                   fi
                   wait_enter
                 fi
               elif confirm "Disable the Spotlight ⌘Space shortcut?" "n"; then
                 if [[ "$MACRIFT_DRY_RUN" == true ]]; then
                   log_info "Dry run — would disable the ⌘Space Spotlight shortcut"
                 # defaults (not PlistBuddy) so the write goes through cfprefsd
                 elif defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 \
                      '<dict><key>enabled</key><false/></dict>' 2>/dev/null; then
                   killall SystemUIServer 2>/dev/null
                   log_ok "⌘Space Spotlight shortcut disabled — ⌘Space is now free"
                 else
                   log_err "Failed to modify shortcut — try System Settings → Keyboard → Keyboard Shortcuts → Spotlight"
                 fi
                 wait_enter
               fi ;;
            4) source "$MACRIFT_DIR/tweaks/dithering.sh" && dithering_menu ;;
            5) source "$MACRIFT_DIR/tweaks/space_switcher.sh" && space_switcher_menu ;;
            6) source "$MACRIFT_DIR/tweaks/fn_lang_switch.sh" && fn_lang_switch_menu ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}
