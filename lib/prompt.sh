#!/usr/bin/env bash
# macrift — interactive prompts

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
