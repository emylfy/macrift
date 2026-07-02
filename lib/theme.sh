#!/usr/bin/env bash
# macrift — terminal theme detection + ANSI palette

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
