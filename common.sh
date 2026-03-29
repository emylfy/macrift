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
    cleanup_sudo
    rm -f /tmp/macrift_* 2>/dev/null || true
    tput cnorm 2>/dev/null || true  # restore cursor
}
trap _macrift_cleanup EXIT INT TERM

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
GRAY='\033[38;5;240m'
CYAN='\033[38;5;39m'
ICE='\033[38;5;195m'

# 
set_title() { printf "\033]0;%s\007" "$1"; }

#
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
    local num_w=${#real_count}
    local inner_w=$((2 + num_w + 3 + max_len + 2))
    local title_min=$((${#title} + 5))
    [[ $title_min -gt $inner_w ]] && inner_w=$title_min
    local top_fill=$((inner_w - ${#title} - 3))

    local BP="${BOLD}${GRAY}" R="${RESET}"
    local total_lines=$((last_idx + 8))
    local sel=0 first_draw=true

    printf "\033[?25l" >&2

    while true; do
        if $first_draw; then
            first_draw=false
        else
            printf "\033[%dA\r" "$total_lines" >&2
        fi

        printf "\n" >&2
        printf '  %b╭─ %b%s%b ' "$BP" "${R}${BOLD}${ICE}" "$title" "${R}${BP}" >&2
        printf '─%.0s' $(seq 1 $top_fill) >&2
        printf '╮%b\n' "$R" >&2
        printf '  %b│%b%*s%b│%b\n' "$BP" "$R" "$inner_w" "" "$BP" "$R" >&2

        local num=0 sel_idx=0
        for ((i=0; i<last_idx; i++)); do
            if [[ "${items[$i]}" == "---" ]]; then
                printf '  %b│%b%*s%b│%b\n' "$BP" "$R" "$inner_w" "" "$BP" "$R" >&2
                continue
            fi
            num=$((num + 1))
            local vis=$((2 + num_w + 3 + ${#items[$i]}))
            local pad=$((inner_w - vis))
            if [[ $sel_idx -eq $sel ]]; then
                printf '  %b│%b  %b%*d › %s%b%*s%b│%b\n' \
                    "$BP" "$R" "${BOLD}${ICE}" "$num_w" "$num" "${items[$i]}" "$R" "$pad" "" "$BP" "$R" >&2
            else
                printf '  %b│%b  %b%*d%b %b›%b %s%*s%b│%b\n' \
                    "$BP" "$R" "$CYAN" "$num_w" "$num" "$R" "$DIM" "$R" "${items[$i]}" "$pad" "" "$BP" "$R" >&2
            fi
            ((sel_idx++))
        done

        printf '  %b│%b%*s%b│%b\n' "$BP" "$R" "$inner_w" "" "$BP" "$R" >&2
        local vis=$((2 + num_w + 3 + ${#items[$last_idx]}))
        local pad=$((inner_w - vis))
        if [[ $sel_idx -eq $sel ]]; then
            printf '  %b│%b  %b%*d › %s%b%*s%b│%b\n' \
                "$BP" "$R" "${BOLD}${ICE}" "$num_w" 0 "${items[$last_idx]}" "$R" "$pad" "" "$BP" "$R" >&2
        else
            printf '  %b│%b  %b%*d › %s%b%*s%b│%b\n' \
                "$BP" "$R" "$DIM" "$num_w" 0 "${items[$last_idx]}" "$R" "$pad" "" "$BP" "$R" >&2
        fi

        printf '  %b│%b%*s%b│%b\n' "$BP" "$R" "$inner_w" "" "$BP" "$R" >&2
        printf '  %b╰' "$BP" >&2
        printf '─%.0s' $(seq 1 $inner_w) >&2
        printf '╯%b\n' "$R" >&2
        printf "\n" >&2

        local key=""
        IFS= read -rsn1 key < /dev/tty || true

        if [[ "$key" == $'\x1b' ]]; then
            local ansi=""
            read -rsn2 -t 1 ansi < /dev/tty || true
            case "$ansi" in
                '[A') ((sel > 0)) && ((sel--)) ;;
                '[B') ((sel < sel_total - 1)) && ((sel++)) ;;
                '[C'|'[M') printf "\033[?25h" >&2; echo "${sel_nums[$sel]}"; return ;;
                '[D') printf "‹\n" >&2; printf "\033[?25h" >&2; echo "0"; return ;;
            esac
        elif [[ "$key" == "" ]]; then
            printf "\033[?25h" >&2
            echo "${sel_nums[$sel]}"
            return
        elif [[ "$key" =~ ^[0-9]$ ]]; then
            printf "%s\n" "$key" >&2
            printf "\033[?25h" >&2
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

    for ((i=0; i<count; i++)); do
        local line="${lines[$i]}"
        local pad=$((inner_w - ${#line} - 2))
        printf '  %b│%b  %s%*s%b│%b\n' "$BP" "$R" "$line" "$pad" "" "$BP" "$R" >&2
    done

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
        selected[i]="1"
    done

    # Calculate box width: "  › [*] item  " = 8 + item_len + 2
    local max_len=0
    for ((i=0; i<count; i++)); do
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

    # Hide cursor
    printf "\033[?25l" >&2

    local first_draw=true
    # lines: \n + top + empty + items + empty + back + empty + bottom + hint = count + 8
    local redraw_lines=$((count + 8))

    while true; do
        if [[ "$first_draw" == true ]]; then
            first_draw=false
        else
            printf "\033[%dA\033[J" "$redraw_lines" >&2
        fi

        local BP="${BOLD}${GRAY}"
        local R="${RESET}"

        printf "\n" >&2
        # ╭─ Title ───╮
        printf '  %b╭─ %b%s%b ' "$BP" "${R}${BOLD}${ICE}" "$title" "${R}${BP}" >&2
        printf '─%.0s' $(seq 1 $top_fill) >&2
        printf '╮%b\n' "$R" >&2
        # │ (empty) │
        printf '  %b│%b%*s%b│%b\n' "$BP" "$R" "$inner_w" "" "$BP" "$R" >&2

        # │ items │
        for ((i=0; i<count; i++)); do
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
        printf '  %b↑↓ move  space toggle  a all  enter confirm%b\n' "$DIM" "$R" >&2

        # Read keypress
        IFS= read -rsn1 key < /dev/tty || true

        if [[ "$key" == $'\x1b' ]]; then
            local seq=""
            read -rsn2 -t 1 seq < /dev/tty || true
            if [[ "$seq" == '[A' ]]; then
                if [[ $cursor -gt 0 ]]; then
                    cursor=$((cursor - 1))
                fi
            elif [[ "$seq" == '[B' ]]; then
                if [[ $cursor -lt $((total - 1)) ]]; then
                    cursor=$((cursor + 1))
                fi
            elif [[ "$seq" == '[D' ]]; then
                printf "\033[?25h" >&2
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
            # Toggle all non-installed items
            local all_on=true
            for ((i=0; i<count; i++)); do
                if [[ "${selected[$i]}" == "0" ]]; then
                    all_on=false
                    break
                fi
            done
            local val="1"
            if $all_on; then val="0"; fi
            for ((i=0; i<count; i++)); do selected[i]="$val"; done
        elif [[ "$key" == '' ]]; then
            if [[ $cursor -eq $count ]]; then
                printf "\033[?25h" >&2
                return 0
            fi
            break
        fi
    done

    # Show cursor
    printf "\033[?25h" >&2

    # Output selected items to stdout
    for ((i=0; i<count; i++)); do
        if [[ "${selected[i]}" == "1" ]]; then
            echo "${items[$i]}"
        fi
    done
}

# Reusable prompts
wait_enter() { printf '\n  %bpress enter to continue%b ' "$DIM" "$RESET"; read -r < /dev/tty || true; }
wait_retry()  { printf '  %bpress enter to retry%b ' "$DIM" "$RESET"; read -r < /dev/tty || true; }
prompt_path() { printf '  %bpath:%b ' "$CYAN" "$RESET"; }

#
confirm() {
    local msg="${1:-Continue?}"
    if [[ "$MACRIFT_NO_CONFIRM" == true ]]; then
        printf '  %b%s%b %b[auto: y]%b\n' "$YELLOW" "$msg" "$RESET" "$DIM" "$RESET"
        _log_file "[auto] $msg → y"
        return 0
    fi
    printf '  %b%s%b %b[y/n]%b ' "$YELLOW" "$msg" "$RESET" "$DIM" "$RESET"
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

# 
require_sudo() {
    if ! sudo -n true 2>/dev/null; then
        printf '\n  %bSudo access needed for system tweaks%b\n' "$YELLOW" "$RESET"
        sudo -v
    fi
    # keep-alive: update existing sudo timestamp in background
    while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null &
    SUDO_KEEPALIVE_PID=$!
}

cleanup_sudo() {
    if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
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

# Apply all queued defaults writes
apply_audited_defaults() {
    for entry in "${AUDIT_ENTRIES[@]}"; do
        IFS='|' read -r label current new_val domain key type sudo_flag <<< "$entry"

        if [[ "$current" == "$new_val" ]]; then
            continue
        fi

        if [[ "${sudo_flag:-}" == "sudo" ]]; then
            if sudo defaults write "$domain" "$key" "$type" "$new_val" 2>/dev/null; then
                log_ok "$label → $new_val"
            else
                log_err "Failed: $label"
            fi
        else
            if defaults write "$domain" "$key" "$type" "$new_val" 2>/dev/null; then
                log_ok "$label → $new_val"
            else
                log_err "Failed: $label"
            fi
        fi
    done

    audit_reset
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
    local remote
    remote=$(curl -fsSL --connect-timeout 2 --max-time 2 "$MACRIFT_VERSION_URL" 2>/dev/null) || return 0
    if [[ -n "$remote" && "$remote" != "$MACRIFT_VERSION" ]]; then
        MACRIFT_UPDATE="$remote"
    fi
}

# Download and apply update (git pull or tarball re-download)
macrift_update() {
    if [[ -d "$MACRIFT_DIR/.git" ]]; then
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
