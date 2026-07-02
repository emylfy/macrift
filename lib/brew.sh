#!/usr/bin/env bash
# macrift — Homebrew helpers

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

# Tokenize one Brewfile line into BF_KIND (formula|cask|mas|tap), BF_NAME,
# BF_ID (mas only) and BF_OPTIONAL (1 when tagged "# optional"). Returns 1 for
# comments, blanks and unrecognized lines. Installed/broken/section policy
# stays with the callers — this only parses.
_brewfile_parse_line() {
    local line="$1"
    BF_KIND="" BF_NAME="" BF_ID="" BF_OPTIONAL=0
    [[ "$line" =~ ^[[:space:]]*#.*$ || -z "${line// /}" ]] && return 1
    if [[ "$line" =~ ^brew[[:space:]]+\"([^\"]+)\" ]]; then
        BF_KIND="formula"; BF_NAME="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^cask[[:space:]]+\"([^\"]+)\" ]]; then
        BF_KIND="cask"; BF_NAME="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^mas[[:space:]]+\"([^\"]+)\".*id:[[:space:]]*([0-9]+) ]]; then
        BF_KIND="mas"; BF_NAME="${BASH_REMATCH[1]}"; BF_ID="${BASH_REMATCH[2]}"
    elif [[ "$line" =~ ^tap[[:space:]]+\"([^\"]+)\" ]]; then
        BF_KIND="tap"; BF_NAME="${BASH_REMATCH[1]}"
    else
        return 1
    fi
    [[ "$line" == *"# optional"* ]] && BF_OPTIONAL=1
    return 0
}

# Emit installed packages as "name<TAB>source<TAB>id" lines: top-level brew
# formulae (leaves), casks, and Mac App Store apps (id last).
_capture_brew_list() {
    if command -v brew &>/dev/null; then
        brew leaves 2>/dev/null      | while IFS= read -r n; do [[ -n "$n" ]] && printf '%s\tformula\t\n' "$n"; done
        brew list --cask 2>/dev/null | while IFS= read -r n; do [[ -n "$n" ]] && printf '%s\tcask\t\n' "$n"; done
    fi
    if command -v mas &>/dev/null; then
        mas list 2>/dev/null | awk 'NF{id=$1; $1=""; sub(/^ +/,""); sub(/ \([^)]*\)$/,""); print $0"\tmas\t"id}'
    fi
}

# Ensure the mas CLI is present (offer a brew install). Lives here, not in
# apps/appstore.sh, because _manifest_apply_brew needs it when `macrift apply`
# runs as a bare subcommand with no menu files sourced.
_ensure_mas() {
    if command -v mas &>/dev/null; then
        return 0
    fi
    log_warn "mas (Mac App Store CLI) not found"
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install mas"
        return 1
    fi
    if confirm "Install mas via Homebrew?"; then
        if ! brew install mas; then
            log_err "Failed to install mas"
            log_hint "try: brew install mas"
            return 1
        fi
        _journal_append_brew "mas" "formula" "" "absent"
        return 0
    fi
    return 1
}
