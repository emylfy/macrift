#!/usr/bin/env bash
# macrift — TUI framework (menus, boxes, spinners, breadcrumbs)

# Update terminal tab/window title — show path to current menu, not the menu itself
_update_title() {
    local count=${#MACRIFT_CRUMBS[@]}
    if [[ $count -le 1 ]]; then
        printf "\033]0;%s\007" "macrift"
    else
        local parent=("${MACRIFT_CRUMBS[@]:0:count-1}")
        local title
        title=$(IFS=" › "; echo "${parent[*]}")
        printf "\033]0;%s\007" "$title"
    fi
}

MACRIFT_CRUMBS=()

# Sticky menu cursor positions — read/write via shared file because show_menu
# runs in a command-substitution subshell, so in-memory dicts don't survive.
_menu_pos_get() {
    local title="$1"
    [[ -f "$MENU_STATE_FILE" ]] || { echo 0; return; }
    local line
    line=$(grep -F "$(printf '%s\t' "$title")" "$MENU_STATE_FILE" 2>/dev/null | tail -1)
    [[ -z "$line" ]] && { echo 0; return; }
    echo "${line#*$'\t'}"
}
_menu_pos_set() {
    local title="$1" pos="$2"
    mkdir -p "$(dirname "$MENU_STATE_FILE")"
    # Remove any old entry for this title, append new one
    local tmp="${MENU_STATE_FILE}.tmp"
    {
        [[ -f "$MENU_STATE_FILE" ]] && grep -vF "$(printf '%s\t' "$title")" "$MENU_STATE_FILE" 2>/dev/null
        printf '%s\t%s\n' "$title" "$pos"
    } > "$tmp"
    mv -f "$tmp" "$MENU_STATE_FILE"
}

crumb_push() { MACRIFT_CRUMBS+=("$1"); _update_title; }
crumb_pop() {
    local last=$(( ${#MACRIFT_CRUMBS[@]} - 1 ))
    if [[ $last -ge 0 ]]; then
        unset "MACRIFT_CRUMBS[$last]"
    fi
    _update_title
}

spinner() {
    local pid=$1 msg="${2:-}"
    local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local frame_count=${#frames}
    local i=0
    tput civis 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r  %b%s%b  %s' "$CYAN" "${frames:i%frame_count:1}" "$RESET" "$msg" >&2
        sleep 0.08
        i=$((i + 1))
    done
    printf '\r\033[K' >&2
    tput cnorm 2>/dev/null || true
}

run_with_spinner() {
    local msg="$1"
    shift
    local _rws_log
    _rws_log=$(mktemp)
    "$@" &>"$_rws_log" &
    spinner $! "$msg"
    wait $! 2>/dev/null
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        cat "$_rws_log" >&2
    fi
    rm -f "$_rws_log"
    return $rc
}

# Progress bar — inline redraw
# Usage: show_progress 3 10 "Installing packages..."
#        show_progress 10 10 "Done"  (auto-clears on complete)
show_progress() {
    local current="$1" total="$2" msg="${3:-}"
    [[ $total -eq 0 ]] && return
    local pct=$((current * 100 / total))
    local bar_w=20  # bar width in characters
    local filled=$((pct * bar_w / 100))
    local empty=$((bar_w - filled))

    local bar=""
    local i
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    if [[ $current -ge $total ]]; then
        printf '\r  %b%s%b %b%d/%d%b  %s\033[K\n' \
            "$GREEN" "$bar" "$RESET" "$DIM" "$current" "$total" "$RESET" "$msg" >&2
    else
        printf '\r  %b%s%b %b%d/%d%b  %s\033[K' \
            "$CYAN" "$bar" "$RESET" "$DIM" "$current" "$total" "$RESET" "$msg" >&2
    fi
}

# Box drawing helpers
# All use $BP (border paint) and $R (reset) from caller scope

_box_top() {
    local title="$1" inner_w="$2"
    local fill=$((inner_w - ${#title} - 3))
    [[ $fill -lt 1 ]] && fill=1
    printf '  %b╭─ %b%s%b ' "$BP" "${R}${BOLD}${ICE}" "$title" "${R}${BP}" >&2
    printf '─%.0s' $(seq 1 "$fill") >&2
    printf '╮%b\033[K\n' "$R" >&2
}

_box_bottom() {
    local inner_w="$1"
    printf '  %b╰' "$BP" >&2
    printf '─%.0s' $(seq 1 "$inner_w") >&2
    printf '╯%b\033[K\n' "$R" >&2
}

_box_empty() {
    local inner_w="$1"
    printf '  %b│%b%*s%b│%b\033[K\n' "$BP" "$R" "$inner_w" "" "$BP" "$R" >&2
}

_box_scroll_indicator() {
    local inner_w="$1" direction="$2"
    local char="▲"
    if [[ "$direction" == "down" ]]; then char="▼"; fi

    # Center "▲ ···" (5 chars) within inner_w, accounting for _box_row's 2-char left padding
    local label="$char ···"
    local usable=$((inner_w - 2))
    local pad_left=$(( (usable - 5) / 2 ))
    local pad_right=$(( usable - pad_left - 5 ))

    local content
    content=$(printf '%*s%b%s%b%*s' "$pad_left" "" "$DIM" "$label" "$R" "$pad_right" "")
    _box_row "$inner_w" "$content" 0
}

_box_row() {
    local inner_w="$1" content="$2" pad="$3" lead="${4:-  }"
    # lead is the 2-col left gutter; pass " ${BAR}" to draw the cursor bar there.
    printf '  %b│%b%b%s%*s%b│%b\033[K\n' "$BP" "$R" "$lead" "$content" "$pad" "" "$BP" "$R" >&2
}

# Viewport: adjust vp_top to keep cursor visible
# Uses items[], need_scroll, visible_count, vp_top from caller
_adjust_viewport() {
    local cursor="$1" item_count="$2"
    if $need_scroll && [[ $cursor -lt $item_count ]]; then
        if [[ $cursor -lt $vp_top ]]; then
            vp_top=$cursor
            while [[ $vp_top -gt 0 && ( "${items[$((vp_top-1))]}" == "---" || "${items[$((vp_top-1))]}" == "## "* ) ]]; do
                vp_top=$((vp_top - 1))
            done
        fi
        local vp_bottom=$((vp_top + visible_count))
        if [[ $cursor -ge $vp_bottom ]]; then
            vp_top=$((cursor - visible_count + 1))
            [[ $vp_top -lt 0 ]] && vp_top=0
        fi
    fi
}

# Read a single keypress, return: up/down/left/right/enter/space/a or the char
_read_key() {
    local key=""
    IFS= read -rsn1 key < /dev/tty || true
    if [[ "$key" == $'\x1b' ]]; then
        local seq=""
        read -rsn2 -t 1 seq < /dev/tty || true
        case "$seq" in
            '[A') echo "up" ;;
            '[B') echo "down" ;;
            '[C') echo "right" ;;
            '[D') echo "left" ;;
            '')   echo "esc" ;;   # bare ESC — nothing followed within the timeout
            *)    echo "" ;;
        esac
    elif [[ "$key" == '' ]]; then
        echo "enter"
    elif [[ "$key" == ' ' ]]; then
        echo "space"
    else
        echo "$key"
    fi
}

# Begin interactive UI — hide cursor, disable echo
_ui_start() {
    stty -echo 2>/dev/null || true
    printf "\033[?25l" >&2
}

# End interactive UI — show cursor, restore echo
_ui_end() {
    stty echo 2>/dev/null || true
    printf "\033[?25h" >&2
}

# Frame start — synchronized output begin + cursor reposition
_frame_start() {
    local first_draw="$1" total_lines="$2"
    printf "\033[?2026h" >&2
    if [[ "$first_draw" == true ]]; then
        : # first frame, no reposition
    else
        printf "\033[%dA\r" "$total_lines" >&2
    fi
    printf "\033[K\n" >&2
}

_frame_end() {
    printf "\033[?2026l" >&2
}

# Calculate scroll parameters
# Sets: need_scroll, visible_count, via output
_calc_scroll() {
    local item_count="$1" chrome="$2"
    local term_h
    term_h=$(tput lines 2>/dev/null || echo 24)
    if [[ $item_count -gt $((term_h - chrome)) ]]; then
        local vc=$((term_h - chrome - 3))
        [[ $vc -lt 3 ]] && vc=3
        echo "true $vc"
    else
        echo "false $item_count"
    fi
}

# Menu

show_menu() {
    local title="$1"
    shift
    local items=("$@")
    # Optional dim subtitle for live state: caller passes "Title"$'\x1f'"Subtitle"
    # (keeps the title bar short instead of cramming state into it).
    local subtitle=""
    if [[ "$title" == *$'\x1f'* ]]; then
        subtitle="${title#*$'\x1f'}"
        title="${title%%$'\x1f'*}"
    fi
    local count=${#items[@]}
    local last_idx=$((count - 1))

    # A trailing "Back" item is implicit now — esc/← handles it (footer says so),
    # so don't render it as a selectable row. Other trailing items (e.g. "Exit") stay.
    local hide_back=false
    [[ "${items[$last_idx]}" == "Back" ]] && hide_back=true

    # Build selectable items map
    local sel_nums=() sel_to_item=()
    local i num=0
    for ((i=0; i<last_idx; i++)); do
        [[ "${items[$i]}" == "---" ]] && continue
        [[ "${items[$i]}" == "## "* ]] && continue
        num=$((num + 1))
        sel_nums+=("$num")
        sel_to_item+=("$i")
    done
    if ! $hide_back; then
        sel_nums+=(0)
        sel_to_item+=("$last_idx")
    fi
    local sel_total=${#sel_nums[@]}

    # Box dimensions — widest label wins. Section headers (`## `) are flush with
    # their items, so only the marker is stripped; no extra indent column.
    local max_len=0
    for ((i=0; i<count; i++)); do
        [[ "${items[$i]}" == "---" ]] && continue
        local _wtext="${items[$i]#\#\# }"   # strip the heading marker for width
        _wtext="${_wtext%$'\x1f'}"          # strip the dim marker for width
        [[ ${#_wtext} -gt $max_len ]] && max_len=${#_wtext}
    done
    [[ -n "$subtitle" && ${#subtitle} -gt $max_len ]] && max_len=${#subtitle}
    local BP="${BOLD}${GRAY}" R="${RESET}"
    local BAR="${BOLD}${CYAN}▌${R}"

    # Geometry: 2-col left gutter (holds the cursor bar) + 2-col right margin.
    local inner_w=$((2 + max_len + 2))
    local title_min=$((${#title} + 5))
    [[ $title_min -gt $inner_w ]] && inner_w=$title_min
    # Clamp to terminal width so the border never wraps on narrow windows
    local term_w; term_w=$(tput cols 2>/dev/null || echo 80)
    local max_inner=$((term_w - 4)); [[ $max_inner -lt 16 ]] && max_inner=16
    [[ $inner_w -gt $max_inner ]] && inner_w=$max_inner
    local max_text=$((inner_w - 4))

    # Truncate a label to the available width, adding an ellipsis
    _fit() { local t="$1"; [[ ${#t} -gt $max_text ]] && t="${t:0:max_text-1}…"; printf '%s' "$t"; }

    # Render one selectable row: text, is_selected, is_back. The cursor is a
    # left accent bar (▌) in the gutter, so selection reads without relying on color.
    _menu_row() {
        local is_sel="$2" is_back="${3:-false}" indent="${4:-}" raw="$1" glyph="" is_dim=false
        # A trailing US byte (\x1f) marks a dim row (e.g. "not installed") that is
        # still selectable; strip it before the affordance split below.
        [[ "$raw" == *$'\x1f' ]] && { is_dim=true; raw="${raw%$'\x1f'}"; }
        # A trailing " ›" (opens a submenu) or " ↗" (opens System Settings) is
        # split off and right-aligned to the border as a dim affordance.
        case "$raw" in
            *' ›') glyph="›"; raw="${raw% ›}" ;;
            *' ↗') glyph="↗"; raw="${raw% ↗}" ;;
        esac
        local text; text=$(_fit "${indent}${raw}")
        local lead="  "; $is_sel && lead=" $BAR"
        local body
        if $is_sel;               then body=$(printf '%b%s%b' "${BOLD}${ICE}" "$text" "$R")
        elif $is_back || $is_dim; then body=$(printf '%b%s%b' "$DIM" "$text" "$R")
        else body="$text"; fi
        if [[ -n "$glyph" ]]; then
            # …text…<gap>glyph<1-col margin>│  — right-aligned with a small margin
            local gap=$((inner_w - 4 - ${#text})); [[ $gap -lt 1 ]] && gap=1
            body="${body}$(printf '%*s' "$gap" '')$(printf '%b%s%b' "$DIM" "$glyph" "$R")"
            _box_row "$inner_w" "$body" 1 "$lead"
        else
            local pad=$((inner_w - 2 - ${#text})); [[ $pad -lt 0 ]] && pad=0
            _box_row "$inner_w" "$body" "$pad" "$lead"
        fi
    }

    # Scrolling
    local chrome=8
    local scroll_info
    scroll_info=$(_calc_scroll "$last_idx" "$chrome")
    local need_scroll=${scroll_info%% *}
    local visible_count=${scroll_info##* }
    local vp_top=0

    local total_lines=$((visible_count + 8))
    $need_scroll && total_lines=$((total_lines + 2))
    [[ -n "$subtitle" ]] && total_lines=$((total_lines + 1))

    # Restore cursor from sticky position if we've been here before
    local sel first_draw=true
    sel=$(_menu_pos_get "$title")
    # Clamp in case items shrank since last visit or value is garbage
    [[ "$sel" =~ ^[0-9]+$ ]] || sel=0
    [[ $sel -ge $((sel_total - 1)) || $sel -lt 0 ]] && sel=0
    _ui_start

    while true; do
        # Viewport
        if $need_scroll && [[ $sel -lt $((sel_total - 1)) ]]; then
            local cur_item=${sel_to_item[$sel]}
            _adjust_viewport "$cur_item" "$last_idx"
        fi

        _frame_start "$first_draw" "$total_lines"
        first_draw=false

        _box_top "$title" "$inner_w"
        _box_empty "$inner_w"

        # Optional dim subtitle (live state) right under the title
        if [[ -n "$subtitle" ]]; then
            local _st; _st=$(_fit "$subtitle")
            local _spad=$((inner_w - 2 - ${#_st})); [[ $_spad -lt 0 ]] && _spad=0
            _box_row "$inner_w" "$(printf '%b%s%b' "$DIM" "$_st" "$R")" "$_spad"
        fi

        # Scroll-up
        if $need_scroll; then
            if [[ $vp_top -gt 0 ]]; then
                _box_scroll_indicator "$inner_w" "up"
            else
                _box_empty "$inner_w"
            fi
        fi

        # Items
        local sel_idx=0 rendered=0
        for ((i=0; i<last_idx; i++)); do
            if $need_scroll; then
                if [[ $i -lt $vp_top || $rendered -ge $visible_count ]]; then
                    if [[ "${items[$i]}" != "---" && "${items[$i]}" != "## "* ]]; then
                        sel_idx=$((sel_idx + 1))
                    fi
                    continue
                fi
            fi

            if [[ "${items[$i]}" == "---" ]]; then
                _box_empty "$inner_w"
                rendered=$((rendered + 1))
                continue
            fi

            if [[ "${items[$i]}" == "## "* ]]; then
                # Section heading: dim, sentence-case as written (not uppercased),
                # flush with its items (no extra indent).
                local htext="${items[$i]#\#\# }"; htext=$(_fit "$htext")
                local hpad=$((inner_w - 2 - ${#htext})); [[ $hpad -lt 0 ]] && hpad=0
                _box_row "$inner_w" "$(printf '%b%s%b' "$DIM" "$htext" "$R")" "$hpad"
                rendered=$((rendered + 1))
                continue
            fi

            local is_sel=false; [[ $sel_idx -eq $sel ]] && is_sel=true
            _menu_row "${items[$i]}" "$is_sel" false
            sel_idx=$((sel_idx + 1))
            rendered=$((rendered + 1))
        done

        # Scroll-down
        if $need_scroll; then
            if [[ $((vp_top + visible_count)) -lt $last_idx ]]; then
                _box_scroll_indicator "$inner_w" "down"
            else
                _box_empty "$inner_w"
            fi
        fi

        # Trailing item: an implicit "Back" is hidden (use ← instead); a real
        # item like "Exit" is still shown and selectable.
        if $hide_back; then
            _box_empty "$inner_w"
        else
            _box_empty "$inner_w"
            local is_sel=false; [[ $sel -eq $((sel_total - 1)) ]] && is_sel=true
            _menu_row "${items[$last_idx]}" "$is_sel" true
            _box_empty "$inner_w"
        fi
        _box_bottom "$inner_w"

        # Footer — key contract + active flags. Back is ← (esc is unreliable in
        # many terminals — a lone ESC can't be told apart from an arrow sequence).
        # Version only at the root level, not on every submenu.
        local hint="↑↓ move · →/↵ select"
        [[ ${#MACRIFT_CRUMBS[@]} -gt 1 ]] && hint+=" · ← back"
        [[ ${#MACRIFT_CRUMBS[@]} -le 1 && "$MACRIFT_VERSION" != "$MACRIFT_VERSION_SHORT" ]] && hint+=" · v$MACRIFT_VERSION"
        local flags=""
        [[ "$MACRIFT_DRY_RUN" == true ]] && flags+=" [dry-run]"
        [[ "$MACRIFT_NO_CONFIRM" == true ]] && flags+=" [auto]"
        [[ -n "$MACRIFT_LOG" ]] && flags+=" [log]"
        if [[ -n "$flags" ]]; then
            printf '  %b%s%b %b%s%b\033[K\n' "$DIM" "$hint" "$R" "$YELLOW" "$flags" "$R" >&2
        else
            printf '  %b%s%b\033[K\n' "$DIM" "$hint" "$R" >&2
        fi
        _frame_end

        # Input
        local key
        key=$(_read_key)
        # Sticky cursor: save sel when leaving, but skip if cursor was on the Back item
        # (otherwise cursor would re-stick on Back and create an immediate-exit loop next visit)
        local on_back=false
        if ! $hide_back && [[ $sel -ge $((sel_total - 1)) ]]; then on_back=true; fi
        case "$key" in
            up)    [[ $sel -gt 0 ]] && sel=$((sel - 1)) ;;
            down)  [[ $sel -lt $((sel_total - 1)) ]] && sel=$((sel + 1)) ;;
            right|enter)
                   $on_back || _menu_pos_set "$title" "$sel"
                   _ui_end; echo "${sel_nums[$sel]}"; return ;;
            left)
                   if [[ ${#MACRIFT_CRUMBS[@]} -gt 1 ]]; then
                       $on_back || _menu_pos_set "$title" "$sel"
                       _ui_end; echo "0"; return
                   fi ;;
        esac
    done
}

# Info box (non-interactive)

show_info_box() {
    local title="$1"
    shift
    local lines=("$@")
    local count=${#lines[@]}

    local max_len=0 i
    for ((i=0; i<count; i++)); do
        [[ ${#lines[$i]} -gt $max_len ]] && max_len=${#lines[$i]}
    done

    local inner_w=$((max_len + 4))
    local title_min=$((${#title} + 5))
    [[ $title_min -gt $inner_w ]] && inner_w=$title_min

    local BP="${BOLD}${GRAY}" R="${RESET}"

    printf "\n" >&2
    _box_top "$title" "$inner_w"
    _box_empty "$inner_w"

    for ((i=0; i<count; i++)); do
        local pad=$((inner_w - ${#lines[$i]} - 2))
        _box_row "$inner_w" "${lines[$i]}" "$pad"
    done

    _box_empty "$inner_w"
    _box_bottom "$inner_w"
}

# Multiselect

show_multiselect() {
    local title="$1"
    shift
    local items=("$@")
    local count=${#items[@]}
    local total=$((count + 1))
    local cursor=0
    declare -a selected
    local i
    # MULTISELECT_OPTIONAL — caller sets to space-padded indices (" 3 5 7 ")
    # that should be unchecked by default. Reset after show_multiselect returns.
    local opt_set=" ${MULTISELECT_OPTIONAL:-} "
    for ((i=0; i<count; i++)); do
        if [[ "${items[$i]}" == "---" || "${items[$i]}" == "## "* ]]; then
            selected[i]="-"
        elif [[ "$opt_set" == *" $i "* ]]; then
            selected[i]="0"
        else
            selected[i]="1"
        fi
    done
    MULTISELECT_OPTIONAL=""
    while [[ $cursor -lt $count && ( "${items[$cursor]}" == "---" || "${items[$cursor]}" == "## "* ) ]]; do
        cursor=$((cursor + 1))
    done

    # View mode: when MULTISELECT_INSTALLED is set, right arrow toggles a
    # read-only list of already-installed packages in the same window
    local view_raw="${MULTISELECT_INSTALLED:-}"
    MULTISELECT_INSTALLED=""
    local view_items=()
    if [[ -n "$view_raw" ]]; then
        while IFS= read -r vl; do
            [[ -z "$vl" ]] && continue
            view_items+=("$vl")
        done <<< "$view_raw"
    fi
    local view_count=${#view_items[@]}
    local view_available=false
    [[ $view_count -gt 0 ]] && view_available=true
    local view_mode=false
    local view_cursor=0
    local view_vp_top=0

    # Box width — include view items so toggling doesn't resize the box
    local max_len=0
    for ((i=0; i<count; i++)); do
        [[ "${items[$i]}" == "---" ]] && continue
        local _ilen=${#items[$i]}
        [[ "${items[$i]}" == "## "* ]] && _ilen=$((_ilen - 3))   # strip "## " prefix
        [[ $_ilen -gt $max_len ]] && max_len=$_ilen
    done
    for ((i=0; i<view_count; i++)); do
        [[ ${#view_items[$i]} -gt $max_len ]] && max_len=${#view_items[$i]}
    done
    # Geometry: 2-col gutter (cursor bar) + "[*] " checkbox (4) + label + 2 margin
    local inner_w=$((max_len + 8))
    [[ 12 -gt $inner_w ]] && inner_w=12
    local title_min=$((${#title} + 5))
    [[ $title_min -gt $inner_w ]] && inner_w=$title_min
    # Clamp to terminal width so the border never wraps
    local term_w; term_w=$(tput cols 2>/dev/null || echo 80)
    local max_inner=$((term_w - 4)); [[ $max_inner -lt 16 ]] && max_inner=16
    [[ $inner_w -gt $max_inner ]] && inner_w=$max_inner

    local BP="${BOLD}${GRAY}" R="${RESET}"
    local BAR="${BOLD}${CYAN}▌${R}"

    # Scrolling — chrome=9 accounts for box (top/bottom + 3 empties + back row) + 2-line hint
    local scroll_info
    scroll_info=$(_calc_scroll "$count" 9)
    local need_scroll=${scroll_info%% *}
    local visible_count=${scroll_info##* }
    local vp_top=0

    # Reserve indicator slot if EITHER picker or view needs to scroll, so the
    # box keeps the same height when toggling modes
    local any_scroll=$need_scroll
    if $view_available && [[ $view_count -gt $visible_count ]]; then
        any_scroll=true
    fi

    # +9 (not +8) because the hint is now two lines instead of one
    local redraw_lines=$((visible_count + 9))
    $any_scroll && redraw_lines=$((redraw_lines + 2))

    local first_draw=true
    _ui_start

    while true; do
        if $view_mode; then
            # ── View mode: read-only list of already-installed packages ──
            # Reuse picker's visible_count budget so total height stays constant
            local v_show=$view_count
            local v_scroll=false
            if [[ $view_count -gt $visible_count ]]; then
                v_show=$visible_count
                v_scroll=true
            fi
            if $v_scroll; then
                if [[ $view_cursor -lt $view_vp_top ]]; then view_vp_top=$view_cursor; fi
                local vbot=$((view_vp_top + v_show))
                if [[ $view_cursor -ge $vbot ]]; then
                    view_vp_top=$((view_cursor - v_show + 1))
                    [[ $view_vp_top -lt 0 ]] && view_vp_top=0
                fi
            fi

            _frame_start "$first_draw" "$redraw_lines"
            first_draw=false

            _box_top "$title" "$inner_w"
            _box_empty "$inner_w"

            # Reserve indicator slot if either mode needs scrolling
            if $any_scroll; then
                if $v_scroll && [[ $view_vp_top -gt 0 ]]; then
                    _box_scroll_indicator "$inner_w" "up"
                else
                    _box_empty "$inner_w"
                fi
            fi

            local rendered=0
            for ((i=0; i<view_count; i++)); do
                if $v_scroll && [[ $i -lt $view_vp_top || $rendered -ge $v_show ]]; then
                    continue
                fi
                local pad=$((inner_w - 2 - ${#view_items[$i]})); [[ $pad -lt 0 ]] && pad=0
                local vlead="  "; [[ $i -eq $view_cursor ]] && vlead=" $BAR"
                local content; content=$(printf '%b%s%b' "$DIM" "${view_items[$i]}" "$R")
                _box_row "$inner_w" "$content" "$pad" "$vlead"
                rendered=$((rendered + 1))
            done
            # Pad to picker's visible_count
            while [[ $rendered -lt $visible_count ]]; do
                _box_empty "$inner_w"
                rendered=$((rendered + 1))
            done

            if $any_scroll; then
                if $v_scroll && [[ $((view_vp_top + v_show)) -lt $view_count ]]; then
                    _box_scroll_indicator "$inner_w" "down"
                else
                    _box_empty "$inner_w"
                fi
            fi

            # Mirror picker's bottom chrome height (3 rows) — keep them empty since
            # navigation is conveyed by the hint line below
            _box_empty "$inner_w"
            _box_empty "$inner_w"
            _box_empty "$inner_w"
            _box_bottom "$inner_w"

            printf '  %b%s%b\033[K\n' "$DIM" "↑↓ scroll  ← back" "$R" >&2
            printf '\033[K\n' >&2
            _frame_end

            local key
            key=$(_read_key)
            case "$key" in
                up)   [[ $view_cursor -gt 0 ]] && view_cursor=$((view_cursor - 1)) ;;
                down) [[ $view_cursor -lt $((view_count - 1)) ]] && view_cursor=$((view_cursor + 1)) ;;
                left|right|enter) view_mode=false ;;   # installed-view is a drill-in; any of these returns to the picker
            esac
            continue
        fi

        _adjust_viewport "$cursor" "$count"

        _frame_start "$first_draw" "$redraw_lines"
        first_draw=false

        _box_top "$title" "$inner_w"
        _box_empty "$inner_w"

        # Scroll-up
        if $any_scroll; then
            if $need_scroll && [[ $vp_top -gt 0 ]]; then
                _box_scroll_indicator "$inner_w" "up"
            else
                _box_empty "$inner_w"
            fi
        fi

        # Items
        local rendered=0
        for ((i=0; i<count; i++)); do
            if $need_scroll && [[ $i -lt $vp_top || $rendered -ge $visible_count ]]; then
                continue
            fi
            if [[ "${items[$i]}" == "---" ]]; then
                _box_empty "$inner_w"
                rendered=$((rendered + 1))
                continue
            fi

            if [[ "${items[$i]}" == "## "* ]]; then
                # Section heading: dim, flush with its items (mirrors show_menu)
                local htext="${items[$i]#\#\# }"
                local hmax=$((inner_w - 4)); [[ ${#htext} -gt $hmax ]] && htext="${htext:0:hmax-1}…"
                local hpad=$((inner_w - 2 - ${#htext})); [[ $hpad -lt 0 ]] && hpad=0
                _box_row "$inner_w" "$(printf '%b%s%b' "$DIM" "$htext" "$R")" "$hpad"
                rendered=$((rendered + 1))
                continue
            fi

            local pad=$((inner_w - 6 - ${#items[$i]})); [[ $pad -lt 0 ]] && pad=0
            local lead="  "; [[ $i -eq $cursor ]] && lead=" $BAR"
            local box
            if [[ "${selected[i]}" == "1" ]]; then box=$(printf '%b[*]%b' "$GREEN" "$R")
            else box=$(printf '%b[ ]%b' "$DIM" "$R"); fi
            _box_row "$inner_w" "$(printf '%s %s' "$box" "${items[$i]}")" "$pad" "$lead"
            rendered=$((rendered + 1))
        done

        # Scroll-down
        if $any_scroll; then
            if $need_scroll && [[ $((vp_top + visible_count)) -lt $count ]]; then
                _box_scroll_indicator "$inner_w" "down"
            else
                _box_empty "$inner_w"
            fi
        fi

        # Back
        _box_empty "$inner_w"
        local blead="  " bbody
        if [[ $cursor -eq $count ]]; then
            blead=" $BAR"; bbody=$(printf '%b%bBack%b' "$BOLD" "$ICE" "$R")
        else
            bbody=$(printf '%bBack%b' "$DIM" "$R")
        fi
        _box_row "$inner_w" "$bbody" "$((inner_w - 6))" "$blead"
        _box_empty "$inner_w"
        _box_bottom "$inner_w"

        if [[ -n "${MULTISELECT_HINT:-}" ]]; then
            # Backwards-compat: caller-supplied hint stays single-line, blank pad
            printf '  %b%s%b\033[K\n' "$DIM" "$MULTISELECT_HINT" "$R" >&2
            printf '\033[K\n' >&2
        else
            printf '  %b↑↓ move  space toggle  a all%b\033[K\n' "$DIM" "$R" >&2
            local hint2="← back  enter confirm"
            $view_available && hint2+="  → installed"
            printf '  %b%s%b\033[K\n' "$DIM" "$hint2" "$R" >&2
        fi
        _frame_end

        # Input
        local key
        key=$(_read_key)
        case "$key" in
            up)
                if [[ $cursor -gt 0 ]]; then
                    cursor=$((cursor - 1))
                    while [[ $cursor -gt 0 && ( "${items[$cursor]}" == "---" || "${items[$cursor]}" == "## "* ) ]]; do
                        cursor=$((cursor - 1))
                    done
                    # bounce off a leading header/separator onto the first selectable
                    while [[ $cursor -lt $count && ( "${items[$cursor]}" == "---" || "${items[$cursor]}" == "## "* ) ]]; do
                        cursor=$((cursor + 1))
                    done
                fi ;;
            down)
                if [[ $cursor -lt $((total - 1)) ]]; then
                    cursor=$((cursor + 1))
                    while [[ $cursor -lt $count && ( "${items[$cursor]}" == "---" || "${items[$cursor]}" == "## "* ) ]]; do
                        cursor=$((cursor + 1))
                    done
                fi ;;
            right)
                # Right activates Back, switches to installed-view if available,
                # otherwise no-op (so an accidental press doesn't kick off install)
                if [[ $cursor -eq $count ]]; then _ui_end; return 0; fi
                if $view_available; then view_mode=true; view_cursor=0; fi
                ;;
            left) _ui_end; return 0 ;;
            space)
                if [[ $cursor -lt $count ]]; then
                    if [[ "${selected[cursor]}" == "1" ]]; then selected[cursor]="0"; else selected[cursor]="1"; fi
                fi ;;
            a|A)
                local all_on=true
                for ((i=0; i<count; i++)); do
                    [[ "${items[$i]}" == "---" || "${items[$i]}" == "## "* ]] && continue
                    [[ "${selected[$i]}" == "0" ]] && { all_on=false; break; }
                done
                local val="1"; $all_on && val="0"
                for ((i=0; i<count; i++)); do
                    [[ "${items[$i]}" == "---" || "${items[$i]}" == "## "* ]] && continue
                    selected[i]="$val"
                done ;;
            enter)
                if [[ $cursor -eq $count ]]; then _ui_end; return 0; fi
                break ;;
        esac
    done

    _ui_end

    for ((i=0; i<count; i++)); do
        [[ "${items[$i]}" == "---" || "${items[$i]}" == "## "* ]] && continue
        if [[ "${selected[i]}" == "1" ]]; then echo "${items[$i]}"; fi
    done
}
