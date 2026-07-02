#!/usr/bin/env bash
# macrift — logging + value formatting

# Strip ANSI escape codes and append to log file
_log_file() {
    [[ -z "$MACRIFT_LOG" ]] && return
    printf "%s  %s\n" "$(date '+%H:%M:%S')" "$1" >> "$MACRIFT_LOG"
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
