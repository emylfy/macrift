#!/usr/bin/env bash
# macrift — Code editor config

editor_menu() {
    if ! check_homebrew; then wait_enter; return; fi
    crumb_push "Code Editor"
    while true; do
        clear


        local choice
        choice=$(show_menu "Code Editor" \
            "VSCode" \
            "Cursor" \
            "Windsurf" \
            "VSCodium" \
            "Zed" \
            "---" \
            "Install extensions" \
            "Back")

        case "$choice" in
            1) apply_editor_config "VSCode" "$HOME/Library/Application Support/Code/User/settings.json" ;;
            2) apply_editor_config "Cursor" "$HOME/Library/Application Support/Cursor/User/settings.json" ;;
            3) apply_editor_config "Windsurf" "$HOME/Library/Application Support/Windsurf/User/settings.json" ;;
            4) apply_editor_config "VSCodium" "$HOME/Library/Application Support/VSCodium/User/settings.json" ;;
            5) apply_editor_config "Zed" "$HOME/.config/zed/settings.json" ;;
            6) install_extensions ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

_editor_cask() {
    case "$1" in
        VSCode)   echo "visual-studio-code" ;;
        Cursor)   echo "cursor" ;;
        Windsurf) echo "windsurf" ;;
        VSCodium) echo "vscodium" ;;
        Zed)      echo "zed" ;;
    esac
}

apply_editor_config() {
    local editor_name="$1"
    local target="$2"
    local source="$MACRIFT_DIR/config/vscode/settings.json"

    if [[ ! -f "$source" ]]; then
        log_warn "No settings.json found in config/vscode/"
        log_info "Add your settings.json there and re-run this"
        wait_enter
        return
    fi

    local target_dir
    target_dir=$(dirname "$target")

    if [[ ! -d "$target_dir" ]]; then
        local cask
        cask=$(_editor_cask "$editor_name")
        log_warn "$editor_name not installed"
        if [[ -n "$cask" ]] && confirm "Install $editor_name via Homebrew?"; then
            brew_install "$cask" "cask"
        else
            return 0
        fi
    fi

    if confirm "Copy settings.json to $editor_name?"; then
        copy_config "$source" "$target"
        log_ok "$editor_name settings applied"
    fi
    wait_enter
}

install_extensions() {
    local ext_file="$MACRIFT_DIR/config/vscode/extensions.txt"

    if [[ ! -f "$ext_file" ]]; then
        log_warn "No extensions.txt found in config/vscode/"
        wait_enter
        return
    fi

    local exts=()
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        exts+=("$line")
    done < "$ext_file"

    if [[ ${#exts[@]} -eq 0 ]]; then
        log_info "extensions.txt is empty"
        wait_enter
        return
    fi

    local selected
    selected=$(show_multiselect "Extensions (${#exts[@]})" "${exts[@]}")
    [[ -z "$selected" ]] && return

    # Pick which CLI to use
    local cli=""
    if command -v code &>/dev/null; then
        cli="code"
    elif command -v cursor &>/dev/null; then
        cli="cursor"
    elif command -v codium &>/dev/null; then
        cli="codium"
    fi

    if [[ -z "$cli" ]]; then
        log_err "No editor CLI found (code, cursor, codium)"
        wait_enter
        return
    fi

    clear
    log_info "Installing via '$cli'..."
    printf "\n"

    local count=0 total failed=0
    total=$(echo "$selected" | wc -l | tr -d ' ')

    while IFS= read -r ext; do
        count=$((count + 1))
        if [[ "$MACRIFT_DRY_RUN" == true ]]; then
            log_info "[$count/$total] Would install $ext"
        else
            printf '  %b[%d/%d]%b %s ' "$DIM" "$count" "$total" "$RESET" "$ext"
            if $cli --install-extension "$ext" --force &>/dev/null; then
                printf '%b✓%b\n' "$GREEN" "$RESET"
            else
                printf '%b✗%b\n' "$RED" "$RESET"
                failed=$((failed + 1))
            fi
        fi
    done <<< "$selected"

    printf "\n"
    if [[ $failed -eq 0 ]]; then
        log_ok "$count extensions installed"
    else
        log_warn "$count processed, $failed failed"
    fi
    wait_enter
}
