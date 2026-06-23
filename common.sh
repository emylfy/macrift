#!/usr/bin/env bash
# macrift — shared utilities

# MACRIFT_NO_INIT lets the test suite source this file for its functions alone,
# without enabling errexit or installing traps/temp files. Production never sets it.
[[ -n "${MACRIFT_NO_INIT:-}" ]] || set -euo pipefail

# CPU architecture — used to detect Apple Silicon vs Intel for brew paths
ARCH=$(uname -m)

# Global flags — set by macrift.sh before sourcing, defaults here for direct sourcing
MACRIFT_DRY_RUN="${MACRIFT_DRY_RUN:-false}"
MACRIFT_NO_CONFIRM="${MACRIFT_NO_CONFIRM:-false}"
MACRIFT_LOG="${MACRIFT_LOG:-}"

# Persistent applied-change journal (JSONL) — feeds undo/drift. Unlike the menu
# state file below, this is NOT removed on exit; it accumulates across runs.
MACRIFT_STATE_DIR="${MACRIFT_STATE_DIR:-$HOME/.macrift/state}"
MACRIFT_JOURNAL="$MACRIFT_STATE_DIR/journal.jsonl"
# One session id per run; groups entries so undo can target the last session.
MACRIFT_SESSION="${MACRIFT_SESSION:-$(date +%y%m)-$(printf '%04x' "$RANDOM")}"
# macOS version recorded with each entry (defaults keys change across releases).
MACRIFT_OS_VER="${MACRIFT_OS_VER:-$(sw_vers -productVersion 2>/dev/null || echo '?')}"

# Restore cursor on exit, clean up state file
_macrift_cleanup() {
    printf "\033[?25h" 2>/dev/null
    rm -f "$MENU_STATE_FILE"
}

# Shared state file for menu cursor positions (per macrift run).
# Needed because show_menu runs in a $() subshell — in-memory var won't persist.
# Created via mktemp (random name, mode 0600) so a shared /tmp can't be seeded
# with a symlink at a predictable path; falls back to a PID name if mktemp fails.
# Skipped under MACRIFT_NO_INIT so sourcing for tests leaves no temp file / trap.
if [[ -z "${MACRIFT_NO_INIT:-}" ]]; then
    MENU_STATE_FILE="$(mktemp "${TMPDIR:-/tmp}/macrift-menu.XXXXXX" 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/macrift-menu.$$")"
    trap '_macrift_cleanup; sudo -k 2>/dev/null' EXIT
    trap 'exit 130' INT TERM
fi

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


# Feedback contract — every action follows three rules:
#   1. State the result: what changed, with magnitude where cheap (log_ok).
#   2. Explain no-ops: say why nothing happened (log_skip "X — reason"), never go silent.
#   3. Offer a fallback: follow a failure with log_hint giving the next concrete step.
log_info()  { printf '  %b›%b  %s\n' "${CYAN}" "${RESET}" "$1"; _log_file "[info] $1"; }
log_ok()    { printf '  %b✓%b  %s\n' "${GREEN}" "${RESET}" "$1"; _log_file "[  ok] $1"; }
log_err()   { printf '  %b✗%b  %s\n' "${RED}" "${RESET}" "$1"; _log_file "[ err] $1"; }
log_warn()  { printf '  %b!%b  %s\n' "${YELLOW}" "${RESET}" "$1"; _log_file "[warn] $1"; }
log_skip()  { printf '  %b-%b  %s\n' "${DIM}" "${RESET}" "$1"; _log_file "[skip] $1"; }
# Fallback continuation — follows log_err/log_warn with an actionable next step.
# The ↳ sits under the message text of the line it follows.
log_hint()  { printf '     %b↳ %s%b\n' "${DIM}" "$1" "${RESET}"; _log_file "[hint] $1"; }

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

# Pending dotfile copies from a manifest apply (src\x1fdest\x1fmode\x1flabel)
declare -a DOTFILE_UNITS=()

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

# JSON-escape a single scalar for embedding in a journal line.
_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/\\r}"
    printf '%s' "$s"
}

# Append one applied change to the journal (JSONL) for later undo/drift.
# Best-effort: a journaling failure never aborts an apply. No-op in dry-run.
# old=="default" (key was unset before) is recorded as JSON null.
# Usage: _journal_append <kind> <label> <domain> <key> <type> <value> <old>
_journal_append() {
    [[ "${MACRIFT_DRY_RUN:-false}" == true ]] && return 0
    local kind="$1" label="$2" domain="$3" key="$4" vtype="$5" value="$6" old="$7"
    mkdir -p "$MACRIFT_STATE_DIR" 2>/dev/null || return 0
    local ts; ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    local old_json="null"
    [[ "$old" != "default" ]] && old_json="\"$(_json_escape "$old")\""
    printf '{"session":"%s","ts":"%s","macos":"%s","status":"applied","kind":"%s","id":"","label":"%s","domain":"%s","key":"%s","type":"%s","value":"%s","old":%s}\n' \
        "$MACRIFT_SESSION" "$ts" "$MACRIFT_OS_VER" \
        "$(_json_escape "$kind")" "$(_json_escape "$label")" "$(_json_escape "$domain")" \
        "$(_json_escape "$key")" "$(_json_escape "$vtype")" "$(_json_escape "$value")" "$old_json" \
        >> "$MACRIFT_JOURNAL" 2>/dev/null || true
}

# Append a dotfile copy to the journal so undo/drift can see it. dest is the
# change identity; old holds the .bak path (pre-macrift original), or null when
# the dest didn't exist before — undo then removes dest instead of restoring.
# Usage: _journal_append_dotfile <src> <dest> <bak-path-or-empty>
_journal_append_dotfile() {
    [[ "${MACRIFT_DRY_RUN:-false}" == true ]] && return 0
    local src="$1" dest="$2" bak="$3"
    mkdir -p "$MACRIFT_STATE_DIR" 2>/dev/null || return 0
    local ts; ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    local old_json="null"
    [[ -n "$bak" ]] && old_json="\"$(_json_escape "$bak")\""
    printf '{"session":"%s","ts":"%s","macos":"%s","status":"applied","kind":"dotfile","id":"","src":"%s","dest":"%s","old":%s}\n' \
        "$MACRIFT_SESSION" "$ts" "$MACRIFT_OS_VER" \
        "$(_json_escape "$src")" "$(_json_escape "$dest")" "$old_json" \
        >> "$MACRIFT_JOURNAL" 2>/dev/null || true
}

# Read the current live value of a journaled change, normalized to compare
# against the stored value/old. Echoes "default" if unset, "__UNKNOWN__" if
# the kind can't be read. Mirrors the read logic in the tweak files.
_journal_live_value() {
    local kind="$1" domain="$2" key="$3" vtype="$4"
    case "$kind" in
        default)
            local v
            v=$(defaults read "$domain" "$key" 2>/dev/null) || { echo "default"; return; }
            if [[ "$vtype" == "-bool" ]]; then
                [[ "$v" == "1" ]] && v="true"
                [[ "$v" == "0" ]] && v="false"
            fi
            echo "$v" ;;
        nvram)
            # value semantics: true = sound on (%00), false = muted (%01)
            if nvram "$key" 2>/dev/null | grep -q '%01'; then echo "false"; else echo "true"; fi ;;
        chflags)
            # value semantics: true = visible (nohidden), false = hidden
            if [[ "$(stat -f '%Sf' "$HOME/Library" 2>/dev/null)" == *hidden* ]]; then echo "false"; else echo "true"; fi ;;
        finder_sort)
            /usr/libexec/PlistBuddy -c \
                "Print :FK_StandardViewSettings:ExtendedListViewSettingsV2:sortColumn" \
                "$HOME/Library/Preferences/com.apple.finder.plist" 2>/dev/null || echo "name" ;;
        *) echo "__UNKNOWN__" ;;
    esac
}

# Forward maps for the non-defaults change kinds, shared by apply (forward) and
# undo/reset (inverse) so the two directions can't drift out of sync.
# nvram StartupMute: true = sound on (%00 raw byte), false = muted (%01).
_nvram_byte_for_bool() {
    if [[ "$1" == "true" ]]; then printf '%%00'; else printf '%%01'; fi
}
# chflags ~/Library: true = visible (nohidden), false = hidden.
_chflags_for_visible() {
    if [[ "$1" == "true" ]]; then printf 'nohidden'; else printf 'hidden'; fi
}

# Classify a journaled change against its live value (pure). Caller handles the
# dotfile and __UNKNOWN__ cases separately.
#   held: live still matches the applied value
#   reverted: live is back to the pre-macrift state — "default" when the key was
#             unset before (old_null=1), else the recorded old value
#   drifted: anything else
_drift_state() {
    local live="$1" value="$2" old="$3" old_null="$4"
    if [[ "$live" == "$value" ]]; then
        echo "held"
    elif [[ "$old_null" == "1" && "$live" == "default" ]] || \
         [[ "$old_null" == "0" && "$live" == "$old" ]]; then
        echo "reverted"
    else
        echo "drifted"
    fi
}

# `macrift drift` — read-only. Compares each journaled change to the live system.
# Classifies each: held (still matches), reverted (back to pre-macrift state),
# drifted (changed to something else), unknown (couldn't read).
journal_drift_cli() {
    if [[ ! -s "$MACRIFT_JOURNAL" ]]; then
        log_info "No journal yet — apply some tweaks first"
        return 0
    fi

    # Dedup to the latest journaled entry per (kind, domain, key)
    local rows
    rows=$(python3 - "$MACRIFT_JOURNAL" <<'PY'
import json, sys, collections, os
def ident(d):
    # dotfile identity is its dest (domain/key are empty); everything else
    # keys on (domain, key).
    if d.get("kind") == "dotfile":
        return ("dotfile", d.get("dest"))
    return (d.get("kind"), d.get("domain"), d.get("key"))
def label_of(d):
    if d.get("kind") == "dotfile":
        return d.get("label") or os.path.basename(d.get("dest", "")) or d.get("dest", "")
    return d.get("label", "") or d.get("key", "")
latest = collections.OrderedDict()
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    latest[ident(d)] = d
for d in latest.values():
    old = d.get("old")
    # Join on US (\x1f), not tab: tab is IFS whitespace in bash and would
    # collapse the empty old field, shifting later columns.
    print("\x1f".join([
        d.get("kind", ""), d.get("domain", ""), d.get("key", ""),
        d.get("type", ""), str(d.get("value", "")),
        "" if old is None else str(old),
        "1" if old is None else "0",
        label_of(d),
        d.get("dest", ""), d.get("src", ""),
    ]))
PY
)
    if [[ -z "$rows" ]]; then
        log_info "Journal is empty"
        return 0
    fi

    printf "\n"
    printf '  %b%-26s %-14s %-14s %s%b\n' "$DIM" "Setting" "Wanted" "Current" "State" "$RESET"
    printf '  %b%s%b\n' "$DIM" "$(printf '─%.0s' {1..62})" "$RESET"

    local held=0 drifted=0 reverted=0 unknown=0
    while IFS=$'\x1f' read -r kind domain key vtype value old old_null label dest src; do
        [[ -z "$kind" ]] && continue
        local state color live

        # dotfile: we only know presence, not content — held if the copy is
        # still there, reverted if gone and nothing existed before, else drifted.
        if [[ "$kind" == "dotfile" ]]; then
            if [[ -e "$dest" ]]; then
                state="held"; color="$GREEN"; held=$((held + 1)); live="present"
            elif [[ "$old_null" == "1" ]]; then
                state="reverted"; color="$YELLOW"; reverted=$((reverted + 1)); live="absent"
            else
                state="drifted"; color="$RED"; drifted=$((drifted + 1)); live="absent"
            fi
            printf '  %-26.26s %b%-14.14s%b %-14.14s %b%s%b\n' \
                "$label" "$DIM" "present" "$RESET" "$live" "$color" "$state" "$RESET"
            continue
        fi

        live=$(_journal_live_value "$kind" "$domain" "$key" "$vtype")
        if [[ "$live" == "__UNKNOWN__" ]]; then
            state="unknown"; color="$DIM"; unknown=$((unknown + 1)); live="?"
        else
            state=$(_drift_state "$live" "$value" "$old" "$old_null")
            case "$state" in
                held)     color="$GREEN";  held=$((held + 1)) ;;
                reverted) color="$YELLOW"; reverted=$((reverted + 1)) ;;
                drifted)  color="$RED";    drifted=$((drifted + 1)) ;;
            esac
        fi
        printf '  %-26.26s %b%-14.14s%b %-14.14s %b%s%b\n' \
            "$label" "$DIM" "$(_friendly_val "$value")" "$RESET" \
            "$(_friendly_val "$live")" "$color" "$state" "$RESET"
    done <<< "$rows"

    printf '  %b%s%b\n' "$DIM" "$(printf '─%.0s' {1..62})" "$RESET"
    local summary="${held} held"
    [[ $drifted  -gt 0 ]] && summary+=", ${drifted} drifted"
    [[ $reverted -gt 0 ]] && summary+=", ${reverted} reverted"
    [[ $unknown  -gt 0 ]] && summary+=", ${unknown} unknown"
    printf '\n'
    log_info "$summary"
}

# List recorded sessions (oldest first) with change counts.
_journal_list_sessions() {
    printf "\n"
    log_info "Recorded sessions (newest last):"
    printf '\n'
    python3 - "$MACRIFT_JOURNAL" <<'PY'
import json, sys, collections
agg = collections.OrderedDict()
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    s = d.get("session", "?")
    if s not in agg:
        agg[s] = {"n": 0, "ts": d.get("ts", ""), "macos": d.get("macos", "")}
    agg[s]["n"] += 1
for s, v in agg.items():
    print(f"    {s}   {v['n']:>3} changes   {v['ts']}   macOS {v['macos']}")
PY
}

# `macrift undo [<session>|list]` — revert a journaled session to its
# pre-macrift state. Default target is the last session. Reuses the audit-time
# `old` values and apply_reset_defaults. Honors --dry-run / --no-confirm.
journal_undo_cli() {
    local arg="${1:-}"
    if [[ ! -s "$MACRIFT_JOURNAL" ]]; then
        log_info "No journal yet — nothing to undo"
        return 0
    fi

    if [[ "$arg" == "list" ]]; then
        _journal_list_sessions
        return 0
    fi

    # Resolve target session (last recorded if none given)
    local target="$arg"
    if [[ -z "$target" ]]; then
        target=$(python3 - "$MACRIFT_JOURNAL" <<'PY'
import json, sys
last = ""
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    try:
        last = json.loads(line).get("session", last)
    except Exception:
        pass
print(last)
PY
)
    fi
    if [[ -z "$target" ]]; then
        log_warn "Could not determine a session to undo"
        return 1
    fi

    # First entry per (kind, domain, key) in the session = pre-session state
    local rows
    rows=$(python3 - "$MACRIFT_JOURNAL" "$target" <<'PY'
import json, sys, collections, os
target = sys.argv[2]
def ident(d):
    if d.get("kind") == "dotfile":
        return ("dotfile", d.get("dest"))
    return (d.get("kind"), d.get("domain"), d.get("key"))
def label_of(d):
    if d.get("kind") == "dotfile":
        return d.get("label") or os.path.basename(d.get("dest", "")) or d.get("dest", "")
    return d.get("label", "") or d.get("key", "")
first = collections.OrderedDict()
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get("session") != target:
        continue
    k = ident(d)
    if k in first:
        continue
    first[k] = d
for d in first.values():
    old = d.get("old")
    print("\x1f".join([
        d.get("kind", ""), d.get("domain", ""), d.get("key", ""),
        d.get("type", ""), str(d.get("value", "")),
        "" if old is None else str(old),
        "1" if old is None else "0",
        label_of(d),
        d.get("dest", ""), d.get("src", ""),
    ]))
PY
)
    if [[ -z "$rows" ]]; then
        log_warn "No changes recorded for session $target"
        return 1
    fi

    printf "\n"
    log_info "Undo session $target — restoring pre-macrift values:"
    printf '\n'
    printf '  %b%-26s %-14s %-14s%b\n' "$DIM" "Setting" "Current" "Restore to" "$RESET"
    printf '  %b%s%b\n' "$DIM" "$(printf '─%.0s' {1..58})" "$RESET"

    RESET_ENTRIES=()
    DOTFILE_RESETS=()
    local changes=0
    while IFS=$'\x1f' read -r kind domain key vtype value old old_null label dest src; do
        [[ -z "$kind" ]] && continue

        # dotfile: restore the .bak, or remove dest if nothing existed before.
        if [[ "$kind" == "dotfile" ]]; then
            local d_disp
            if [[ "$old_null" == "1" ]]; then
                [[ ! -e "$dest" ]] && continue          # already gone
                d_disp="remove"
            else
                [[ ! -f "$old" ]] && { log_warn "$label — backup gone, skipping"; continue; }
                d_disp="restore ${old##*/}"
            fi
            local cur="absent"; [[ -e "$dest" ]] && cur="present"
            printf '  %-26.26s %b%-14.14s%b %b%-14.14s%b\n' \
                "$label" "$DIM" "$cur" "$RESET" "$GREEN" "$d_disp" "$RESET"
            DOTFILE_RESETS+=("${dest}|${old}|${old_null}")
            changes=$((changes + 1))
            continue
        fi

        local live target_val target_disp
        live=$(_journal_live_value "$kind" "$domain" "$key" "$vtype")
        if [[ "$old_null" == "1" ]]; then
            target_val="default"; target_disp="system default"
        else
            target_val="$old"; target_disp="$(_friendly_val "$old")"
        fi
        # Skip if already at the restore target
        if [[ "$live" == "$target_val" ]] || [[ "$old_null" == "1" && "$live" == "default" ]]; then
            continue
        fi
        printf '  %-26.26s %b%-14.14s%b %b%-14.14s%b\n' \
            "$label" "$DIM" "$(_friendly_val "$live")" "$RESET" "$GREEN" "$target_disp" "$RESET"
        RESET_ENTRIES+=("${label}|${target_val}|${value}|${domain}|${key}|${vtype}")
        changes=$((changes + 1))
    done <<< "$rows"
    printf '  %b%s%b\n' "$DIM" "$(printf '─%.0s' {1..58})" "$RESET"

    if [[ $changes -eq 0 ]]; then
        printf '\n'
        log_ok "Nothing to undo — already at pre-macrift state"
        RESET_ENTRIES=(); DOTFILE_RESETS=()
        return 0
    fi

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        printf '\n'
        log_info "Dry run — no changes applied"
        RESET_ENTRIES=(); DOTFILE_RESETS=()
        return 0
    fi

    printf '\n'
    if ! confirm "Revert these $changes change(s)?"; then
        log_info "Undo cancelled"
        RESET_ENTRIES=(); DOTFILE_RESETS=()
        return 0
    fi

    MACRIFT_CHANGED_DOMAINS=()
    [[ ${#RESET_ENTRIES[@]} -gt 0 ]] && apply_reset_defaults
    [[ ${#DOTFILE_RESETS[@]} -gt 0 ]] && _undo_restore_dotfiles

    # Restart services whose domain we touched
    local need_dock=false need_finder=false d
    for d in "${MACRIFT_CHANGED_DOMAINS[@]:+${MACRIFT_CHANGED_DOMAINS[@]}}"; do
        [[ "$d" == *dock* ]] && need_dock=true
        [[ "$d" == *finder* || "$d" == *desktopservices* ]] && need_finder=true
    done
    MACRIFT_CHANGED_DOMAINS=()
    if $need_dock || $need_finder; then
        printf '\n'
        if confirm "Restart affected services?"; then
            $need_dock   && { killall Dock 2>/dev/null   || true; log_ok "Dock restarted"; }
            $need_finder && { killall Finder 2>/dev/null || true; log_ok "Finder restarted"; }
        fi
    fi
}

# `macrift apply [<file.json>]` — apply a declarative manifest. Desugars the
# JSON surface into the engine's audit entries, previews via show_audit_table,
# and applies through apply_audited_defaults (which journals each change).
# Covers the defaults family (default/finder_sort/nvram/chflags) plus dotfile
# copies (via copy_config); brew, plist, command are reported as not-yet-applied.
manifest_apply_cli() {
    local manifest="${1:-$HOME/.config/macrift/macrift.json}"
    if [[ ! -f "$manifest" ]]; then
        log_err "Manifest not found: $manifest"
        log_info "Pass a path: macrift apply <file.json>"
        return 1
    fi

    local out
    out=$(python3 - "$manifest" "$MACRIFT_OS_VER" <<'PY'
import json, sys, os
SEP = "\x1f"
TYPE_MAP = {"bool": "-bool", "int": "-int", "float": "-float", "string": "-string"}

def os_major(v):
    try:
        return int(str(v).split(".")[0])
    except Exception:
        return None

run_major = os_major(sys.argv[2]) if len(sys.argv) > 2 else None

def nval(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    return str(v)

def version_ok(u):
    if run_major is None:
        return True
    mn, mx = u.get("min_macos"), u.get("max_macos")
    if mn is not None and (m := os_major(mn)) is not None and run_major < m:
        return False
    if mx is not None and (m := os_major(mx)) is not None and run_major > m:
        return False
    return True

try:
    with open(sys.argv[1]) as f:
        m = json.load(f)
except Exception as e:
    sys.stderr.write("parse error: %s\n" % e)
    sys.exit(2)

units = []
skipped_version = 0

def add(kind, domain, key, vtype, value, label, unit=None):
    global skipped_version
    if unit is not None and not version_ok(unit):
        skipped_version += 1
        return
    units.append((kind, domain, key, vtype, value, label))

for d in m.get("defaults", []):
    add("default", d["domain"], d["key"],
        TYPE_MAP.get(d.get("type", "string"), "-string"),
        nval(d["value"]), d.get("label") or d.get("id") or d["key"], d)

fin = m.get("finder", {})
if "sort" in fin:
    add("finder_sort", "finder_sort", "sort", "", str(fin["sort"]), "Finder sort")
if "hidden_files" in fin:
    add("default", "com.apple.finder", "AppleShowAllFiles", "-bool",
        nval(fin["hidden_files"]), "Show hidden files")

boot = m.get("boot", {})
if "startup_sound" in boot:
    add("nvram", "nvram", "StartupMute", "-bool", nval(boot["startup_sound"]), "Startup sound")

lib = m.get("library", {})
if "visible" in lib:
    add("chflags", "chflags", "nohidden", "-bool", nval(lib["visible"]), "Show Library folder")

# dotfile units are file copies, not audit-table entries — emit on a separate
# channel (__DOTFILE__ marker) and let the bash side route them to copy_config.
dots = []
for df in m.get("dotfile", []):
    if not version_ok(df):
        skipped_version += 1
        continue
    src, dest = df.get("src", ""), df.get("dest", "")
    if not src or not dest:
        continue
    label = df.get("label") or df.get("id") or os.path.basename(dest) or dest
    dots.append(("__DOTFILE__", src, dest, str(df.get("mode") or ""), label))

unsupported = [f"{k}:{len(m.get(k, []))}"
               for k in ("brew", "plist", "command") if m.get(k)]

for u in units:
    print(SEP.join(u))
for d in dots:
    print(SEP.join(d))
print("__META__" + SEP + str(skipped_version) + SEP + ",".join(unsupported))
PY
) || { log_err "Could not parse manifest (invalid JSON?)"; return 1; }

    audit_reset
    DOTFILE_UNITS=()
    local skipped_version=0 unsupported=""
    while IFS=$'\x1f' read -r kind domain key vtype value label; do
        [[ -z "$kind" ]] && continue
        if [[ "$kind" == "__META__" ]]; then
            skipped_version="$domain"; unsupported="$key"; continue
        fi
        if [[ "$kind" == "__DOTFILE__" ]]; then
            # Reader columns reused: domain=src, key=dest, vtype=mode, value=label.
            DOTFILE_UNITS+=("${domain}"$'\x1f'"${key}"$'\x1f'"${vtype}"$'\x1f'"${value}")
            continue
        fi
        local current
        current=$(_journal_live_value "$kind" "$domain" "$key" "$vtype")
        AUDIT_ENTRIES+=("${label}|${current}|${value}|${domain}|${key}|${vtype}")
    done <<< "$out"

    if [[ ${#AUDIT_ENTRIES[@]} -eq 0 && ${#DOTFILE_UNITS[@]} -eq 0 ]]; then
        log_warn "No applicable settings in manifest"
        [[ -n "$unsupported" ]] && log_info "Not yet supported by apply: $unsupported"
        return 0
    fi

    # Defaults family — audit table gates and applies (each change journaled).
    if [[ ${#AUDIT_ENTRIES[@]} -gt 0 ]] && show_audit_table "Manifest"; then
        MACRIFT_CHANGED_DOMAINS=()
        apply_audited_defaults
        local need_dock=false need_finder=false d
        for d in "${MACRIFT_CHANGED_DOMAINS[@]:+${MACRIFT_CHANGED_DOMAINS[@]}}"; do
            [[ "$d" == *dock* ]] && need_dock=true
            [[ "$d" == *finder* || "$d" == *desktopservices* ]] && need_finder=true
        done
        MACRIFT_CHANGED_DOMAINS=()
        if $need_dock || $need_finder; then
            printf '\n'
            if confirm "Restart affected services?"; then
                $need_dock   && { killall Dock 2>/dev/null   || true; log_ok "Dock restarted"; }
                $need_finder && { killall Finder 2>/dev/null || true; log_ok "Finder restarted"; }
            fi
        fi
    fi

    # Dotfiles — separate preview/confirm, copied via copy_config (journaled, so
    # undo/drift work for free). Gated independently of the defaults table.
    if [[ ${#DOTFILE_UNITS[@]} -gt 0 ]]; then
        _manifest_apply_dotfiles "$(dirname "$manifest")"
    fi

    [[ "${skipped_version:-0}" -gt 0 ]] && log_info "$skipped_version skipped (macOS version guard)"
    [[ -n "$unsupported" ]] && log_info "Not yet applied by macrift apply: $unsupported"
    return 0
}

# Apply manifest dotfile units (DOTFILE_UNITS, each "src\x1fdest\x1fmode\x1flabel"
# with src relative to the manifest dir). Previews, confirms once, then copies via
# copy_config — which backs up and journals each copy for undo/drift.
_manifest_apply_dotfiles() {
    local manifest_dir="$1"
    local unit src dest mode label src_abs dest_abs status p
    local -a plan=()
    for unit in "${DOTFILE_UNITS[@]}"; do
        IFS=$'\x1f' read -r src dest mode label <<< "$unit"
        case "$src" in /*) src_abs="$src" ;; *) src_abs="$manifest_dir/$src" ;; esac
        dest_abs="${dest/#\~/$HOME}"
        if [[ ! -f "$src_abs" ]]; then status="missing src"
        elif [[ -e "$dest_abs" ]]; then status="overwrite"
        else status="new"; fi
        plan+=("${label}"$'\x1f'"${src_abs}"$'\x1f'"${dest_abs}"$'\x1f'"${mode}"$'\x1f'"${status}")
    done

    printf '\n'
    printf '  %b── Dotfiles %b' "${BOLD}" "${RESET}${DIM}"
    printf '─%.0s' {1..34}
    printf '%b\n' "$RESET"
    printf '  %b%-26s %-13s %s%b\n' "$DIM" "File" "Action" "Destination" "$RESET"
    for p in "${plan[@]}"; do
        IFS=$'\x1f' read -r label src_abs dest_abs mode status <<< "$p"
        local color="$GREEN"; [[ "$status" == "missing src" ]] && color="$RED"
        printf '  %-26.26s %b%-13s%b %s\n' "$label" "$color" "$status" "$RESET" "$dest_abs"
    done
    printf '  %b%s%b\n' "$DIM" "$(printf '─%.0s' {1..58})" "$RESET"

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        printf '\n'; log_info "Dry run — no dotfiles copied"; return 0
    fi
    printf '\n'
    if ! confirm "Copy these dotfiles?"; then
        log_info "No dotfiles copied"; return 0
    fi

    for p in "${plan[@]}"; do
        IFS=$'\x1f' read -r label src_abs dest_abs mode status <<< "$p"
        if [[ "$status" == "missing src" ]]; then
            log_warn "$label — source not found: $src_abs"; continue
        fi
        copy_config "$src_abs" "$dest_abs"
        [[ -n "$mode" ]] && chmod "$mode" "$dest_abs" 2>/dev/null
    done
}

# `macrift save [<file.json>]` — snapshot the current value of every tweak
# macrift knows about into a JSON manifest. Reuses the tweak spec-builders to
# populate AUDIT_ENTRIES with live values, then records only non-default ones
# (per-key, not a wholesale domain dump). Restore with `macrift apply <file>`.
manifest_save_cli() {
    local out_file="${1:-$HOME/.config/macrift/macrift.json}"

    # Build AUDIT_ENTRIES with current live values for all standard tweaks
    audit_reset
    local f
    # shellcheck disable=SC1090
    for f in dock finder keyboard input screenshots misc; do
        source "$MACRIFT_DIR/tweaks/$f.sh"
    done
    dock_tweaks; finder_tweaks; keyboard_tweaks; input_tweaks; screenshots_tweaks; misc_tweaks
    # shellcheck disable=SC1090
    source "$MACRIFT_DIR/tweaks/privacy.sh"; privacy_recommended; privacy_strict

    if [[ ${#AUDIT_ENTRIES[@]} -eq 0 ]]; then
        log_warn "No tweaks detected to save"
        return 1
    fi

    # Pass entries via a temp file, not stdin: python's program already comes
    # from the heredoc on stdin, so a pipe would be shadowed by it.
    local entries_tmp
    entries_tmp=$(mktemp)
    printf '%s\n' "${AUDIT_ENTRIES[@]}" > "$entries_tmp"
    audit_reset

    local manifest_json
    manifest_json=$(python3 - "$entries_tmp" "$MACRIFT_VERSION" "$MACRIFT_OS_VER" \
        "$(scutil --get LocalHostName 2>/dev/null || hostname -s 2>/dev/null || echo mac)" <<'PY'
import sys, json
entries_path, ver, osv, host = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
TYPE = {"-bool": "bool", "-int": "int", "-float": "float", "-string": "string"}

def conv(t, v):
    # Only bool becomes a JSON boolean. int/float/string keep their raw
    # `defaults read` string so a save→apply round-trip compares byte-identical
    # (e.g. avoids "0" vs "0.0" float-formatting drift).
    if t == "-bool":
        return v == "true"
    return v

defaults, finder, boot, library = [], {}, {}, {}
for line in open(entries_path):
    line = line.rstrip("\n")
    if not line:
        continue
    p = line.split("|")
    if len(p) < 6:
        continue
    label, current, new_val, domain, key, vtype = p[:6]
    label = label.split("~", 1)[0]
    if label == "---" or current == "default":
        continue                       # separators / already-default keys: nothing to reproduce
    if domain == "finder_sort":
        finder["sort"] = current
    elif domain == "nvram" and key == "StartupMute":
        boot["startup_sound"] = (current == "true")
    elif domain == "chflags":
        library["visible"] = (current == "true")
    else:
        defaults.append({
            "label": label, "domain": domain, "key": key,
            "type": TYPE.get(vtype, "string"), "value": conv(vtype, current),
        })

m = {"meta": {"name": host, "macrift": ver, "source_macos": osv}, "defaults": defaults}
if finder:  m["finder"] = finder
if boot:    m["boot"] = boot
if library: m["library"] = library
print(json.dumps(m, indent=2))
PY
)
    rm -f "$entries_tmp"

    if [[ -z "$manifest_json" ]]; then
        log_err "Failed to build manifest"
        return 1
    fi

    mkdir -p "$(dirname "$out_file")"
    printf '%s\n' "$manifest_json" > "$out_file"
    local n
    n=$(grep -c '"domain"' "$out_file" 2>/dev/null) || true
    printf '\n'
    log_ok "Saved manifest → $out_file"
    log_info "Captured ${n:-0} non-default setting(s). Restore: macrift apply \"$out_file\""
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
            local chflag; chflag=$(_chflags_for_visible "$new_val")
            if chflags "$chflag" ~/Library 2>/dev/null; then
                log_ok "$label → $friendly"
                _journal_append "chflags" "$label" "$domain" "$key" "$type" "$new_val" "$current"
                applied=$((applied + 1))
            else
                log_err "Failed: $label → $friendly"
                failed=$((failed + 1))
            fi
            continue
        fi

        # Handle nvram entries (e.g. StartupMute)
        if [[ "$domain" == "nvram" ]]; then
            local nvram_val; nvram_val=$(_nvram_byte_for_bool "$new_val")
            require_sudo
            if sudo nvram "${key}=${nvram_val}" 2>/dev/null; then
                log_ok "$label → $friendly"
                _journal_append "nvram" "$label" "$domain" "$key" "$type" "$new_val" "$current"
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
                _journal_append "finder_sort" "$label" "$domain" "$key" "$type" "$new_val" "$current"
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
            _journal_append "default" "$label" "$domain" "$key" "$type" "$new_val" "$current"
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
    [[ $failed -gt 0 ]] && log_hint "managed by a config profile (MDM)? some keys can't be set — check System Settings"

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

# Restore queued defaults to their pre-macrift values (captured at audit time).
# If the key was unset before (current=="default"), delete the key so system
# default applies; otherwise write the captured value back so user customizations
# made before running macrift are preserved.
declare -a RESET_ENTRIES=()
# Queued dotfile reversions, populated by journal_undo_cli: "dest|bak|old_null".
declare -a DOTFILE_RESETS=()

# Revert journaled dotfile copies: restore the .bak, or remove dest when nothing
# existed before macrift wrote it (old_null==1).
_undo_restore_dotfiles() {
    local entry dest bak null
    for entry in "${DOTFILE_RESETS[@]:+${DOTFILE_RESETS[@]}}"; do
        IFS='|' read -r dest bak null <<< "$entry"
        if [[ "$null" == "1" ]]; then
            if rm -f "$dest" 2>/dev/null; then
                log_ok "${dest##*/} → removed"
            else
                log_err "Failed to remove: $dest"
            fi
        elif cp "$bak" "$dest" 2>/dev/null; then
            log_ok "${dest##*/} → restored from ${bak##*/}"
        else
            log_err "Failed to restore: $dest"
        fi
    done
}

apply_reset_defaults() {
    local reset=0 failed=0

    for entry in "${RESET_ENTRIES[@]}"; do
        IFS='|' read -r label current new_val domain key type sudo_flag <<< "$entry"

        if [[ "$domain" == "finder_sort" ]]; then
            # current was captured from PlistBuddy or defaulted to "name" if unset
            if _finder_sort_write "$current"; then
                log_ok "$label → $current"
                reset=$((reset + 1))
                MACRIFT_CHANGED_DOMAINS+=("com.apple.finder")
            else
                log_err "Failed to reset: $label"
                failed=$((failed + 1))
            fi
            continue
        fi

        # nvram / chflags carry a real prior bool in $current (the tweak files
        # capture it by hand). Mirror the forward mapping to invert them.
        if [[ "$domain" == "nvram" ]]; then
            if [[ "$current" == "default" ]]; then
                log_warn "$label — no prior state recorded, skipping"
            else
                local nvram_val; nvram_val=$(_nvram_byte_for_bool "$current")
                require_sudo
                if sudo nvram "${key}=${nvram_val}" 2>/dev/null; then
                    log_ok "$label → $(_friendly_val "$current")"; reset=$((reset + 1))
                else
                    log_err "Failed to reset: $label"; failed=$((failed + 1))
                fi
            fi
            continue
        fi

        if [[ "$domain" == "chflags" ]]; then
            if [[ "$current" == "default" ]]; then
                log_warn "$label — no prior state recorded, skipping"
            else
                local cf; cf=$(_chflags_for_visible "$current")
                if chflags "$cf" ~/Library 2>/dev/null; then
                    log_ok "$label → $(_friendly_val "$current")"; reset=$((reset + 1))
                else
                    log_err "Failed to reset: $label"; failed=$((failed + 1))
                fi
            fi
            continue
        fi

        local rc
        if [[ "$current" == "default" ]]; then
            _defaults_cmd "delete" "$domain" "$key" "" "" "$label" "${sudo_flag:-}"
            rc=$?
        else
            _defaults_cmd "write" "$domain" "$key" "$type" "$current" "$label" "${sudo_flag:-}"
            rc=$?
        fi

        if [[ $rc -eq 0 ]]; then
            if [[ "$current" == "default" ]]; then
                log_ok "$label → system default"
            else
                log_ok "$label → $(_friendly_val "$current")"
            fi
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
    [[ $failed -gt 0 ]] && log_hint "managed by a config profile (MDM)? some keys can't be set — check System Settings"

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

    local existed=false
    [[ -f "$target" ]] && existed=true
    backup_file "$target"
    cp "$source" "$target"
    log_ok "Copied → $target"

    # Journal for undo/drift. bak holds the pre-macrift original (backup_file
    # keeps the FIRST .bak via cp -n, so this stays valid across re-runs).
    local bak=""
    [[ "$existed" == true && -f "${target}.bak" ]] && bak="${target}.bak"
    _journal_append_dotfile "$source" "$target" "$bak"
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

# true if $1 is a strictly newer dotted calver (YY.MM.N) than $2.
# Component-wise numeric compare; 10# forces base-10 so "05" isn't read as octal.
_macrift_version_gt() {
    [[ "$1" == "$2" ]] && return 1
    local IFS=. i x y
    # shellcheck disable=SC2206  # intentional split on IFS='.' into version components
    local -a a=($1) b=($2)
    for ((i = 0; i < ${#a[@]} || i < ${#b[@]}; i++)); do
        x=${a[i]:-0}
        y=${b[i]:-0}
        x=${x//[^0-9]/}
        y=${y//[^0-9]/}
        ((10#${x:-0} > 10#${y:-0})) && return 0
        ((10#${x:-0} < 10#${y:-0})) && return 1
    done
    return 1
}

# Check for updates (2s timeout, silent on failure)
check_update() {
    [[ "${MACRIFT_NO_UPDATE:-}" == true ]] && return 0
    local remote
    remote=$(curl -fsSL --connect-timeout 2 --max-time 2 "$MACRIFT_VERSION_URL" 2>/dev/null) || return 0
    # Only offer an update when remote is strictly NEWER — never a downgrade
    # (during development the local VERSION is ahead of main's).
    if [[ -n "$remote" ]] && _macrift_version_gt "$remote" "$MACRIFT_VERSION"; then
        MACRIFT_UPDATE="$remote"
    fi
}

# Fetch changelog for the pending update.
# Prefers GitHub compare API (precise, tag-based); falls back to recent commits.
_fetch_update_changelog() {
    local current_tag="v$MACRIFT_VERSION"
    local commits

    # Emits two prefixes for the caller to split on:
    #   - <subject>       regular changelog line
    #   M: <action>       Manual-Action trailer (rendered yellow above changelog)
    local parse_script='
import sys, json
def emit(commits):
    for c in commits:
        msg = c["commit"]["message"]
        lines = msg.splitlines()
        print("- " + lines[0])
        for line in lines[1:]:
            if line.startswith("Manual-Action:"):
                action = line.split(":", 1)[1].strip()
                if action:
                    print("M: " + action)
try:
    d = json.load(sys.stdin)
    if isinstance(d, dict):
        if "commits" not in d: sys.exit(1)
        emit(d["commits"])
    else:
        emit(d)
except Exception:
    sys.exit(1)
'

    # Precise path: requires `v<VERSION>` tag pushed for the current release
    commits=$(curl -fsSL --max-time 5 \
        "https://api.github.com/repos/${MACRIFT_REPO}/compare/${current_tag}...main" 2>/dev/null \
        | python3 -c "$parse_script" 2>/dev/null)

    if [[ -n "$commits" ]]; then
        printf '%s\n' "$commits"
        return 0
    fi

    # Fallback: last 10 commits (may include ones the user already has)
    commits=$(curl -fsSL --max-time 5 \
        "https://api.github.com/repos/${MACRIFT_REPO}/commits?per_page=10" 2>/dev/null \
        | python3 -c "$parse_script" 2>/dev/null)
    [[ -n "$commits" ]] && printf '%s\n' "$commits"
    return 1   # signals 'imprecise' (caller may note this)
}

# Download and apply update
macrift_update() {
    # Refuse to clobber a git checkout. The atomic swap below rm -rf's the install
    # dir, which would destroy .git, uncommitted work, and untracked files. If you
    # run macrift from a clone, update with git, not this command.
    if [[ -e "$MACRIFT_DIR/.git" ]]; then
        log_err "Refusing to update: $MACRIFT_DIR is a git checkout."
        log_info "Update with git instead:  git -C \"$MACRIFT_DIR\" pull --ff-only"
        return 1
    fi

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
            local manual_actions log_lines
            manual_actions=$(printf '%s\n' "$changelog" | sed -n 's/^M: //p')
            log_lines=$(printf '%s\n' "$changelog" | grep '^- ' || true)

            if [[ -n "$manual_actions" ]]; then
                log_warn "Manual action required:"
                printf '%s\n' "$manual_actions" | while IFS= read -r line; do
                    printf '  %b%s%b\n' "$YELLOW" "$line" "$RESET"
                done
                printf '\n'
            fi

            if [[ $precise -eq 1 ]]; then
                log_info "Changes since v$MACRIFT_VERSION:"
            else
                log_info "Recent commits (no tag for current version — may include ones you have):"
            fi
            printf '%s\n' "$log_lines" | while IFS= read -r line; do
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
        # Atomic swap: backup old → move new → remove backup.
        # Clear any stale .bak from a prior interrupted run first, or the backup
        # mv would nest the install inside it and the restore path would be wrong.
        rm -rf "$MACRIFT_DIR.bak"
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
        # Don't fall through to `return 0` — the caller treats success as "update
        # applied" and re-execs, so a failed download must report failure.
        log_err "Download failed"
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$tmp"
    return 0
}
