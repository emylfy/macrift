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

brew_menu() {
    if ! check_homebrew; then wait_enter; return; fi
    crumb_push "Homebrew"
    while true; do
        clear

        local choice
        choice=$(show_menu "Homebrew" \
            "Development" \
            "Utilities" \
            "Browsers" \
            "---" \
            "Communication" \
            "Media" \
            "Games" \
            "Fonts (Nerd Fonts)" \
            "---" \
            "Install ALL bundles" \
            "Backup (.brewbak)" \
            "Back")

        case "$choice" in
            1) install_bundle "Brewfile.dev" "Development" ;;
            2) install_bundle "Brewfile.utils" "Utilities" ;;
            3) install_bundle "Brewfile.browsers" "Browsers" ;;
            4) install_bundle "Brewfile.comm" "Communication" ;;
            5) install_bundle "Brewfile.media" "Media" ;;
            6) install_bundle "Brewfile.games" "Games" ;;
            7) install_bundle "Brewfile.fonts" "Fonts" ;;
            8) install_all_bundles ;;
            9) brewbak_menu ;;
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

    # Parse Brewfile — split into new, broken, and already installed
    local new_lines=()
    local new_labels=()
    local broken_casks=()
    local installed_count=0
    local had_items=false
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*#.*$ ]] && continue
        if [[ -z "${line// /}" ]]; then
            if $had_items; then
                new_lines+=("")
                new_labels+=("---")
            fi
            continue
        fi
        had_items=true
        local name=""
        if [[ "$line" =~ ^brew[[:space:]]+\"([^\"]+)\" ]]; then
            name="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^cask[[:space:]]+\"([^\"]+)\" ]]; then
            name="${BASH_REMATCH[1]}"
        else
            continue
        fi
        if echo "$installed" | grep -qxF "$name"; then
            if [[ "$line" =~ ^cask ]] && _is_cask_broken "$name"; then
                broken_casks+=("$name")
                continue
            fi
            installed_count=$((installed_count + 1))
        else
            new_lines+=("$line")
            new_labels+=("$name")
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
        local clean_lines=() clean_labels=()
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
        done
        # Remove trailing separator
        while [[ ${#clean_labels[@]} -gt 0 && "${clean_labels[${#clean_labels[@]}-1]}" == "---" ]]; do
            unset "clean_lines[${#clean_lines[@]}-1]"
            unset "clean_labels[${#clean_labels[@]}-1]"
        done
        new_lines=(${clean_lines[@]+"${clean_lines[@]}"})
        new_labels=(${clean_labels[@]+"${clean_labels[@]}"})
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
    local selected
    selected=$(show_multiselect "$ms_title" "${new_labels[@]}")

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

    # Merge all brewfiles into one list with section separators
    local all_lines=() all_labels=()
    local installed_count=0 first_section=true

    for brewfile in "$MACRIFT_DIR"/config/Brewfile.*; do
        [[ -f "$brewfile" ]] || continue
        local bname had_new=false
        bname=$(basename "$brewfile")

        local section_lines=() section_labels=()
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*#.*$ || -z "${line// /}" ]] && continue
            local name=""
            if [[ "$line" =~ ^brew[[:space:]]+\"([^\"]+)\" ]]; then
                name="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^cask[[:space:]]+\"([^\"]+)\" ]]; then
                name="${BASH_REMATCH[1]}"
            else
                continue
            fi
            if echo "$installed" | grep -qxF "$name"; then
                installed_count=$((installed_count + 1))
            else
                section_lines+=("$line")
                section_labels+=("$name")
                had_new=true
            fi
        done < "$brewfile"

        if $had_new; then
            if ! $first_section && [[ ${#all_labels[@]} -gt 0 ]]; then
                all_lines+=("")
                all_labels+=("---")
            fi
            first_section=false
            for ((i=0; i<${#section_labels[@]}; i++)); do
                all_lines+=("${section_lines[$i]}")
                all_labels+=("${section_labels[$i]}")
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

    local selected
    selected=$(show_multiselect "$ms_title" "${all_labels[@]}")
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

    # Get installed packages
    local installed
    installed=$(brew list --formula -1 2>/dev/null; brew list --cask -1 2>/dev/null)

    # Parse brewbak — same format as Brewfile
    local new_lines=()
    local new_labels=()
    local installed_count=0
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*#.*$ || -z "${line// /}" ]] && continue
        local name="" label=""
        if [[ "$line" =~ ^brew[[:space:]]+\"([^\"]+)\" ]]; then
            name="${BASH_REMATCH[1]}"
            label="$name"
        elif [[ "$line" =~ ^cask[[:space:]]+\"([^\"]+)\" ]]; then
            name="${BASH_REMATCH[1]}"
            label="$name"
        elif [[ "$line" =~ ^tap[[:space:]]+\"([^\"]+)\" ]]; then
            name="${BASH_REMATCH[1]}"
            label="$name (tap)"
            new_lines+=("$line")
            new_labels+=("$label")
            continue
        else
            continue
        fi
        if echo "$installed" | grep -qxF "$name"; then
            if [[ "$line" =~ ^cask ]] && _is_cask_broken "$name"; then
                new_lines+=("$line")
                new_labels+=("$label [broken]")
                continue
            fi
            installed_count=$((installed_count + 1))
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

    local selected
    selected=$(show_multiselect "Import" "${new_labels[@]}")

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
    fi
    wait_enter
}
