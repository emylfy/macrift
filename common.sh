#!/usr/bin/env bash
# macrift — shared utilities

set -euo pipefail

# CPU architecture — used to detect Apple Silicon vs Intel for brew paths
ARCH=$(uname -m)

# Global flags — set by macrift.sh before sourcing, defaults here for direct sourcing
MACRIFT_DRY_RUN="${MACRIFT_DRY_RUN:-false}"
MACRIFT_NO_CONFIRM="${MACRIFT_NO_CONFIRM:-false}"
MACRIFT_LOG="${MACRIFT_LOG:-}"

# Shared state file for menu cursor positions (per macrift PID).
# Needed because show_menu runs in a $() subshell — in-memory var won't persist.
MENU_STATE_FILE="${TMPDIR:-/tmp}/macrift-menu.$$"

# Restore cursor on exit, clean up state file
_macrift_cleanup() {
    printf "\033[?25h" 2>/dev/null
    rm -f "$MENU_STATE_FILE"
}
trap _macrift_cleanup EXIT
trap 'exit 130' INT TERM

# Strip ANSI escape codes and append to log file
_log_file() {
    [[ -z "$MACRIFT_LOG" ]] && return
    printf "%s  %s\n" "$(date '+%H:%M:%S')" "$1" >> "$MACRIFT_LOG"
}

# ANSI colors — adjusted for dark/light theme below
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'

_detect_theme() {
    # 1. Explicit override
    if [[ "${MACRIFT_THEME:-}" == "light" ]]; then echo "light"; return; fi
    if [[ "${MACRIFT_THEME:-}" == "dark" ]]; then echo "dark"; return; fi

    # 2. Query terminal background via OSC 11 (iTerm2, Ghostty, Kitty, WezTerm)
    if [[ -t 2 ]] && [[ -r /dev/tty ]]; then
        local old_stty response="" _dd_pid _timer_pid
        local _dd_tmp
        _dd_tmp=$(mktemp)
        old_stty=$(stty -g </dev/tty 2>/dev/null) || true
        stty raw -echo min 0 time 2 </dev/tty 2>/dev/null
        printf '\033]11;?\a' > /dev/tty 2>/dev/null
        # Read with kill-timer to prevent hang in non-standard terminals
        dd bs=1 count=30 </dev/tty >"$_dd_tmp" 2>/dev/null &
        _dd_pid=$!
        (sleep 1 && kill "$_dd_pid" 2>/dev/null) &
        _timer_pid=$!
        wait "$_dd_pid" 2>/dev/null
        kill "$_timer_pid" 2>/dev/null; wait "$_timer_pid" 2>/dev/null
        response=$(cat "$_dd_tmp")
        rm -f "$_dd_tmp"
        # Drain any leftover bytes from terminal response
        dd bs=1 count=64 </dev/tty >/dev/null 2>&1 &
        _dd_pid=$!
        (sleep 1 && kill "$_dd_pid" 2>/dev/null) &
        _timer_pid=$!
        wait "$_dd_pid" 2>/dev/null
        kill "$_timer_pid" 2>/dev/null; wait "$_timer_pid" 2>/dev/null
        stty "$old_stty" </dev/tty 2>/dev/null
        if [[ "$response" =~ rgb:([0-9a-fA-F]+)/([0-9a-fA-F]+)/([0-9a-fA-F]+) ]]; then
            local r=$((16#${BASH_REMATCH[1]:0:2}))
            local g=$((16#${BASH_REMATCH[2]:0:2}))
            local b=$((16#${BASH_REMATCH[3]:0:2}))
            # Perceived brightness (ITU-R BT.601 luma coefficients)
            local lum=$(( (r * 299 + g * 587 + b * 114) / 1000 ))
            if [[ $lum -gt 128 ]]; then echo "light"; else echo "dark"; fi
            return
        fi
    fi

    # 3. Fall back to system theme
    if defaults read -g AppleInterfaceStyle 2>/dev/null | grep -q Dark; then
        echo "dark"
    else
        echo "light"
    fi
}

if [[ "$(_detect_theme)" == "dark" ]]; then
    GRAY='\033[38;5;240m'
    CYAN='\033[38;5;39m'
    ICE='\033[38;5;195m'
else
    GRAY='\033[38;5;245m'
    CYAN='\033[38;5;25m'
    ICE='\033[38;5;24m'
fi

_friendly_val() {
    case "$1" in
        SCcf)                echo "current folder" ;;
        icnv)                echo "icons" ;;
        Nlsv)                echo "list" ;;
        clmv)                echo "column" ;;
        glyv)                echo "gallery" ;;
        PfHm)                echo "home" ;;
        none)                echo "off" ;;
        ZeroDiagnosticData)  echo "off" ;;
        file://*) echo "$HOME/" ;;
        default) echo "not set" ;;
        *)       echo "$1" ;;
    esac
}

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


log_info()  { printf '  %b›%b  %s\n' "${CYAN}" "${RESET}" "$1"; _log_file "[info] $1"; }
log_ok()    { printf '  %b✓%b  %s\n' "${GREEN}" "${RESET}" "$1"; _log_file "[  ok] $1"; }
log_err()   { printf '  %b✗%b  %s\n' "${RED}" "${RESET}" "$1"; _log_file "[ err] $1"; }
log_warn()  { printf '  %b!%b  %s\n' "${YELLOW}" "${RESET}" "$1"; _log_file "[warn] $1"; }
log_skip()  { printf '  %b-%b  %s\n' "${DIM}" "${RESET}" "$1"; _log_file "[skip] $1"; }

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
    local inner_w="$1" content="$2" pad="$3"
    printf '  %b│%b  %s%*s%b│%b\033[K\n' "$BP" "$R" "$content" "$pad" "" "$BP" "$R" >&2
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
    local count=${#items[@]}
    local last_idx=$((count - 1))

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
    sel_nums+=(0)
    sel_to_item+=("$last_idx")
    local sel_total=${#sel_nums[@]}

    # Box dimensions
    local max_len=0
    for ((i=0; i<count; i++)); do
        [[ "${items[$i]}" == "---" ]] && continue
        local _wtext="${items[$i]}"
        [[ "$_wtext" == "## "* ]] && _wtext="${_wtext#\#\# }"
        [[ ${#_wtext} -gt $max_len ]] && max_len=${#_wtext}
    done
    local no_nums="${MENU_NO_NUMBERS:-false}"
    local num_w=${#num}; local num_pad=3
    if [[ "$no_nums" == true ]]; then num_w=0; num_pad=2; fi
    local inner_w=$((2 + num_w + num_pad + max_len + 2))
    local title_min=$((${#title} + 5))
    [[ $title_min -gt $inner_w ]] && inner_w=$title_min

    local BP="${BOLD}${GRAY}" R="${RESET}"

    # Build content for a menu row: text, number, is_selected(bool)
    _menu_content() {
        local text="$1" num="$2" is_sel="$3"
        if [[ "$no_nums" == true ]]; then
            if $is_sel; then printf '%b› %s%b' "${BOLD}${ICE}" "$text" "$R"
            else printf '%b›%b %s' "$DIM" "$R" "$text"; fi
        else
            if $is_sel; then printf '%b%*d › %s%b' "${BOLD}${ICE}" "$num_w" "$num" "$text" "$R"
            elif [[ "$num" -eq 0 ]]; then printf '%b%*d › %s%b' "$DIM" "$num_w" "$num" "$text" "$R"
            else printf '%b%*d%b %b›%b %s' "$CYAN" "$num_w" "$num" "$R" "$DIM" "$R" "$text"; fi
        fi
    }

    # Scrolling
    local chrome=8; [[ "$no_nums" == true ]] && chrome=7
    local scroll_info
    scroll_info=$(_calc_scroll "$last_idx" "$chrome")
    local need_scroll=${scroll_info%% *}
    local visible_count=${scroll_info##* }
    local vp_top=0

    local total_lines=$((visible_count + 8))
    [[ "$no_nums" == true ]] && total_lines=$((total_lines - 1))
    $need_scroll && total_lines=$((total_lines + 2))

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

        # Scroll-up
        if $need_scroll; then
            if [[ $vp_top -gt 0 ]]; then
                _box_scroll_indicator "$inner_w" "up"
            else
                _box_empty "$inner_w"
            fi
        fi

        # Items
        local cur_num=0 sel_idx=0 rendered=0
        for ((i=0; i<last_idx; i++)); do
            if [[ "${items[$i]}" != "---" && "${items[$i]}" != "## "* ]]; then
                cur_num=$((cur_num + 1))
            fi

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
                local htext="${items[$i]#\#\# }"
                local hindent=$((num_w + num_pad))
                local hvis=$((2 + hindent + ${#htext}))
                local hpad=$((inner_w - hvis))
                local hcontent
                hcontent=$(printf '%*s%b%s%b' "$hindent" "" "$DIM" "$htext" "$R")
                _box_row "$inner_w" "$hcontent" "$hpad"
                rendered=$((rendered + 1))
                continue
            fi

            local vis=$((2 + num_w + num_pad + ${#items[$i]}))
            local pad=$((inner_w - vis))
            local is_sel=false; [[ $sel_idx -eq $sel ]] && is_sel=true
            _box_row "$inner_w" "$(_menu_content "${items[$i]}" "$cur_num" "$is_sel")" "$pad"
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

        # Back item
        [[ "$no_nums" != true ]] && _box_empty "$inner_w"
        local vis=$((2 + num_w + num_pad + ${#items[$last_idx]}))
        local pad=$((inner_w - vis))
        local is_sel=false; [[ $sel -eq $((sel_total - 1)) ]] && is_sel=true
        _box_row "$inner_w" "$(_menu_content "${items[$last_idx]}" 0 "$is_sel")" "$pad"

        _box_empty "$inner_w"
        _box_bottom "$inner_w"

        # Footer
        local hint="↑↓ navigate  enter/→ select"
        [[ ${#MACRIFT_CRUMBS[@]} -gt 1 ]] && hint+="  ← back"
        hint+="  ·  v$MACRIFT_VERSION"
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
        [[ $sel -ge $((sel_total - 1)) ]] && on_back=true
        case "$key" in
            up)    [[ $sel -gt 0 ]] && sel=$((sel - 1)) ;;
            down)  [[ $sel -lt $((sel_total - 1)) ]] && sel=$((sel + 1)) ;;
            right) $on_back || _menu_pos_set "$title" "$sel"
                   _ui_end; echo "${sel_nums[$sel]}"; return ;;
            left)
                if [[ ${#MACRIFT_CRUMBS[@]} -gt 1 ]]; then
                    $on_back || _menu_pos_set "$title" "$sel"
                    _ui_end; echo "0"; return
                fi ;;
            enter) $on_back || _menu_pos_set "$title" "$sel"
                   _ui_end; echo "${sel_nums[$sel]}"; return ;;
            [0-9])
                if [[ "$no_nums" != true ]]; then
                    printf "%s\n" "$key" >&2
                    _ui_end; echo "$key"; return
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
        if [[ "${items[$i]}" == "---" ]]; then
            selected[i]="-"
        elif [[ "$opt_set" == *" $i "* ]]; then
            selected[i]="0"
        else
            selected[i]="1"
        fi
    done
    MULTISELECT_OPTIONAL=""
    while [[ $cursor -lt $count && "${items[$cursor]}" == "---" ]]; do
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
        [[ ${#items[$i]} -gt $max_len ]] && max_len=${#items[$i]}
    done
    for ((i=0; i<view_count; i++)); do
        [[ ${#view_items[$i]} -gt $max_len ]] && max_len=${#view_items[$i]}
    done
    local inner_w=$((8 + max_len + 2))
    [[ 12 -gt $inner_w ]] && inner_w=12
    local title_min=$((${#title} + 5))
    [[ $title_min -gt $inner_w ]] && inner_w=$title_min

    local BP="${BOLD}${GRAY}" R="${RESET}"

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
                # Visible prefix is 3 chars ("›  " or "   "), so pad = inner_w - 2 - 3 - len
                local pad=$((inner_w - 5 - ${#view_items[$i]}))
                local content
                if [[ $i -eq $view_cursor ]]; then
                    content=$(printf '%b›%b  %b%s%b' "$CYAN" "$R" "$DIM" "${view_items[$i]}" "$R")
                else
                    content=$(printf '   %b%s%b' "$DIM" "${view_items[$i]}" "$R")
                fi
                _box_row "$inner_w" "$content" "$pad"
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

            printf '  %b%s%b\033[K\n' "$DIM" "↑↓ scroll  ← exit  → picker" "$R" >&2
            printf '\033[K\n' >&2
            _frame_end

            local key
            key=$(_read_key)
            case "$key" in
                up)   [[ $view_cursor -gt 0 ]] && view_cursor=$((view_cursor - 1)) ;;
                down) [[ $view_cursor -lt $((view_count - 1)) ]] && view_cursor=$((view_cursor + 1)) ;;
                right|enter) view_mode=false ;;
                left) _ui_end; return 0 ;;
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

            local pad=$((inner_w - 8 - ${#items[$i]}))
            local content
            if [[ $i -eq $cursor ]]; then
                if [[ "${selected[i]}" == "1" ]]; then
                    content=$(printf '%b›%b %b[*]%b %s' "$CYAN" "$R" "$GREEN" "$R" "${items[$i]}")
                else
                    content=$(printf '%b›%b %b[ ]%b %s' "$CYAN" "$R" "$DIM" "$R" "${items[$i]}")
                fi
            else
                if [[ "${selected[i]}" == "1" ]]; then
                    content=$(printf '  %b[*]%b %s' "$GREEN" "$R" "${items[$i]}")
                else
                    content=$(printf '  %b[ ]%b %s' "$DIM" "$R" "${items[$i]}")
                fi
            fi
            _box_row "$inner_w" "$content" "$pad"
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
        local back_pad=$((inner_w - 10))
        if [[ $cursor -eq $count ]]; then
            _box_row "$inner_w" "$(printf '%b›%b %b‹ Back%b' "$CYAN" "$R" "$DIM" "$R")" "$back_pad"
        else
            _box_row "$inner_w" "$(printf '  %b‹ Back%b' "$DIM" "$R")" "$back_pad"
        fi
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
                    while [[ $cursor -gt 0 && $cursor -lt $count && "${items[$cursor]}" == "---" ]]; do
                        cursor=$((cursor - 1))
                    done
                fi ;;
            down)
                if [[ $cursor -lt $((total - 1)) ]]; then
                    cursor=$((cursor + 1))
                    while [[ $cursor -lt $count && "${items[$cursor]}" == "---" ]]; do
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
                    [[ "${items[$i]}" == "---" ]] && continue
                    [[ "${selected[$i]}" == "0" ]] && { all_on=false; break; }
                done
                local val="1"; $all_on && val="0"
                for ((i=0; i<count; i++)); do
                    [[ "${items[$i]}" == "---" ]] && continue
                    selected[i]="$val"
                done ;;
            enter)
                if [[ $cursor -eq $count ]]; then _ui_end; return 0; fi
                break ;;
        esac
    done

    _ui_end

    for ((i=0; i<count; i++)); do
        [[ "${items[$i]}" == "---" ]] && continue
        if [[ "${selected[i]}" == "1" ]]; then echo "${items[$i]}"; fi
    done
}

# Reusable prompts
wait_enter() {
    printf '\n  %bpress enter to continue%b ' "$DIM" "$RESET"
    while true; do
        local _k=""
        IFS= read -rsn1 _k < /dev/tty || true
        if [[ "$_k" == $'\x1b' ]]; then
            read -rsn2 -t 1 _ < /dev/tty || true
            continue
        fi
        [[ "$_k" == "" ]] && break
    done
    printf '\n'
}

prompt_path() { printf '  %bpath:%b ' "$CYAN" "$RESET"; }

# Prompt y/n; respects MACRIFT_NO_CONFIRM (auto-yes); returns 0=yes, 1=no
confirm() {
    local msg="${1:-Continue?}"
    local default="${2:-}"
    if [[ "$MACRIFT_NO_CONFIRM" == true ]]; then
        printf '  %b%s%b %b[auto: y]%b\n' "$YELLOW" "$msg" "$RESET" "$DIM" "$RESET"
        _log_file "[auto] $msg → y"
        return 0
    fi
    local hint="y/n"
    [[ "$default" == "y" ]] && hint="Y/n"
    [[ "$default" == "n" ]] && hint="y/N"
    printf '  %b%s%b %b[%s]%b ' "$YELLOW" "$msg" "$RESET" "$DIM" "$hint" "$RESET"
    while true; do
        local key=""
        IFS= read -rsn1 key < /dev/tty || true
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 1 _ < /dev/tty || true
            continue
        fi
        case "$key" in
            [Yy]) printf '%s\n' "$key"; return 0 ;;
            [Nn]) printf '%s\n' "$key"; return 1 ;;
            "")
                printf '\n'
                [[ "$default" == "y" ]] && return 0
                [[ "$default" == "n" ]] && return 1
                ;;
            *) ;;
        esac
    done
}

# Prompt for sudo password if not already cached
require_sudo() {
    if ! sudo -n true 2>/dev/null; then
        printf '\n  %bSudo access needed for system tweaks%b\n' "$YELLOW" "$RESET"
        sudo -v -p "  Password: "
    fi
}

# Ensure Homebrew is available; install if missing, load shellenv for current session
check_homebrew() {
    if ! command -v brew &>/dev/null; then
        # Try to load brew from known paths before declaring missing
        if [[ "$ARCH" == "arm64" && -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -f /usr/local/bin/brew ]]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    fi

    if ! command -v brew &>/dev/null; then
        log_warn "Homebrew not found"
        if confirm "Install Homebrew?"; then
            if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/tty; then
                if [[ "$ARCH" == "arm64" && -f /opt/homebrew/bin/brew ]]; then
                    eval "$(/opt/homebrew/bin/brew shellenv)"
                elif [[ -f /usr/local/bin/brew ]]; then
                    eval "$(/usr/local/bin/brew shellenv)"
                fi
            else
                log_err "Homebrew installation failed"
                return 1
            fi
        else
            log_warn "Some features require Homebrew"
            return 1
        fi
    fi
}

brew_install() {
    local package="$1"
    local type="${2:-formula}" # formula or cask
    local -a flag=(); [[ "$type" == "cask" ]] && flag=("--cask")

    # bash 3.2-safe array expansion — empty arrays under set -u explode otherwise
    if brew list ${flag[@]+"${flag[@]}"} "$package" &>/dev/null; then
        log_skip "$package already installed"
        return 0
    fi
    log_info "Installing $package..."
    if brew install ${flag[@]+"${flag[@]}"} "$package"; then
        log_ok "$package installed"
    else
        log_err "Failed to install $package"
        return 1
    fi
}

#
# Stores pending changes for review before applying
declare -a AUDIT_ENTRIES=()

audit_reset() {
    AUDIT_ENTRIES=()
    AUDIT_OPTIONAL=" "
}

audit_sep() {
    AUDIT_ENTRIES+=("---|---|---|---|---|---")
}

# Queue a defaults write for audit
# Usage: audit_default "com.apple.dock" "autohide" "-bool" "true" "Autohide Dock"
audit_default() {
    local domain="$1"
    local key="$2"
    local type="$3"
    local new_value="$4"
    local label="${5:-$key}"

    local current
    current=$(defaults read "$domain" "$key" 2>/dev/null || echo "default")

    # Normalize: defaults read returns 1/0 for bools
    if [[ "$type" == "-bool" ]]; then
        [[ "$current" == "1" ]] && current="true"
        [[ "$current" == "0" ]] && current="false"
    fi

    AUDIT_ENTRIES+=("${label}|${current}|${new_value}|${domain}|${key}|${type}")
}

# Parallel set of AUDIT_ENTRIES indices that should be unchecked by default in the wizard
# (space-padded to allow substring lookup: " 3 7 12 ")
AUDIT_OPTIONAL=" "

# Same as audit_default but marks the entry as opt-in (default unchecked in wizard)
audit_default_optional() {
    audit_default "$@"
    AUDIT_OPTIONAL+="$((${#AUDIT_ENTRIES[@]} - 1)) "
}


# Show audit table and ask for confirmation
show_audit_table() {
    local category="$1"

    if [[ ${#AUDIT_ENTRIES[@]} -eq 0 ]]; then
        log_info "No changes to apply"
        return 1
    fi

    printf "\n"
    printf '  %b── %s %b' "${BOLD}" "$category" "${RESET}${DIM}"
    printf '─%.0s' {1..35}
    printf '%b\n' "$RESET"
    printf '  %b%-28s %-15s %-15s%b\n' "$DIM" "Setting" "Current" "New" "$RESET"

    local has_changes=false
    for entry in "${AUDIT_ENTRIES[@]}"; do
        IFS='|' read -r label current new_val domain key type sudo_flag <<< "$entry"
        if [[ "$current" != "$new_val" ]]; then
            if [[ "$current" == "default" ]]; then
                printf '  %-28s %b%-15s%b %b%-15s%b\n' "$label" "$DIM" "$current" "$RESET" "$GREEN" "$new_val" "$RESET"
            else
                printf '  %-28s %b%-15s%b %b%-15s%b\n' "$label" "$RED" "$current" "$RESET" "$GREEN" "$new_val" "$RESET"
            fi
            has_changes=true
        else
            printf '  %-28s %b%-15s %-15s%b\n' "$label" "$DIM" "$current" "(no change)" "$RESET"
        fi
    done

    printf '  %b%s%b\n' "$DIM" "$(printf '─%.0s' {1..58})" "$RESET"

    if ! $has_changes; then
        log_ok "Everything already set"
        wait_enter
        audit_reset
        return 1
    fi

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        printf "\n"
        log_info "Dry run — no changes applied"
        audit_reset
        return 1
    fi

    if confirm "Apply these changes?"; then
        return 0
    else
        log_info "No changes applied"
        wait_enter
        audit_reset
        return 1
    fi
}

# Domains that were actually modified (used to decide which services to restart)
declare -a MACRIFT_CHANGED_DOMAINS=()

# Run defaults write/delete with sudo fallback
# Usage: _defaults_cmd "write" domain key type value label sudo_flag
#        _defaults_cmd "delete" domain key "" "" label sudo_flag
# Returns 0 on success, 1 on failure. Appends to MACRIFT_CHANGED_DOMAINS on success.
_defaults_cmd() {
    local cmd="$1" domain="$2" key="$3" type="$4" value="$5" label="$6" sudo_flag="${7:-}"

    local args=("$domain" "$key")
    [[ "$cmd" == "write" ]] && args+=("$type" "$value")

    if [[ "$sudo_flag" == "sudo" ]]; then
        if sudo defaults "$cmd" "${args[@]}" 2>/dev/null; then
            MACRIFT_CHANGED_DOMAINS+=("$domain")
            return 0
        fi
        return 1
    fi

    if defaults "$cmd" "${args[@]}" 2>/dev/null; then
        MACRIFT_CHANGED_DOMAINS+=("$domain")
        return 0
    fi

    log_warn "$label needs sudo ($domain is protected)"
    if sudo defaults "$cmd" "${args[@]}" 2>/dev/null; then
        MACRIFT_CHANGED_DOMAINS+=("$domain")
        return 0
    fi
    return 1
}

# Apply all queued defaults writes
apply_audited_defaults() {
    local applied=0 skipped=0 failed=0

    for entry in "${AUDIT_ENTRIES[@]}"; do
        IFS='|' read -r label current new_val domain key type sudo_flag <<< "$entry"
        label="${label%%~*}"

        if [[ "$current" == "$new_val" ]]; then
            skipped=$((skipped + 1))
            continue
        fi

        local friendly
        friendly=$(_friendly_val "$new_val")

        # Handle chflags entries (e.g. ~/Library)
        if [[ "$domain" == "chflags" ]]; then
            local chflag="$key"
            [[ "$new_val" == "false" ]] && chflag="hidden"
            if chflags "$chflag" ~/Library 2>/dev/null; then
                log_ok "$label → $friendly"
                applied=$((applied + 1))
            else
                log_err "Failed: $label → $friendly"
                failed=$((failed + 1))
            fi
            continue
        fi

        # Handle nvram entries (e.g. StartupMute)
        if [[ "$domain" == "nvram" ]]; then
            local nvram_val="%01"                           # %01 = muted, %00 = sound on (NVRAM raw byte)
            [[ "$new_val" == "true" ]] && nvram_val="%00"
            require_sudo
            if sudo nvram "${key}=${nvram_val}" 2>/dev/null; then
                log_ok "$label → $friendly"
                applied=$((applied + 1))
            else
                log_err "Failed: $label → $friendly"
                failed=$((failed + 1))
            fi
            continue
        fi

        # Handle finder_sort entries — nested dict in com.apple.finder, written via PlistBuddy
        if [[ "$domain" == "finder_sort" ]]; then
            if _finder_sort_write "$new_val"; then
                log_ok "$label → $friendly"
                applied=$((applied + 1))
                MACRIFT_CHANGED_DOMAINS+=("com.apple.finder")
            else
                log_err "Failed: $label → $friendly"
                failed=$((failed + 1))
            fi
            continue
        fi

        # Ensure screenshot directory exists before setting location
        if [[ "$domain" == "com.apple.screencapture" && "$key" == "location" ]]; then
            mkdir -p "$new_val" 2>/dev/null || true
        fi

        if _defaults_cmd "write" "$domain" "$key" "$type" "$new_val" "$label" "${sudo_flag:-}"; then
            log_ok "$label → $friendly"
            applied=$((applied + 1))
        else
            log_err "Failed: $label → $friendly"
            failed=$((failed + 1))
        fi
    done

    local summary="${applied} applied"
    [[ $skipped -gt 0 ]] && summary+=", ${skipped} skipped"
    [[ $failed -gt 0 ]]  && summary+=", ${failed} failed"
    printf '\n'
    log_info "$summary"

    audit_reset
}

# Write the same sort criterion across all 4 Finder default-view subdicts
# (list/column = sortColumn, icon/gallery = arrangeBy). Returns 0 on success.
_finder_sort_write() {
    local value="$1"
    local plist="$HOME/Library/Preferences/com.apple.finder.plist"
    local pb="/usr/libexec/PlistBuddy"
    # Force plist to exist so PlistBuddy can open it
    defaults read com.apple.finder >/dev/null 2>&1
    "$pb" -c "Add :FK_StandardViewSettings dict" "$plist" 2>/dev/null
    local sub view prop rc=0
    for sub in "ExtendedListViewSettingsV2:sortColumn" \
               "ColumnViewSettings:sortColumn" \
               "IconViewSettings:arrangeBy" \
               "GalleryViewSettings:arrangeBy"; do
        view="${sub%%:*}"; prop="${sub##*:}"
        "$pb" -c "Add :FK_StandardViewSettings:$view dict" "$plist" 2>/dev/null
        "$pb" -c "Add :FK_StandardViewSettings:$view:$prop string $value" "$plist" 2>/dev/null \
            || "$pb" -c "Set :FK_StandardViewSettings:$view:$prop $value" "$plist" 2>/dev/null \
            || rc=1
    done
    return $rc
}

# Reset queued defaults (delete keys to restore system defaults)
declare -a RESET_ENTRIES=()

apply_reset_defaults() {
    local reset=0 failed=0

    for entry in "${RESET_ENTRIES[@]}"; do
        IFS='|' read -r label current new_val domain key type sudo_flag <<< "$entry"

        if [[ "$domain" == "finder_sort" ]]; then
            if _finder_sort_write "name"; then
                log_ok "$label → name (default)"
                reset=$((reset + 1))
                MACRIFT_CHANGED_DOMAINS+=("com.apple.finder")
            else
                log_err "Failed to reset: $label"
                failed=$((failed + 1))
            fi
            continue
        fi

        if _defaults_cmd "delete" "$domain" "$key" "" "" "$label" "${sudo_flag:-}"; then
            log_ok "$label → system default"
            reset=$((reset + 1))
        else
            log_err "Failed to reset: $label"
            failed=$((failed + 1))
        fi
    done

    local summary="${reset} reset"
    [[ $failed -gt 0 ]] && summary+=", ${failed} failed"
    printf '\n'
    log_info "$summary"

    RESET_ENTRIES=()
}

# Create a single backup of a file before overwriting.
# `cp -n` keeps the FIRST backup intact across repeated calls — important for
# multi-step flows (install → reset) where a later run would otherwise clobber
# the original with an already-modified version.
backup_file() {
    local target="$1"
    if [[ -f "$target" ]]; then
        local backup="${target}.bak"
        if cp -n "$target" "$backup" 2>/dev/null; then
            log_info "Backed up to ${backup##*/}"
        fi
    fi
}

# Copy file to target, creating parent dirs; logs the destination
copy_config() {
    local source="$1"
    local target="$2"

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Would copy → $target"
        return 0
    fi

    local target_dir
    target_dir=$(dirname "$target")
    mkdir -p "$target_dir"

    backup_file "$target"
    cp "$source" "$target"
    log_ok "Copied → $target"
}

# 
check_macos() {
    if [[ "$(uname)" != "Darwin" ]]; then
        log_err "This script is for macOS only"
        exit 1
    fi
}

# 
get_script_dir() {
    cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

MACRIFT_DIR="$(get_script_dir)"

# Version & Updates
MACRIFT_REPO="emylfy/macrift"
MACRIFT_REPO_TAR="https://github.com/${MACRIFT_REPO}/archive/main.tar.gz"
MACRIFT_VERSION_URL="https://raw.githubusercontent.com/${MACRIFT_REPO}/main/VERSION"
MACRIFT_VERSION=$(cat "$MACRIFT_DIR/VERSION" 2>/dev/null || echo "0")
# Short form (YY.MM) for menu title; full (YY.MM.N) for footer + update compare
if [[ "$MACRIFT_VERSION" =~ ^([0-9]+\.[0-9]+) ]]; then
    MACRIFT_VERSION_SHORT="${BASH_REMATCH[1]}"
else
    MACRIFT_VERSION_SHORT="$MACRIFT_VERSION"
fi
MACRIFT_UPDATE=""

# Check for updates (2s timeout, silent on failure)
check_update() {
    [[ "${MACRIFT_NO_UPDATE:-}" == true ]] && return 0
    local remote
    remote=$(curl -fsSL --connect-timeout 2 --max-time 2 "$MACRIFT_VERSION_URL" 2>/dev/null) || return 0
    if [[ -n "$remote" && "$remote" != "$MACRIFT_VERSION" ]]; then
        MACRIFT_UPDATE="$remote"
    fi
}

# Fetch changelog for the pending update.
# Prefers GitHub compare API (precise, tag-based); falls back to recent commits.
_fetch_update_changelog() {
    local current_tag="v$MACRIFT_VERSION"
    local commits

    # Precise path: requires `v<VERSION>` tag pushed for the current release
    commits=$(curl -fsSL --max-time 5 \
        "https://api.github.com/repos/${MACRIFT_REPO}/compare/${current_tag}...main" 2>/dev/null \
        | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if 'commits' not in d: sys.exit(1)
    for c in d['commits']:
        print('- ' + c['commit']['message'].splitlines()[0])
except Exception:
    sys.exit(1)
" 2>/dev/null)

    if [[ -n "$commits" ]]; then
        printf '%s\n' "$commits"
        return 0
    fi

    # Fallback: last 10 commits (may include ones the user already has)
    commits=$(curl -fsSL --max-time 5 \
        "https://api.github.com/repos/${MACRIFT_REPO}/commits?per_page=10" 2>/dev/null \
        | python3 -c "
import sys, json
try:
    for c in json.load(sys.stdin):
        print('- ' + c['commit']['message'].splitlines()[0])
except Exception:
    pass
" 2>/dev/null)
    [[ -n "$commits" ]] && printf '%s\n' "$commits"
    return 1   # signals 'imprecise' (caller may note this)
}

# Download and apply update
macrift_update() {
    # Show changelog first, then ask
    if [[ -n "$MACRIFT_UPDATE" ]]; then
        printf '\n'
        log_info "Update available: $MACRIFT_VERSION → $MACRIFT_UPDATE"
        printf '\n'
        local changelog precise=0
        if changelog=$(_fetch_update_changelog); then
            precise=1
        fi
        if [[ -n "$changelog" ]]; then
            if [[ $precise -eq 1 ]]; then
                log_info "Changes since v$MACRIFT_VERSION:"
            else
                log_info "Recent commits (no tag for current version — may include ones you have):"
            fi
            printf '%s\n' "$changelog" | while IFS= read -r line; do
                printf '  %b%s%b\n' "$DIM" "$line" "$RESET"
            done
            printf '\n'
        fi
        if ! confirm "Continue with update?" "y"; then
            return 1
        fi
    fi

    log_info "Downloading latest version..."
    local tmp
    tmp="$(mktemp -d)"
    if curl -fsSL "$MACRIFT_REPO_TAR" | tar -xz -C "$tmp" && [[ -d "$tmp/macrift-main" ]]; then
        # Atomic swap: backup old → move new → remove backup
        mv "$MACRIFT_DIR" "$MACRIFT_DIR.bak"
        if mv "$tmp/macrift-main" "$MACRIFT_DIR"; then
            chmod +x "$MACRIFT_DIR/macrift.sh"
            find "$MACRIFT_DIR" -name "*.sh" -exec chmod +x {} +
            rm -rf "$MACRIFT_DIR.bak"
            log_ok "Updated to $(cat "$MACRIFT_DIR/VERSION" 2>/dev/null || echo 'latest')"
        else
            log_err "Failed to replace install directory"
            mv "$MACRIFT_DIR.bak" "$MACRIFT_DIR"
            rm -rf "$tmp"
            return 1
        fi
    else
        log_err "Download failed"
    fi
    rm -rf "$tmp"
    return 0
}
