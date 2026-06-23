#!/usr/bin/env bash
# macrift — Code editor config

editor_menu() {
    if ! check_homebrew; then wait_enter; return; fi
    crumb_push "Code Editor"

    # VS Code family first, then Zed (separate settings format)
    local family=("VSCode" "Cursor" "Windsurf" "VSCodium")

    while true; do
        clear

        # Show every editor; ones not installed render dim (US-byte marker) but
        # stay selectable — picking one still offers to install it via Homebrew.
        local menu=() pick=() e label
        for e in "${family[@]}"; do
            label="$e"; _editor_installed "$e" || label+=$'\x1f'
            menu+=("$label"); pick+=("$e")
        done
        menu+=("Install extensions"); pick+=("__install__")
        menu+=("---")
        label="Zed"; _editor_installed "Zed" || label+=$'\x1f'
        menu+=("$label"); pick+=("Zed")
        menu+=("Back")

        local choice
        choice=$(show_menu "Code Editor" "${menu[@]}")
        [[ -z "$choice" || "$choice" == "0" ]] && break

        local sel="${pick[$((choice - 1))]:-}"
        if [[ "$sel" == "__install__" ]]; then
            install_extensions; wait_enter
        elif [[ -n "$sel" ]]; then
            apply_editor_config "$sel" "$(_editor_settings "$sel")"
        fi
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

# App-bundle base name per editor (for install detection)
_editor_app() {
    case "$1" in
        VSCode)   echo "Visual Studio Code" ;;
        Cursor)   echo "Cursor" ;;
        Windsurf) echo "Windsurf" ;;
        VSCodium) echo "VSCodium" ;;
        Zed)      echo "Zed" ;;
    esac
}

# Installed = .app present (/Applications or ~/Applications) or CLI on PATH
_editor_installed() {
    local name="$1" app
    app=$(_editor_app "$name")
    [[ -n "$app" && ( -d "/Applications/$app.app" || -d "$HOME/Applications/$app.app" ) ]] && return 0
    case "$name" in
        VSCode)   command -v code     &>/dev/null && return 0 ;;
        Cursor)   command -v cursor   &>/dev/null && return 0 ;;
        Windsurf) command -v windsurf &>/dev/null && return 0 ;;
        VSCodium) command -v codium   &>/dev/null && return 0 ;;
        Zed)      command -v zed      &>/dev/null && return 0 ;;
    esac
    return 1
}

# settings.json path per editor
_editor_settings() {
    case "$1" in
        VSCode)   echo "$HOME/Library/Application Support/Code/User/settings.json" ;;
        Cursor)   echo "$HOME/Library/Application Support/Cursor/User/settings.json" ;;
        Windsurf) echo "$HOME/Library/Application Support/Windsurf/User/settings.json" ;;
        VSCodium) echo "$HOME/Library/Application Support/VSCodium/User/settings.json" ;;
        Zed)      echo "$HOME/.config/zed/settings.json" ;;
    esac
}

# CLI command per VS Code-family editor (for extension install)
_editor_cli() {
    case "$1" in
        VSCode)   echo "code" ;;
        Cursor)   echo "cursor" ;;
        Windsurf) echo "windsurf" ;;
        VSCodium) echo "codium" ;;
    esac
}

apply_editor_config() {
    local editor_name="$1"
    local target="$2"
    local source="$MACRIFT_DIR/config/vscode/settings.json"
    [[ "$editor_name" == "Zed" ]] && source="$MACRIFT_DIR/config/zed/settings.json"

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
        if [[ "$editor_name" == "Zed" ]]; then
            _zed_fonts "$target"
        else
            printf '\n'
            confirm "Choose extensions to install?" && install_extensions "$editor_name"
        fi
    fi
    wait_enter
}

# Patch a "key": "value" string in the copied Zed settings, preserving JSONC comments
_zed_set_font() {
    local file="$1" key="$2" val="$3"
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then log_info "Would set $key → $val"; return 0; fi
    [[ -f "$file" ]] || { log_warn "$file not found"; return 1; }
    local tmp esc; tmp=$(mktemp)
    esc=$(printf '%s' "$val" | sed -e 's/[\&|]/\\&/g') # escape sed specials
    if sed -E "s|(\"$key\"[[:space:]]*:[[:space:]]*\")[^\"]*(\")|\1$esc\2|" "$file" > "$tmp" \
        && [[ -s "$tmp" ]]; then
        mv "$tmp" "$file"
    else
        rm -f "$tmp"; return 1
    fi
}

# Optional font setup after applying the Zed config
_zed_fonts() {
    local target="$1"
    printf '\n'
    local choice
    choice=$(show_menu "Zed fonts" \
        "Install Maple Mono + FiraCode Nerd Font" \
        "Type my own font name" \
        "Skip (use config as-is)")
    case "$choice" in
        1)
            if [[ "$MACRIFT_DRY_RUN" == true ]]; then
                log_info "Dry run — would install font-maple-mono + font-fira-code-nerd-font"
            else
                brew_install "font-maple-mono" "cask"
                brew_install "font-fira-code-nerd-font" "cask"
            fi
            ;;
        2)
            local editor_font ui_font
            printf '  %bEditor font (Enter to keep):%b ' "$DIM" "$RESET"
            IFS= read -r editor_font < /dev/tty || true
            [[ -n "$editor_font" ]] && _zed_set_font "$target" "buffer_font_family" "$editor_font" \
                && log_ok "Editor font → $editor_font"
            printf '  %bUI font (Enter = same as editor):%b ' "$DIM" "$RESET"
            IFS= read -r ui_font < /dev/tty || true
            [[ -z "$ui_font" ]] && ui_font="$editor_font"
            [[ -n "$ui_font" ]] && _zed_set_font "$target" "ui_font_family" "$ui_font" \
                && log_ok "UI font → $ui_font"
            ;;
        *) : ;; # 3 or implicit Back (0) → skip
    esac
}

install_extensions() {
    local want_editor="${1:-}"
    local ext_file="$MACRIFT_DIR/config/vscode/extensions.txt"

    if [[ ! -f "$ext_file" ]]; then
        log_warn "No extensions.txt found in config/vscode/"
        return
    fi

    local items=() ext_count=0 seen_header=false
    while IFS= read -r line; do
        # "## Section" → labeled heading row (blank-spaced before each after the first)
        if [[ "$line" == "## "* ]]; then
            $seen_header && items+=("---")
            items+=("$line")
            seen_header=true
            continue
        fi
        [[ -z "$line" || "$line" == \#* ]] && continue
        items+=("$line")
        ext_count=$((ext_count + 1))
    done < "$ext_file"

    if [[ $ext_count -eq 0 ]]; then
        log_info "extensions.txt is empty"
        return
    fi

    local selected
    selected=$(show_multiselect "Extensions ($ext_count)" "${items[@]}")
    [[ -z "$selected" ]] && return

    # Prefer the editor we just configured; else fall back to whatever CLI exists
    local cli=""
    if [[ -n "$want_editor" ]]; then
        local wcli; wcli=$(_editor_cli "$want_editor")
        [[ -n "$wcli" ]] && command -v "$wcli" &>/dev/null && cli="$wcli"
    fi
    if [[ -z "$cli" ]]; then
        if command -v code &>/dev/null; then
            cli="code"
        elif command -v cursor &>/dev/null; then
            cli="cursor"
        elif command -v codium &>/dev/null; then
            cli="codium"
        fi
    fi

    if [[ -z "$cli" ]]; then
        log_err "No editor CLI found (code, cursor, codium)"
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
}
