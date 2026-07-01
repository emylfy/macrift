#!/usr/bin/env bash
# macrift — Homebrew bundle installer

# Speed up brew: skip auto-update, analytics, cleanup, dependents check
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1

# Strip drag-and-drop quotes and trailing whitespace from a path
_clean_dragged_path() {
    local p="$1"
    p="${p//\'/}"
    p="${p//\"/}"
    p="${p%% }"
    echo "$p"
}

# Check if a cask is installed but its .app is missing from /Applications
_is_cask_broken() {
    local name="$1"
    local cask_apps
    cask_apps=$(find "$(brew --prefix)/Caskroom/$name" -name "*.app" -maxdepth 3 2>/dev/null) || return 1
    [[ -z "$cask_apps" ]] && return 1
    while IFS= read -r app_path; do
        local appname
        appname=$(basename "$app_path")
        if [[ -e "/Applications/$appname" ]] || \
           [[ -e "/Applications/${appname/_installer/}" ]]; then
            return 1
        fi
    done <<< "$cask_apps"
    return 0
}

# Cache of .app basenames found under standard install dirs (session-scope)
_APP_BUNDLES=""

# Cache of cask→app mapping: lines "cask|App.app"; "cask|" = queried but no apps
_CASK_APP_CACHE=""

_load_app_bundles() {
    [[ -n "$_APP_BUNDLES" ]] && return
    local d app
    for d in /Applications /System/Applications "$HOME/Applications"; do
        [[ -d "$d" ]] || continue
        while IFS= read -r app; do
            _APP_BUNDLES+="${app##*/}"$'\n'
        done < <(find "$d" -maxdepth 2 -name "*.app" 2>/dev/null)
    done
}

# Echo .app names a cask declares (via `brew info --json`, memoized)
_cask_app_names() {
    local cask="$1"
    # Anchored cache lookup — substring match would conflate e.g. `code` with `vscode`
    local hit
    if hit=$(awk -F'|' -v c="$cask" '
        BEGIN { f=0 }
        $1==c { f=1; if ($2!="") print $2 }
        END   { exit !f }
    ' <<< "$_CASK_APP_CACHE"); then
        [[ -n "$hit" ]] && printf '%s\n' "$hit"
        return
    fi
    local apps
    apps=$(brew info --json=v2 --cask "$cask" 2>/dev/null | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    for c in d.get("casks", []):
        for art in c.get("artifacts", []):
            if isinstance(art, dict) and "app" in art:
                for a in art["app"]:
                    if isinstance(a, str):
                        print(a)
                    elif isinstance(a, dict):
                        for k in ("target", "source"):
                            if k in a and isinstance(a[k], str):
                                print(a[k]); break
except Exception:
    pass
' 2>/dev/null) || apps=""
    if [[ -n "$apps" ]]; then
        local a
        while IFS= read -r a; do
            [[ -z "$a" ]] && continue
            _CASK_APP_CACHE+="${cask}|${a}"$'\n'
        done <<< "$apps"
        printf '%s\n' "$apps"
    else
        _CASK_APP_CACHE+="${cask}|"$'\n'
    fi
}

# True iff package is installed outside Homebrew.
# Formulae: binary in $PATH (catches git from Xcode CLT, node from nvm, etc.)
# Casks: any of the cask's .app names exists under standard install dirs
_is_installed_external() {
    local name="$1" kind="$2"
    if [[ "$kind" == "formula" ]]; then
        command -v "$name" &>/dev/null
        return $?
    fi
    _load_app_bundles
    local app
    while IFS= read -r app; do
        [[ -z "$app" ]] && continue
        grep -qxF "$app" <<< "$_APP_BUNDLES" && return 0
    done < <(_cask_app_names "$name")
    return 1
}

# True iff installed via brew OR externally
# Usage: _is_installed name formula|cask brew_installed_list
_is_installed() {
    local name="$1" kind="$2" brew_list="$3"
    grep -qxF "$name" <<< "$brew_list" && return 0
    _is_installed_external "$name" "$kind"
}

# Worker: write cache entries for given casks to $out_file (runs under spinner subshell)
# `brew info --json=v2` aborts the whole batch on any unknown cask, so we extract
# the bad cask from stderr, drop it (sentinel-only), and retry until everything resolves.
_warm_cask_cache_to_file() {
    local out_file="$1"
    shift
    local -a casks=("$@")
    : > "$out_file"
    local err_tmp
    err_tmp=$(mktemp /tmp/macrift_brewerr_XXXXXX)
    local guard=0
    while [[ ${#casks[@]} -gt 0 && $guard -lt 30 ]]; do
        guard=$((guard + 1))
        local raw rc
        raw=$(brew info --json=v2 --cask "${casks[@]}" 2>"$err_tmp")
        rc=$?
        if [[ $rc -eq 0 && -n "$raw" ]]; then
            printf '%s' "$raw" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    for c in d.get("casks", []):
        token = c.get("token") or ""
        if not token:
            continue
        emitted = False
        for art in c.get("artifacts", []):
            if isinstance(art, dict) and "app" in art:
                for a in art["app"]:
                    if isinstance(a, str):
                        print(f"{token}|{a}"); emitted = True
                    elif isinstance(a, dict):
                        for k in ("target", "source"):
                            if k in a and isinstance(a[k], str):
                                print(f"{token}|{a[k]}"); emitted = True; break
        if not emitted:
            print(f"{token}|")
except Exception:
    pass
' 2>/dev/null >> "$out_file" || true
            break
        fi
        # Failure — try to identify the bad cask from stderr and exclude it
        local err bad=""
        err=$(<"$err_tmp")
        if [[ "$err" =~ Cask\ \'([^\']+)\' ]]; then
            bad="${BASH_REMATCH[1]}"
        fi
        if [[ -z "$bad" ]]; then
            break  # unknown failure mode — give up gracefully
        fi
        printf '%s|\n' "$bad" >> "$out_file"
        local -a remaining=()
        local c
        for c in "${casks[@]}"; do
            [[ "$c" == "$bad" ]] || remaining+=("$c")
        done
        casks=(${remaining[@]+"${remaining[@]}"})
    done
    rm -f "$err_tmp"
}

# Filter casks needing brew info (not in brew list, not yet cached), batch-warm with spinner
_prewarm_casks() {
    local installed="$1"
    shift
    local -a candidates=("$@")
    [[ ${#candidates[@]} -eq 0 ]] && return
    local -a to_warm=()
    local c
    for c in "${candidates[@]}"; do
        grep -qxF "$c" <<< "$installed" && continue
        awk -F'|' -v c="$c" 'BEGIN{f=0} $1==c{f=1} END{exit !f}' <<< "$_CASK_APP_CACHE" >/dev/null && continue
        to_warm+=("$c")
    done
    [[ ${#to_warm[@]} -eq 0 ]] && return
    local cache_tmp
    cache_tmp=$(mktemp /tmp/macrift_warm_XXXXXX)
    run_with_spinner "Checking ${#to_warm[@]} installed apps... please wait" \
        _warm_cask_cache_to_file "$cache_tmp" "${to_warm[@]}" || true
    if [[ -s "$cache_tmp" ]]; then
        _CASK_APP_CACHE+="$(<"$cache_tmp")"$'\n'
    fi
    rm -f "$cache_tmp"
}

# Collect cask tokens from one or more Brewfile-format files
_collect_casks() {
    local f line
    for f in "$@"; do
        [[ -f "$f" ]] || continue
        while IFS= read -r line; do
            [[ "$line" =~ ^cask[[:space:]]+\"([^\"]+)\" ]] && echo "${BASH_REMATCH[1]}"
        done < "$f"
    done
}

fzf_search_packages() {
    if ! command -v fzf &>/dev/null; then
        log_warn "fzf not found"
        if confirm "Install fzf via Homebrew?"; then
            brew_install "fzf" || return 0
        else
            return 0
        fi
    fi

    # Get installed packages
    local installed
    installed=$(brew list --formula -1 2>/dev/null | sed 's/@.*//')
    installed+=$'\n'$(brew list --cask -1 2>/dev/null)

    # Warm cask cache across all bundles
    local -a _prewarm_list=()
    while IFS= read -r _c; do
        [[ -n "$_c" ]] && _prewarm_list+=("$_c")
    done < <(_collect_casks "$MACRIFT_DIR"/config/Brewfile.*)
    _prewarm_casks "$installed" ${_prewarm_list[@]+"${_prewarm_list[@]}"}

    # Parse all Brewfiles: "name [category]" + keep original lines for install
    local -a fzf_lines=() brew_lines=()
    for brewfile in "$MACRIFT_DIR"/config/Brewfile.*; do
        [[ -f "$brewfile" ]] || continue
        local bname category
        bname=$(basename "$brewfile")
        category=$(_bundle_label "$bname")

        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*#.*$ || -z "${line// /}" ]] && continue
            local name="" kind=""
            if [[ "$line" =~ ^brew[[:space:]]+\"([^\"]+)\" ]]; then
                name="${BASH_REMATCH[1]}"
                kind="formula"
            elif [[ "$line" =~ ^cask[[:space:]]+\"([^\"]+)\" ]]; then
                name="${BASH_REMATCH[1]}"
                kind="cask"
            else
                continue
            fi
            # Skip already installed (via brew or externally)
            _is_installed "$name" "$kind" "$installed" && continue
            fzf_lines+=("$name  [$category]")
            brew_lines+=("$line")
        done < "$brewfile"
    done

    if [[ ${#fzf_lines[@]} -eq 0 ]]; then
        clear
        log_ok "Everything installed"
        wait_enter
        return
    fi

    # fzf multi-select
    local selected
    selected=$(printf '%s\n' "${fzf_lines[@]}" | fzf --multi \
        --header="tab select · enter install · esc cancel" \
        --prompt="search: " \
        --height=~80% \
        --reverse \
        --no-info) || true

    [[ -z "$selected" ]] && return

    # Build temp Brewfile from selected
    local tmp
    tmp=$(mktemp /tmp/macrift_fzf_XXXXXX)

    while IFS= read -r pick; do
        for ((i=0; i<${#fzf_lines[@]}; i++)); do
            if [[ "${fzf_lines[$i]}" == "$pick" ]]; then
                echo "${brew_lines[$i]}" >> "$tmp"
                break
            fi
        done
    done <<< "$selected"

    if [[ ! -s "$tmp" ]]; then
        rm -f "$tmp"
        return
    fi

    local count
    count=$(wc -l < "$tmp" | tr -d ' ')

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install $count packages:"
        while IFS= read -r line; do
            printf '  %b· %s%b\n' "$DIM" "$line" "$RESET"
        done < "$tmp"
        rm -f "$tmp"
        wait_enter
        return
    fi

    log_info "Installing $count packages..."
    if brew bundle --quiet --no-upgrade --file="$tmp"; then
        log_ok "All packages installed"
    else
        log_warn "Some packages failed to install"
        log_hint "re-run, or 'brew doctor' to diagnose; logs in ~/Library/Logs/Homebrew"
    fi
    rm -f "$tmp"
    wait_enter
}

brew_menu() {
    if ! check_homebrew; then wait_enter; return; fi
    crumb_push "Homebrew"
    while true; do
        clear

        local choice
        choice=$(show_menu "Homebrew" \
            "Search packages" \
            "---" \
            "Development" \
            "Utilities" \
            "Browsers" \
            "---" \
            "Communication" \
            "Media" \
            "Games" \
            "Fonts (Nerd Fonts)" \
            "---" \
            "Install all bundles" \
            "Backup & restore ›" \
            "Back")

        case "$choice" in
            1) fzf_search_packages ;;
            2) install_bundle "Brewfile.dev" "Development" ;;
            3) install_bundle "Brewfile.utils" "Utilities" ;;
            4) install_bundle "Brewfile.browsers" "Browsers" ;;
            5) install_bundle "Brewfile.comm" "Communication" ;;
            6) install_bundle "Brewfile.media" "Media" ;;
            7) install_bundle "Brewfile.games" "Games" ;;
            8) install_bundle "Brewfile.fonts" "Fonts" ;;
            9) install_all_bundles ;;
            10) brewbak_menu ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

brewbak_menu() {
    crumb_push "Backup"
    while true; do
        clear

        local choice
        choice=$(show_menu "Backup (.brewbak)" \
            "Import from .brewbak" \
            "Export to .brewbak" \
            "Back")

        case "$choice" in
            1) import_brewbak ;;
            2) export_brewbak ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

_fix_broken_casks() {
    local casks=("$@")
    [[ ${#casks[@]} -eq 0 ]] && return
    log_warn "${#casks[@]} app(s) are missing from Applications"
    for cask in "${casks[@]}"; do
        printf '  %b· %s%b\n' "$DIM" "$cask" "$RESET"
    done
    printf "\n"
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would reinstall broken casks"
    elif confirm "Fix them now?"; then
        local idx=0
        for cask in "${casks[@]}"; do
            idx=$((idx + 1))
            show_progress "$idx" "${#casks[@]}" "$cask"
            if brew reinstall --cask "$cask" &>/dev/null; then
                log_ok "$cask reinstalled"
            else
                log_warn "Failed to reinstall $cask"
                log_hint "try: brew reinstall --cask $cask"
            fi
        done
    fi
}

install_bundle() {
    local brewfile="$1"
    local label="${2:-$brewfile}"
    local path="$MACRIFT_DIR/config/$brewfile"

    if [[ ! -f "$path" ]]; then
        log_err "Brewfile not found: $path"
        return 1
    fi

    clear

    # Get installed packages (strip @version from formulae, e.g. python@3.14 → python)
    local installed
    installed=$(brew list --formula -1 2>/dev/null | sed 's/@.*//')
    installed+=$'\n'$(brew list --cask -1 2>/dev/null)

    # Warm cask→app cache up front so the parse loop is fast and user sees progress
    local -a _prewarm_list=()
    while IFS= read -r _c; do
        [[ -n "$_c" ]] && _prewarm_list+=("$_c")
    done < <(_collect_casks "$path")
    _prewarm_casks "$installed" ${_prewarm_list[@]+"${_prewarm_list[@]}"}

    # Parse Brewfile — split into new, broken, and already installed
    local new_lines=()
    local new_labels=()
    local new_optional=()
    local broken_casks=()
    local installed_view=()
    local installed_count=0
    local had_items=false
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*#.*$ ]] && continue
        if [[ -z "${line// /}" ]]; then
            if $had_items; then
                new_lines+=("")
                new_labels+=("---")
                new_optional+=("0")
            fi
            continue
        fi
        had_items=true
        local name="" kind=""
        if [[ "$line" =~ ^brew[[:space:]]+\"([^\"]+)\" ]]; then
            name="${BASH_REMATCH[1]}"
            kind="formula"
        elif [[ "$line" =~ ^cask[[:space:]]+\"([^\"]+)\" ]]; then
            name="${BASH_REMATCH[1]}"
            kind="cask"
        else
            continue
        fi
        local optional=0
        [[ "$line" == *"# optional"* ]] && optional=1
        if grep -qxF "$name" <<< "$installed"; then
            if [[ "$kind" == "cask" ]] && _is_cask_broken "$name"; then
                broken_casks+=("$name")
                continue
            fi
            installed_count=$((installed_count + 1))
            installed_view+=("$name [brew]")
        elif _is_installed_external "$name" "$kind"; then
            installed_count=$((installed_count + 1))
            installed_view+=("$name [external]")
        else
            new_lines+=("$line")
            new_labels+=("$name")
            new_optional+=("$optional")
        fi
    done < "$path"

    # Check if there are any real (non-separator) new items
    local has_new=false
    if [[ ${new_labels[*]+x} && ${#new_labels[@]} -gt 0 ]]; then
        for lbl in "${new_labels[@]}"; do
            if [[ "$lbl" != "---" ]]; then has_new=true; break; fi
        done
    fi

    # Nothing new — show status, handle broken casks
    if ! $has_new; then
        log_ok "Everything installed"
        if [[ ${broken_casks[*]+x} && ${#broken_casks[@]} -gt 0 ]]; then
            _fix_broken_casks "${broken_casks[@]}"
        fi
        wait_enter
        return 0
    fi

    # Clean up separators: remove leading, trailing, and consecutive
    if [[ ${#new_labels[@]} -gt 0 ]]; then
        local clean_lines=() clean_labels=() clean_optional=()
        local prev_sep=true
        for ((i=0; i<${#new_labels[@]}; i++)); do
            if [[ "${new_labels[$i]}" == "---" ]]; then
                $prev_sep && continue
                prev_sep=true
            else
                prev_sep=false
            fi
            clean_lines+=("${new_lines[$i]}")
            clean_labels+=("${new_labels[$i]}")
            clean_optional+=("${new_optional[$i]}")
        done
        # Remove trailing separator
        while [[ ${#clean_labels[@]} -gt 0 && "${clean_labels[${#clean_labels[@]}-1]}" == "---" ]]; do
            unset "clean_lines[${#clean_lines[@]}-1]"
            unset "clean_labels[${#clean_labels[@]}-1]"
            unset "clean_optional[${#clean_optional[@]}-1]"
        done
        new_lines=(${clean_lines[@]+"${clean_lines[@]}"})
        new_labels=(${clean_labels[@]+"${clean_labels[@]}"})
        new_optional=(${clean_optional[@]+"${clean_optional[@]}"})
    fi

    # Handle missing apps separately
    if [[ ${#broken_casks[@]} -gt 0 ]]; then
        printf "\n"
        _fix_broken_casks "${broken_casks[@]}"
        printf "\n"
    fi

    # After cleanup, if only separators remained they're gone — nothing to show
    if [[ ! ${new_labels[*]+x} || ${#new_labels[@]} -eq 0 ]]; then
        return 0
    fi

    # Multiselect for new packages only
    local ms_title="$label"
    [[ $installed_count -gt 0 ]] && ms_title="$label · $installed_count installed"
    # Build space-padded optional indices for show_multiselect
    MULTISELECT_OPTIONAL=""
    for ((i=0; i<${#new_optional[@]}; i++)); do
        [[ "${new_optional[$i]}" == "1" ]] && MULTISELECT_OPTIONAL+="$i "
    done
    # Feed already-installed packages to show_multiselect's view mode (→ to toggle).
    # Inline env-prefix keeps it scoped to the subshell — no leak into other menus.
    local installed_str=""
    for ((i=0; i<${#installed_view[@]}; i++)); do
        installed_str+="${installed_view[$i]}"$'\n'
    done
    local selected
    selected=$(MULTISELECT_INSTALLED="$installed_str" show_multiselect "$ms_title" "${new_labels[@]}")

    if [[ -z "$selected" ]]; then
        return 0
    fi

    # Build temp Brewfile with selected packages
    local tmp
    tmp=$(mktemp /tmp/macrift_brew_XXXXXX)

    for ((i=0; i<${#new_labels[@]}; i++)); do
        [[ "${new_labels[$i]}" == "---" ]] && continue
        if echo "$selected" | grep -qxF "${new_labels[$i]}"; then
            echo "${new_lines[$i]}" >> "$tmp"
        fi
    done

    if [[ ! -s "$tmp" ]]; then
        rm -f "$tmp"
        return 0
    fi

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install:"
        [[ -s "$tmp" ]] && while IFS= read -r line; do
            printf '  %b· %s%b\n' "$DIM" "$line" "$RESET"
        done < "$tmp"
        rm -f "$tmp"
        wait_enter
        return 0
    fi

    local all_ok=true

    if [[ -s "$tmp" ]]; then
        log_info "Installing selected packages..."
        brew bundle --quiet --no-upgrade --file="$tmp" || all_ok=false
    fi
    rm -f "$tmp"

    if $all_ok; then
        log_ok "All packages installed"
    else
        log_warn "Some packages failed to install"
        log_hint "re-run, or 'brew doctor' to diagnose; logs in ~/Library/Logs/Homebrew"
    fi
    wait_enter
}

_bundle_label() {
    case "$1" in
        Brewfile.dev)      echo "Development" ;;
        Brewfile.utils)    echo "Utilities" ;;
        Brewfile.browsers) echo "Browsers" ;;
        Brewfile.comm)     echo "Communication" ;;
        Brewfile.media)    echo "Media" ;;
        Brewfile.games)    echo "Games" ;;
        Brewfile.fonts)    echo "Fonts" ;;
        *)                 echo "$1" ;;
    esac
}

install_all_bundles() {
    clear

    # Get installed packages once
    local installed
    installed=$(brew list --formula -1 2>/dev/null | sed 's/@.*//')
    installed+=$'\n'$(brew list --cask -1 2>/dev/null)

    # Warm cache for all casks across all bundles in one batch
    local -a _prewarm_list=()
    while IFS= read -r _c; do
        [[ -n "$_c" ]] && _prewarm_list+=("$_c")
    done < <(_collect_casks "$MACRIFT_DIR"/config/Brewfile.*)
    _prewarm_casks "$installed" ${_prewarm_list[@]+"${_prewarm_list[@]}"}

    # Merge all brewfiles into one list with section separators
    local all_lines=() all_labels=() all_optional=()
    local installed_view=()
    local installed_count=0 first_section=true

    for brewfile in "$MACRIFT_DIR"/config/Brewfile.*; do
        [[ -f "$brewfile" ]] || continue
        local bname had_new=false section_label
        bname=$(basename "$brewfile")
        section_label=$(_bundle_label "$bname")

        local section_lines=() section_labels=() section_optional=()
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*#.*$ || -z "${line// /}" ]] && continue
            local name="" kind=""
            if [[ "$line" =~ ^brew[[:space:]]+\"([^\"]+)\" ]]; then
                name="${BASH_REMATCH[1]}"
                kind="formula"
            elif [[ "$line" =~ ^cask[[:space:]]+\"([^\"]+)\" ]]; then
                name="${BASH_REMATCH[1]}"
                kind="cask"
            else
                continue
            fi
            local optional=0
            [[ "$line" == *"# optional"* ]] && optional=1
            if grep -qxF "$name" <<< "$installed"; then
                installed_count=$((installed_count + 1))
                installed_view+=("$name [brew · $section_label]")
            elif _is_installed_external "$name" "$kind"; then
                installed_count=$((installed_count + 1))
                installed_view+=("$name [external · $section_label]")
            else
                section_lines+=("$line")
                section_labels+=("$name")
                section_optional+=("$optional")
                had_new=true
            fi
        done < "$brewfile"

        if $had_new; then
            if ! $first_section && [[ ${#all_labels[@]} -gt 0 ]]; then
                all_lines+=("")
                all_labels+=("---")
                all_optional+=("0")
            fi
            first_section=false
            for ((i=0; i<${#section_labels[@]}; i++)); do
                all_lines+=("${section_lines[$i]}")
                all_labels+=("${section_labels[$i]}")
                all_optional+=("${section_optional[$i]}")
            done
        fi
    done

    if [[ ${#all_labels[@]} -eq 0 ]]; then
        log_ok "Everything installed"
        [[ $installed_count -gt 0 ]] && log_info "$installed_count packages already installed"
        wait_enter
        return
    fi

    local ms_title="All Bundles"
    [[ $installed_count -gt 0 ]] && ms_title="All Bundles · $installed_count installed"

    MULTISELECT_OPTIONAL=""
    for ((i=0; i<${#all_optional[@]}; i++)); do
        [[ "${all_optional[$i]}" == "1" ]] && MULTISELECT_OPTIONAL+="$i "
    done
    local installed_str=""
    for ((i=0; i<${#installed_view[@]}; i++)); do
        installed_str+="${installed_view[$i]}"$'\n'
    done
    local selected
    selected=$(MULTISELECT_INSTALLED="$installed_str" show_multiselect "$ms_title" "${all_labels[@]}")
    [[ -z "$selected" ]] && return

    local tmp
    tmp=$(mktemp /tmp/macrift_brew_all_XXXXXX)

    for ((i=0; i<${#all_labels[@]}; i++)); do
        [[ "${all_labels[$i]}" == "---" ]] && continue
        if echo "$selected" | grep -qxF "${all_labels[$i]}"; then
            echo "${all_lines[$i]}" >> "$tmp"
        fi
    done

    if [[ ! -s "$tmp" ]]; then
        rm -f "$tmp"
        return
    fi

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install:"
        while IFS= read -r line; do
            printf '  %b· %s%b\n' "$DIM" "$line" "$RESET"
        done < "$tmp"
        rm -f "$tmp"
        wait_enter
        return
    fi

    log_info "Installing selected packages..."
    if brew bundle --quiet --no-upgrade --file="$tmp"; then
        log_ok "All packages installed"
    else
        log_warn "Some packages failed to install"
        log_hint "re-run, or 'brew doctor' to diagnose; logs in ~/Library/Logs/Homebrew"
    fi
    rm -f "$tmp"
    wait_enter
}

import_brewbak() {
    clear

    printf '  %bDrag file into terminal or type path%b\n' "$DIM" "$RESET"
    prompt_path
    read -r filepath

    filepath=$(_clean_dragged_path "$filepath")

    if [[ ! -f "$filepath" ]]; then
        log_err "File not found: $filepath"
        wait_enter
        return
    fi

    clear

    # Get installed packages (strip @version from formulae, e.g. python@3.14 → python)
    local installed
    installed=$(brew list --formula -1 2>/dev/null | sed 's/@.*//')
    installed+=$'\n'$(brew list --cask -1 2>/dev/null)

    # Warm cask cache from backup file
    local -a _prewarm_list=()
    while IFS= read -r _c; do
        [[ -n "$_c" ]] && _prewarm_list+=("$_c")
    done < <(_collect_casks "$filepath")
    _prewarm_casks "$installed" ${_prewarm_list[@]+"${_prewarm_list[@]}"}

    # Parse brewbak — same format as Brewfile
    local new_lines=()
    local new_labels=()
    local installed_view=()
    local installed_count=0
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*#.*$ || -z "${line// /}" ]] && continue
        local name="" label="" kind=""
        if [[ "$line" =~ ^brew[[:space:]]+\"([^\"]+)\" ]]; then
            name="${BASH_REMATCH[1]}"
            label="$name"
            kind="formula"
        elif [[ "$line" =~ ^cask[[:space:]]+\"([^\"]+)\" ]]; then
            name="${BASH_REMATCH[1]}"
            label="$name"
            kind="cask"
        elif [[ "$line" =~ ^tap[[:space:]]+\"([^\"]+)\" ]]; then
            name="${BASH_REMATCH[1]}"
            label="$name (tap)"
            new_lines+=("$line")
            new_labels+=("$label")
            continue
        else
            continue
        fi
        if grep -qxF "$name" <<< "$installed"; then
            if [[ "$kind" == "cask" ]] && _is_cask_broken "$name"; then
                new_lines+=("$line")
                new_labels+=("$label [broken]")
                continue
            fi
            installed_count=$((installed_count + 1))
            installed_view+=("$name [brew]")
        elif _is_installed_external "$name" "$kind"; then
            installed_count=$((installed_count + 1))
            installed_view+=("$name [external]")
        else
            new_lines+=("$line")
            new_labels+=("$label")
        fi
    done < "$filepath"

    if [[ $installed_count -gt 0 ]]; then
        log_ok "$installed_count already installed"
    fi

    if [[ ${#new_labels[@]} -eq 0 ]]; then
        log_ok "Everything from backup is already installed"
        wait_enter
        return
    fi

    local installed_str=""
    for ((i=0; i<${#installed_view[@]}; i++)); do
        installed_str+="${installed_view[$i]}"$'\n'
    done
    local selected
    selected=$(MULTISELECT_INSTALLED="$installed_str" show_multiselect "Import" "${new_labels[@]}")

    if [[ -z "$selected" ]]; then
        log_info "Nothing selected"
        return
    fi

    local tmp
    tmp=$(mktemp /tmp/macrift_import_XXXXXX)

    for ((i=0; i<${#new_labels[@]}; i++)); do
        if echo "$selected" | grep -qxF "${new_labels[$i]}"; then
            echo "${new_lines[$i]}" >> "$tmp"
        fi
    done

    log_info "Installing selected packages..."
    if brew bundle --quiet --no-upgrade --file="$tmp"; then
        log_ok "Import complete"
    else
        log_warn "Some packages failed to install"
        log_hint "re-run, or 'brew doctor' to diagnose; logs in ~/Library/Logs/Homebrew"
    fi
    rm -f "$tmp"
    wait_enter
}

export_brewbak() {
    clear

    local default_path
    default_path="$HOME/Desktop/macrift-$(date +%Y%m%d).brewbak"
    printf '  %bSave path (enter for default):%b\n' "$DIM" "$RESET"
    printf '  %b%s%b\n' "$DIM" "$default_path" "$RESET"
    prompt_path
    read -r filepath

    if [[ -z "$filepath" ]]; then
        filepath="$default_path"
    fi
    filepath=$(_clean_dragged_path "$filepath")

    log_info "Exporting..."
    if brew bundle dump --file="$filepath" --force; then
        log_ok "Exported to $filepath"
    else
        log_err "Export failed"
        log_hint "check the path is writable: $filepath"
    fi
    wait_enter
}
