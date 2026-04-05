#!/usr/bin/env bash
# macrift — shared utilities

set -euo pipefail

#
ARCH=$(uname -m)

#
MACRIFT_DRY_RUN="${MACRIFT_DRY_RUN:-false}"
MACRIFT_NO_CONFIRM="${MACRIFT_NO_CONFIRM:-false}"
MACRIFT_LOG="${MACRIFT_LOG:-}"

#
_macrift_cleanup() {
    printf "\033[?25h" 2>/dev/null
}
trap _macrift_cleanup EXIT
trap 'exit 130' INT TERM

# Strip ANSI escape codes and append to log file
_log_file() {
    [[ -z "$MACRIFT_LOG" ]] && return
    printf "%s  %s\n" "$(date '+%H:%M:%S')" "$1" >> "$MACRIFT_LOG"
}

#
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
        local old_stty response=""
        old_stty=$(stty -g </dev/tty 2>/dev/null) || true
        stty raw -echo min 0 time 2 </dev/tty 2>/dev/null
        printf '\033]11;?\a' > /dev/tty 2>/dev/null
        response=$(dd bs=1 count=30 </dev/tty 2>/dev/null) || true
        # Drain any leftover bytes from terminal response
        dd bs=1 count=64 </dev/tty >/dev/null 2>&1 || true
        stty "$old_stty" </dev/tty 2>/dev/null
        if [[ "$response" =~ rgb:([0-9a-fA-F]+)/([0-9a-fA-F]+)/([0-9a-fA-F]+) ]]; then
            local r=$((16#${BASH_REMATCH[1]:0:2}))
            local g=$((16#${BASH_REMATCH[2]:0:2}))
            local b=$((16#${BASH_REMATCH[3]:0:2}))
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
        SCcf)    echo "current folder" ;;
        Nlsv)    echo "list" ;;
        PfHm)    echo "home" ;;
        file://*) echo "$HOME/" ;;
        default) echo "not set" ;;
        *)       echo "$1" ;;
    esac
}

#
set_title() { printf "\033]0;%s\007" "$1"; }

MACRIFT_CRUMBS=()
crumb_push() { MACRIFT_CRUMBS+=("$1"); }
crumb_pop()  { local _i=$(( ${#MACRIFT_CRUMBS[@]} - 1 )); [[ $_i -ge 0 ]] && unset "MACRIFT_CRUMBS[$_i]"; }

spinner() {
    local pid=$1 msg="${2:-}"
    local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    tput civis 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r  %b%s%b  %s' "$CYAN" "${frames:i%10:1}" "$RESET" "$msg" >&2
        sleep 0.08
        ((i++))
    done
    printf '\r\033[K' >&2
    tput cnorm 2>/dev/null || true
}

run_with_spinner() {
    local msg="$1"
    shift
    "$@" &>/dev/null &
    spinner $! "$msg"
    wait $! 2>/dev/null
    return $?
}

log_info()  { printf '  %b›%b  %s\n' "${CYAN}" "${RESET}" "$1"; _log_file "[info] $1"; }
log_ok()    { printf '  %b✓%b  %s\n' "${GREEN}" "${RESET}" "$1"; _log_file "[  ok] $1"; }
log_err()   { printf '  %b✗%b  %s\n' "${RED}" "${RESET}" "$1"; _log_file "[ err] $1"; }
log_warn()  { printf '  %b!%b  %s\n' "${YELLOW}" "${RESET}" "$1"; _log_file "[warn] $1"; }
log_skip()  { printf '  %b-%b  %s\n' "${DIM}" "${RESET}" "$1"; _log_file "[skip] $1"; }

# 

# 
show_menu() {
    local title="$1"
    shift
    local items=("$@")
    local count=${#items[@]}
    local last_idx=$((count - 1))

    # Build selectable items: sel_nums[i]=choice number, sel_labels[i]=label
    local sel_nums=() sel_labels=()
    local i num=0
    for ((i=0; i<last_idx; i++)); do
        [[ "${items[$i]}" == "---" ]] && continue
        num=$((num + 1))
        sel_nums+=("$num")
        sel_labels+=("${items[$i]}")
    done
    sel_nums+=(0)
    sel_labels+=("${items[$last_idx]}")
    local sel_total=${#sel_nums[@]}

    # Box dimensions
    local max_len=0
    for ((i=0; i<count; i++)); do
        [[ "${items[$i]}" == "---" ]] && continue
        [[ ${#items[$i]} -gt $max_len ]] && max_len=${#items[$i]}
    done
    local real_count=$num
    local no_nums="${MENU_NO_NUMBERS:-false}"
    local num_w=${#real_count}
    local num_pad=3
    if [[ "$no_nums" == true ]]; then num_w=0; num_pad=2; fi
    local inner_w=$((2 + num_w + num_pad + max_len + 2))
    local title_min=$((${#title} + 5))
    [[ $title_min -gt $inner_w ]] && inner_w=$title_min
    local top_fill=$((inner_w - ${#title} - 3))

    local BP="${BOLD}${GRAY}" R="${RESET}"
    local total_lines=$((last_idx + 8))
    [[ "$no_nums" == true ]] && total_lines=$((total_lines - 1))
    local sel=0 first_draw=true

    stty -echo 2>/dev/null
    printf "\033[?25l" >&2

    while true; do
        printf "\033[?2026h" >&2
        if $first_draw; then
            first_draw=false
        else
            printf "\033[%dA\r" "$total_lines" >&2
        fi

        printf "\033[K\n" >&2
        printf '  %b╭─ %b%s%b ' "$BP" "${R}${BOLD}${ICE}" "$title" "${R}${BP}" >&2
        printf '─%.0s' $(seq 1 $top_fill) >&2
        printf '╮%b\033[K\n' "$R" >&2
        printf '  %b│%b%*s%b│%b\033[K\n' "$BP" "$R" "$inner_w" "" "$BP" "$R" >&2

        local num=0 sel_idx=0
        for ((i=0; i<last_idx; i++)); do
            if [[ "${items[$i]}" == "---" ]]; then
                printf '  %b│%b%*s%b│%b\033[K\n' "$BP" "$R" "$inner_w" "" "$BP" "$R" >&2
                continue
            fi
            num=$((num + 1))
            local vis=$((2 + num_w + num_pad + ${#items[$i]}))
            local pad=$((inner_w - vis))
            if [[ "$no_nums" == true ]]; then
                if [[ $sel_idx -eq $sel ]]; then
                    printf '  %b│%b  %b› %s%b%*s%b│%b\033[K\n' \
                        "$BP" "$R" "${BOLD}${ICE}" "${items[$i]}" "$R" "$pad" "" "$BP" "$R" >&2
                else
                    printf '  %b│%b  %b›%b %s%*s%b│%b\033[K\n' \
                        "$BP" "$R" "$DIM" "$R" "${items[$i]}" "$pad" "" "$BP" "$R" >&2
                fi
            else
                if [[ $sel_idx -eq $sel ]]; then
                    printf '  %b│%b  %b%*d › %s%b%*s%b│%b\033[K\n' \
                        "$BP" "$R" "${BOLD}${ICE}" "$num_w" "$num" "${items[$i]}" "$R" "$pad" "" "$BP" "$R" >&2
                else
                    printf '  %b│%b  %b%*d%b %b›%b %s%*s%b│%b\033[K\n' \
                        "$BP" "$R" "$CYAN" "$num_w" "$num" "$R" "$DIM" "$R" "${items[$i]}" "$pad" "" "$BP" "$R" >&2
                fi
            fi
            ((sel_idx++))
        done

        [[ "$no_nums" != true ]] && printf '  %b│%b%*s%b│%b\033[K\n' "$BP" "$R" "$inner_w" "" "$BP" "$R" >&2
        local vis=$((2 + num_w + num_pad + ${#items[$last_idx]}))
        local pad=$((inner_w - vis))
        if [[ "$no_nums" == true ]]; then
            if [[ $sel_idx -eq $sel ]]; then
                printf '  %b│%b  %b› %s%b%*s%b│%b\033[K\n' \
                    "$BP" "$R" "${BOLD}${ICE}" "${items[$last_idx]}" "$R" "$pad" "" "$BP" "$R" >&2
            else
                printf '  %b│%b  %b›%b %s%*s%b│%b\033[K\n' \
                    "$BP" "$R" "$DIM" "$R" "${items[$last_idx]}" "$pad" "" "$BP" "$R" >&2
            fi
        else
            if [[ $sel_idx -eq $sel ]]; then
                printf '  %b│%b  %b%*d › %s%b%*s%b│%b\033[K\n' \
                    "$BP" "$R" "${BOLD}${ICE}" "$num_w" 0 "${items[$last_idx]}" "$R" "$pad" "" "$BP" "$R" >&2
            else
                printf '  %b│%b  %b%*d › %s%b%*s%b│%b\033[K\n' \
                    "$BP" "$R" "$DIM" "$num_w" 0 "${items[$last_idx]}" "$R" "$pad" "" "$BP" "$R" >&2
            fi
        fi

        printf '  %b│%b%*s%b│%b\033[K\n' "$BP" "$R" "$inner_w" "" "$BP" "$R" >&2
        printf '  %b╰' "$BP" >&2
        printf '─%.0s' $(seq 1 $inner_w) >&2
        printf '╯%b\033[K\n' "$R" >&2
        local _nav_hint="↑↓ navigate  enter/→ select"
        [[ ${#MACRIFT_CRUMBS[@]} -gt 1 ]] && _nav_hint+="  ← back"
        printf '  %b%s%b\033[K\n' "$DIM" "$_nav_hint" "$R" >&2
        printf "\033[?2026l" >&2

        local key=""
        IFS= read -rsn1 key < /dev/tty || true

        if [[ "$key" == $'\x1b' ]]; then
            local ansi=""
            read -rsn2 -t 1 ansi < /dev/tty || true
            case "$ansi" in
                '[A') ((sel > 0)) && ((sel--)) ;;
                '[B') ((sel < sel_total - 1)) && ((sel++)) ;;
                '[C') stty echo 2>/dev/null; printf "\033[?25h" >&2; echo "${sel_nums[$sel]}"; return ;;
                '[D')
                    if [[ ${#MACRIFT_CRUMBS[@]} -gt 1 ]]; then
                        stty echo 2>/dev/null; printf "\033[?25h" >&2
                        echo "0"
                        return
                    fi
                    ;;
            esac
        elif [[ "$key" == "" ]]; then
            stty echo 2>/dev/null; printf "\033[?25h" >&2
            echo "${sel_nums[$sel]}"
            return
        elif [[ "$no_nums" != true && "$key" =~ ^[0-9]$ ]]; then
            printf "%s\n" "$key" >&2
            stty echo 2>/dev/null; printf "\033[?25h" >&2
            echo "$key"
            return
        fi
    done
}

# 
# Usage: show_info_box "Title" "line1" "" "line3" ...
# Empty strings render as blank lines inside box
show_info_box() {
    local title="$1"
    shift
    local lines=("$@")
    local count=${#lines[@]}

    local max_len=0
    local i
    for ((i=0; i<count; i++)); do
        if [[ ${#lines[$i]} -gt $max_len ]]; then
            max_len=${#lines[$i]}
        fi
    done

    local inner_w=$((max_len + 4))
    local title_min=$((${#title} + 5))
    if [[ $title_min -gt $inner_w ]]; then
        inner_w=$title_min
    fi

    local top_fill=$((inner_w - ${#title} - 3))

    local BP="${BOLD}${GRAY}"
    local R="${RESET}"

    printf "\n" >&2
    printf '  %b╭─ %b%s%b ' "$BP" "${R}${BOLD}${ICE}" "$title" "${R}${BP}" >&2
    printf '─%.0s' $(seq 1 $top_fill) >&2
    printf '╮%b\n' "$R" >&2

    # Top padding
    printf '  %b│%b%*s%b│%b\n' "$BP" "$R" "$inner_w" "" "$BP" "$R" >&2

    for ((i=0; i<count; i++)); do
        local line="${lines[$i]}"
        local pad=$((inner_w - ${#line} - 2))
        printf '  %b│%b  %s%*s%b│%b\n' "$BP" "$R" "$line" "$pad" "" "$BP" "$R" >&2
    done

    # Bottom padding
    printf '  %b│%b%*s%b│%b\n' "$BP" "$R" "$inner_w" "" "$BP" "$R" >&2

    printf '  %b╰' "$BP" >&2
    printf '─%.0s' $(seq 1 $inner_w) >&2
    printf '╯%b\n' "$R" >&2
}

# 
# Usage: selected=$(show_multiselect "Title" "item1" "item2" ...)
# Returns selected items one per line to stdout
# All items selected by default
show_multiselect() {
    local title="$1"
    shift
    local items=("$@")
    local count=${#items[@]}
    local total=$((count + 1))  # items + Back
    local cursor=0
    declare -a selected
    local i
    for ((i=0; i<count; i++)); do
        if [[ "${items[$i]}" == "---" ]]; then
            selected[i]="-"
        else
            selected[i]="1"
        fi
    done
    # Ensure cursor starts on a real item
    while [[ $cursor -lt $count && "${items[$cursor]}" == "---" ]]; do
        cursor=$((cursor + 1))
    done

    # Calculate box width: "  › [*] item  " = 8 + item_len + 2
    local max_len=0
    for ((i=0; i<count; i++)); do
        [[ "${items[$i]}" == "---" ]] && continue
        if [[ ${#items[$i]} -gt $max_len ]]; then
            max_len=${#items[$i]}
        fi
    done
    local inner_w=$((8 + max_len + 2))
    local back_min=12  # "    ‹ Back" + 2
    if [[ $back_min -gt $inner_w ]]; then inner_w=$back_min; fi
    local title_min=$((${#title} + 5))
    if [[ $title_min -gt $inner_w ]]; then inner_w=$title_min; fi
    local top_fill=$((inner_w - ${#title} - 3))

    # Hide cursor & disable echo
    stty -echo 2>/dev/null
    printf "\033[?25l" >&2

    local first_draw=true
    local redraw_lines=$((count + 8))

    while true; do
        printf "\033[?2026h" >&2
        if [[ "$first_draw" == true ]]; then
            first_draw=false
        else
            printf "\033[%dA\r" "$redraw_lines" >&2
        fi

        local BP="${BOLD}${GRAY}"
        local R="${RESET}"
        printf "\033[K\n" >&2
        printf '  %b╭─ %b%s%b ' "$BP" "${R}${BOLD}${ICE}" "$title" "${R}${BP}" >&2
        printf '─%.0s' $(seq 1 $top_fill) >&2
        printf '╮%b\n' "$R" >&2
        # │ (empty) │
        printf '  %b│%b%*s%b│%b\n' "$BP" "$R" "$inner_w" "" "$BP" "$R" >&2

        # │ items │
        for ((i=0; i<count; i++)); do
            if [[ "${items[$i]}" == "---" ]]; then
                printf '  %b│%b%*s%b│%b\n' "$BP" "$R" "$inner_w" "" "$BP" "$R" >&2
                continue
            fi
            local pad=$((inner_w - 8 - ${#items[$i]}))
            if [[ $i -eq $cursor ]]; then
                if [[ "${selected[i]}" == "1" ]]; then
                    printf '  %b│%b  %b›%b %b[*]%b %s%*s%b│%b\n' "$BP" "$R" "$CYAN" "$R" "$GREEN" "$R" "${items[$i]}" "$pad" "" "$BP" "$R" >&2
                else
                    printf '  %b│%b  %b›%b %b[ ]%b %s%*s%b│%b\n' "$BP" "$R" "$CYAN" "$R" "$DIM" "$R" "${items[$i]}" "$pad" "" "$BP" "$R" >&2
                fi
            else
                if [[ "${selected[i]}" == "1" ]]; then
                    printf '  %b│%b    %b[*]%b %s%*s%b│%b\n' "$BP" "$R" "$GREEN" "$R" "${items[$i]}" "$pad" "" "$BP" "$R" >&2
                else
                    printf '  %b│%b    %b[ ]%b %s%*s%b│%b\n' "$BP" "$R" "$DIM" "$R" "${items[$i]}" "$pad" "" "$BP" "$R" >&2
                fi
            fi
        done

        # │ (empty) │
        printf '  %b│%b%*s%b│%b\n' "$BP" "$R" "$inner_w" "" "$BP" "$R" >&2
        # │ ‹ Back  │
        local back_pad=$((inner_w - 10))
        if [[ $cursor -eq $count ]]; then
            printf '  %b│%b  %b›%b %b‹ Back%b%*s%b│%b\n' "$BP" "$R" "$CYAN" "$R" "$DIM" "$R" "$back_pad" "" "$BP" "$R" >&2
        else
            printf '  %b│%b    %b‹ Back%b%*s%b│%b\n' "$BP" "$R" "$DIM" "$R" "$back_pad" "" "$BP" "$R" >&2
        fi
        # │ (empty) │
        printf '  %b│%b%*s%b│%b\n' "$BP" "$R" "$inner_w" "" "$BP" "$R" >&2
        # ╰─────────╯
        printf '  %b╰' "$BP" >&2
        printf '─%.0s' $(seq 1 $inner_w) >&2
        printf '╯%b\n' "$R" >&2
        # hint below box
        local _ms_hint="${MULTISELECT_HINT:-↑↓ move  space toggle  a all  enter confirm}"
        printf '  %b%s%b\033[K\n' "$DIM" "$_ms_hint" "$R" >&2
        printf "\033[?2026l" >&2

        # Read keypress
        IFS= read -rsn1 key < /dev/tty || true

        if [[ "$key" == $'\x1b' ]]; then
            local seq=""
            read -rsn2 -t 1 seq < /dev/tty || true
            if [[ "$seq" == '[A' ]]; then
                if [[ $cursor -gt 0 ]]; then
                    cursor=$((cursor - 1))
                    while [[ $cursor -gt 0 && $cursor -lt $count && "${items[$cursor]}" == "---" ]]; do
                        cursor=$((cursor - 1))
                    done
                fi
            elif [[ "$seq" == '[B' ]]; then
                if [[ $cursor -lt $((total - 1)) ]]; then
                    cursor=$((cursor + 1))
                    while [[ $cursor -lt $count && "${items[$cursor]}" == "---" ]]; do
                        cursor=$((cursor + 1))
                    done
                fi
            elif [[ "$seq" == '[C' ]]; then
                if [[ $cursor -eq $count ]]; then
                    stty echo 2>/dev/null; printf "\033[?25h" >&2
                    return 0
                fi
                break
            elif [[ "$seq" == '[D' ]]; then
                stty echo 2>/dev/null; printf "\033[?25h" >&2
                return 0
            fi
        elif [[ "$key" == ' ' ]]; then
            if [[ $cursor -lt $count ]]; then
                if [[ "${selected[cursor]}" == "1" ]]; then
                    selected[cursor]="0"
                else
                    selected[cursor]="1"
                fi
            fi
        elif [[ "$key" == 'a' || "$key" == 'A' ]]; then
            # Toggle all non-separator items
            local all_on=true
            for ((i=0; i<count; i++)); do
                [[ "${items[$i]}" == "---" ]] && continue
                if [[ "${selected[$i]}" == "0" ]]; then
                    all_on=false
                    break
                fi
            done
            local val="1"
            if $all_on; then val="0"; fi
            for ((i=0; i<count; i++)); do
                [[ "${items[$i]}" == "---" ]] && continue
                selected[i]="$val"
            done
        elif [[ "$key" == '' ]]; then
            if [[ $cursor -eq $count ]]; then
                stty echo 2>/dev/null; printf "\033[?25h" >&2
                return 0
            fi
            break
        fi
    done

    # Show cursor & restore echo
    stty echo 2>/dev/null
    printf "\033[?25h" >&2

    # Output selected items to stdout (skip separators)
    for ((i=0; i<count; i++)); do
        [[ "${items[$i]}" == "---" ]] && continue
        if [[ "${selected[i]}" == "1" ]]; then
            echo "${items[$i]}"
        fi
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
wait_retry() {
    printf '  %bpress enter to retry%b ' "$DIM" "$RESET"
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

#
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

# 
require_sudo() {
    if ! sudo -n true 2>/dev/null; then
        printf '\n  %bSudo access needed for system tweaks%b\n' "$YELLOW" "$RESET"
        sudo -v -p "  Password: "
    fi
}

# 
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
            if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
                if [[ "$ARCH" == "arm64" && -f /opt/homebrew/bin/brew ]]; then
                    eval "$(/opt/homebrew/bin/brew shellenv)"
                elif [[ -f /usr/local/bin/brew ]]; then
                    eval "$(/usr/local/bin/brew shellenv)"
                fi
                log_ok "Homebrew installed"
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

    if [[ "$type" == "cask" ]]; then
        if brew list --cask "$package" &>/dev/null; then
            log_skip "$package already installed"
            return 0
        fi
        log_info "Installing $package..."
        if brew install --cask "$package"; then
            log_ok "$package installed"
        else
            log_err "Failed to install $package"
            return 1
        fi
    else
        if brew list "$package" &>/dev/null; then
            log_skip "$package already installed"
            return 0
        fi
        log_info "Installing $package..."
        if brew install "$package"; then
            log_ok "$package installed"
        else
            log_err "Failed to install $package"
            return 1
        fi
    fi
}

# 
# Stores pending changes for review before applying
declare -a AUDIT_ENTRIES=()

audit_reset() {
    AUDIT_ENTRIES=()
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

# Queue a sudo defaults write for audit
audit_default_sudo() {
    local domain="$1"
    local key="$2"
    local type="$3"
    local new_value="$4"
    local label="${5:-$key}"

    local current
    current=$(sudo defaults read "$domain" "$key" 2>/dev/null || echo "default")

    if [[ "$type" == "-bool" ]]; then
        [[ "$current" == "1" ]] && current="true"
        [[ "$current" == "0" ]] && current="false"
    fi

    AUDIT_ENTRIES+=("${label}|${current}|${new_value}|${domain}|${key}|${type}|sudo")
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
            local flag="$key"
            [[ "$new_val" == "false" ]] && flag="hidden"
            if chflags "$flag" ~/Library 2>/dev/null; then
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
            local nvram_val="%01"
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

        if [[ "${sudo_flag:-}" == "sudo" ]]; then
            if sudo defaults write "$domain" "$key" "$type" "$new_val" 2>/dev/null; then
                log_ok "$label → $friendly"
                applied=$((applied + 1))
                MACRIFT_CHANGED_DOMAINS+=("$domain")
            else
                log_err "Failed: $label → $friendly"
                failed=$((failed + 1))
            fi
        else
            if defaults write "$domain" "$key" "$type" "$new_val" 2>/dev/null; then
                log_ok "$label → $friendly"
                applied=$((applied + 1))
                MACRIFT_CHANGED_DOMAINS+=("$domain")
            else
                log_warn "$label needs sudo ($domain is protected)"
                if sudo defaults write "$domain" "$key" "$type" "$new_val" 2>/dev/null; then
                    log_ok "$label → $friendly"
                    applied=$((applied + 1))
                    MACRIFT_CHANGED_DOMAINS+=("$domain")
                else
                    log_err "Failed: $label → $friendly"
                    failed=$((failed + 1))
                fi
            fi
        fi
    done

    local summary="${applied} applied"
    [[ $skipped -gt 0 ]] && summary+=", ${skipped} skipped"
    [[ $failed -gt 0 ]]  && summary+=", ${failed} failed"
    printf '\n'
    log_info "$summary"

    audit_reset
}

# Reset queued defaults (delete keys to restore system defaults)
# RESET_ENTRIES format: same as AUDIT_ENTRIES
declare -a RESET_ENTRIES=()

apply_reset_defaults() {
    local reset=0 failed=0

    for entry in "${RESET_ENTRIES[@]}"; do
        IFS='|' read -r label current new_val domain key type sudo_flag <<< "$entry"

        if [[ "${sudo_flag:-}" == "sudo" ]]; then
            if sudo defaults delete "$domain" "$key" 2>/dev/null; then
                log_ok "$label → system default"
                ((reset++))
                MACRIFT_CHANGED_DOMAINS+=("$domain")
            else
                log_err "Failed to reset: $label"
                failed=$((failed + 1))
            fi
        else
            if defaults delete "$domain" "$key" 2>/dev/null; then
                log_ok "$label → system default"
                ((reset++))
                MACRIFT_CHANGED_DOMAINS+=("$domain")
            else
                log_warn "$label needs sudo ($domain is protected)"
                if sudo defaults delete "$domain" "$key" 2>/dev/null; then
                    log_ok "$label → system default"
                    ((reset++))
                    MACRIFT_CHANGED_DOMAINS+=("$domain")
                else
                    log_err "Failed to reset: $label"
                    failed=$((failed + 1))
                fi
            fi
        fi
    done

    local summary="${reset} reset"
    if [[ $failed -gt 0 ]]; then summary+=", ${failed} failed"; fi
    printf '\n'
    log_info "$summary"

    RESET_ENTRIES=()
}

#
backup_file() {
    local target="$1"
    if [[ -f "$target" ]]; then
        local backup="${target}.bak"
        cp "$target" "$backup"
        log_info "Backed up to ${backup##*/}"
    fi
}

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
MACRIFT_REPO_TAR="https://github.com/emylfy/macrift/archive/main.tar.gz"
MACRIFT_VERSION_URL="https://raw.githubusercontent.com/emylfy/macrift/main/VERSION"
MACRIFT_VERSION=$(cat "$MACRIFT_DIR/VERSION" 2>/dev/null || echo "0")
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

# Download and apply update (git pull or tarball re-download)
macrift_update() {
    if [[ -d "$MACRIFT_DIR/.git" ]] && command -v git &>/dev/null; then
        log_info "Updating via git..."
        if git -C "$MACRIFT_DIR" pull --rebase --autostash; then
            log_ok "Updated to $(cat "$MACRIFT_DIR/VERSION" 2>/dev/null || echo 'latest')"
        else
            log_err "git pull failed"
            return 1
        fi
    else
        log_info "Downloading latest version..."
        local tmp
        tmp="$(mktemp -d)"
        if curl -fsSL "$MACRIFT_REPO_TAR" | tar -xz -C "$tmp"; then
            rm -rf "$MACRIFT_DIR"
            mv "$tmp/macrift-main" "$MACRIFT_DIR"
            rm -rf "$tmp"
            chmod +x "$MACRIFT_DIR/macrift.sh"
            find "$MACRIFT_DIR" -name "*.sh" -exec chmod +x {} +
            log_ok "Updated to $(cat "$MACRIFT_DIR/VERSION" 2>/dev/null || echo 'latest')"
        else
            log_err "Download failed"
            rm -rf "$tmp"
            return 1
        fi
    fi
}
