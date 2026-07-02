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
# Opt-in: allow `kind: command` manifest units (arbitrary shell) to run under
# --no-confirm. Off by default — auto-approving shell from a file is unsafe.
MACRIFT_ALLOW_COMMANDS="${MACRIFT_ALLOW_COMMANDS:-false}"
# Opt-in: let `undo` uninstall brew formulae/casks this session installed. Off by
# default — uninstalling is destructive; we never touch packages without it.
MACRIFT_ALLOW_UNINSTALL="${MACRIFT_ALLOW_UNINSTALL:-false}"
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
MACRIFT_VERSION_URL="https://raw.githubusercontent.com/${MACRIFT_REPO}/main/VERSION"
MACRIFT_VERSION=$(cat "$MACRIFT_DIR/VERSION" 2>/dev/null || echo "0")
# Short form (YY.MM) for menu title; full (YY.MM.N) for footer + update compare
if [[ "$MACRIFT_VERSION" =~ ^([0-9]+\.[0-9]+) ]]; then
    MACRIFT_VERSION_SHORT="${BASH_REMATCH[1]}"
else
    MACRIFT_VERSION_SHORT="$MACRIFT_VERSION"
fi
MACRIFT_UPDATE=""

# Shared modules — fixed order: leaves (colors, logging) before the layers using them
source "$MACRIFT_DIR/lib/theme.sh"
source "$MACRIFT_DIR/lib/log.sh"
source "$MACRIFT_DIR/lib/tui.sh"
source "$MACRIFT_DIR/lib/prompt.sh"
source "$MACRIFT_DIR/lib/files.sh"
source "$MACRIFT_DIR/lib/brew.sh"
source "$MACRIFT_DIR/lib/engine.sh"
source "$MACRIFT_DIR/lib/update.sh"
