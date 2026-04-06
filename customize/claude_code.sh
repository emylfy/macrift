#!/usr/bin/env bash
# macrift — Claude Code setup

CLAUDE_DIR="$HOME/.claude"
CC_CONFIG="$MACRIFT_DIR/config/claude-code"

claude_code_menu() {
    crumb_push "Claude Code"
    while true; do
        clear


        local choice
        choice=$(show_menu "Claude Code" \
            "Full Setup" \
            "---" \
            "Settings (user)" \
            "Settings (project template)" \
            "Hooks" \
            "Agents" \
            "Slash Commands" \
            "Rules" \
            "Environment" \
            "Back")

        case "$choice" in
            1) _cc_full_setup ;;
            2) _cc_install_settings_user; wait_enter ;;
            3) _cc_install_settings_project; wait_enter ;;
            4) _cc_install_hooks ;;
            5) _cc_install_agents ;;
            6) _cc_install_commands ;;
            7) _cc_install_rules ;;
            8) _cc_install_env; wait_enter ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

# Full Setup

_cc_full_setup() {
    clear
    printf '\n'
    printf '  %bClaude Code — Full Setup%b\n\n' "$BOLD" "$RESET"
    printf '  This will install all components to %b~/.claude/%b:\n\n' "$CYAN" "$RESET"
    printf '  %b›%b  User settings (permissions, plugins, effort level)\n' "$CYAN" "$RESET"
    printf '  %b›%b  Hooks (stop-verify, post-compact, pre-commit guard)\n' "$CYAN" "$RESET"
    printf '  %b›%b  Agents (debugger, reviewer, security-checker)\n' "$CYAN" "$RESET"
    printf '  %b›%b  Slash commands (/review, /audit, /debug)\n' "$CYAN" "$RESET"
    printf '  %b›%b  Rules (code-style, git, security)\n' "$CYAN" "$RESET"
    printf '  %b›%b  Environment variables in .zshrc\n' "$CYAN" "$RESET"
    printf '\n'

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install all Claude Code components"
        wait_enter
        return
    fi

    if ! confirm "Install all Claude Code components?"; then
        return
    fi

    _cc_ensure_dir
    _cc_install_settings_user
    _cc_install_hooks_copy
    _cc_install_dir "agents"
    _cc_install_dir "commands"
    _cc_install_dir "rules"
    _cc_install_env_copy

    printf '\n'
    log_ok "Claude Code fully configured"
    log_info "Restart your shell and Claude Code to apply"
    wait_enter
}

# Settings

_cc_install_settings_user() {
    local source="$CC_CONFIG/settings/user.json"
    local target="$CLAUDE_DIR/settings.json"

    if [[ ! -f "$source" ]]; then
        log_err "No user settings found in config/claude-code/settings/"
        return
    fi

    _cc_ensure_dir

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install user settings"
        return
    fi

    # Merge with existing settings if jq is available
    if [[ -f "$target" ]] && command -v jq &>/dev/null; then
        if confirm "Merge settings into existing ~/.claude/settings.json?"; then
            backup_file "$target"
            local merged
            merged=$(jq -s '.[0] * .[1]' "$target" "$source")
            echo "$merged" > "$target"
            log_ok "User settings merged"
            return
        fi
    fi

    if confirm "Copy user settings to ~/.claude/settings.json?"; then
        copy_config "$source" "$target"
        log_ok "User settings installed"
    fi
}

_cc_install_settings_project() {
    local source="$CC_CONFIG/settings/project.json"

    if [[ ! -f "$source" ]]; then
        log_err "No project settings found in config/claude-code/settings/"
        return
    fi

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would copy project settings template"
        return
    fi

    log_info "Project settings are a template for per-project .claude/settings.json"
    log_info "Source: config/claude-code/settings/project.json"
    printf '\n'

    local target
    printf '  Enter project path (or press Enter for current dir): '
    read -r target
    [[ -z "$target" ]] && target="."

    # Expand ~ manually
    target="${target/#\~/$HOME}"

    if [[ ! -d "$target" ]]; then
        log_err "Directory not found: $target"
        return
    fi

    local dest="$target/.claude/settings.json"
    if confirm "Copy project settings to $dest?"; then
        copy_config "$source" "$dest"
        log_ok "Project settings installed"
    fi
}

# Hooks

_cc_install_hooks() {
    local source_dir="$CC_CONFIG/hooks"
    local target_dir="$CLAUDE_DIR/hooks"

    if [[ ! -d "$source_dir" ]]; then
        log_err "No hooks found in config/claude-code/hooks/"
        wait_enter
        return
    fi

    local hooks=()
    for f in "$source_dir"/*.sh; do
        [[ -f "$f" ]] || continue
        hooks+=("$(basename "$f")")
    done

    if [[ ${#hooks[@]} -eq 0 ]]; then
        log_info "No hook scripts found"
        wait_enter
        return
    fi

    local selected
    selected=$(show_multiselect "Hooks" "${hooks[@]}")
    [[ -z "$selected" ]] && return

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install selected hooks"
        wait_enter
        return
    fi

    _cc_ensure_dir
    mkdir -p "$target_dir"

    while IFS= read -r hook; do
        copy_config "$source_dir/$hook" "$target_dir/$hook"
        chmod +x "$target_dir/$hook"
    done <<< "$selected"

    printf '\n'
    log_ok "Hooks installed to ~/.claude/hooks/"
    log_info "Register hooks in settings.json to activate them"
    wait_enter
}

_cc_install_hooks_copy() {
    local source_dir="$CC_CONFIG/hooks"
    local target_dir="$CLAUDE_DIR/hooks"
    mkdir -p "$target_dir"

    for f in "$source_dir"/*.sh; do
        [[ -f "$f" ]] || continue
        copy_config "$f" "$target_dir/$(basename "$f")"
        chmod +x "$target_dir/$(basename "$f")"
    done
    log_ok "Hooks installed"
}

# Agents / Commands / Rules

_cc_install_agents() {
    _cc_install_component "agents" "Agents" "md"
}

_cc_install_commands() {
    _cc_install_component "commands" "Slash Commands" "md"
}

_cc_install_rules() {
    _cc_install_component "rules" "Rules" "md"
}

_cc_install_component() {
    local dir_name="$1"
    local label="$2"
    local ext="$3"
    local source_dir="$CC_CONFIG/$dir_name"
    local target_dir="$CLAUDE_DIR/$dir_name"

    if [[ ! -d "$source_dir" ]]; then
        log_err "No $label found in config/claude-code/$dir_name/"
        wait_enter
        return
    fi

    local items=()
    for f in "$source_dir"/*."$ext"; do
        [[ -f "$f" ]] || continue
        items+=("$(basename "$f")")
    done

    if [[ ${#items[@]} -eq 0 ]]; then
        log_info "No $label found"
        wait_enter
        return
    fi

    local selected
    selected=$(show_multiselect "$label" "${items[@]}")
    [[ -z "$selected" ]] && return

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install selected $label"
        wait_enter
        return
    fi

    _cc_ensure_dir
    mkdir -p "$target_dir"

    local count=0
    while IFS= read -r item; do
        copy_config "$source_dir/$item" "$target_dir/$item"
        count=$((count + 1))
    done <<< "$selected"

    printf '\n'
    log_ok "$count $label installed to ~/.claude/$dir_name/"
    wait_enter
}

_cc_install_dir() {
    local dir_name="$1"
    local source_dir="$CC_CONFIG/$dir_name"
    local target_dir="$CLAUDE_DIR/$dir_name"
    mkdir -p "$target_dir"

    for f in "$source_dir"/*.md; do
        [[ -f "$f" ]] || continue
        copy_config "$f" "$target_dir/$(basename "$f")"
    done
    local label
    label="$(printf '%s' "${dir_name:0:1}" | tr '[:lower:]' '[:upper:]')${dir_name:1}"
    log_ok "$label installed"
}

# Environment

_cc_install_env() {
    local source="$CC_CONFIG/env.sh"
    local zshrc="$HOME/.zshrc"
    local marker="# macrift:claude-code env"

    if [[ ! -f "$source" ]]; then
        log_err "No env.sh found in config/claude-code/"
        return
    fi

    log_info "Environment variables to add to .zshrc:"
    printf '\n'
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        printf '  %b›%b %s\n' "$CYAN" "$RESET" "$line"
    done < "$source"
    printf '\n'

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would add env vars to .zshrc"
        return
    fi

    if ! confirm "Add Claude Code env vars to .zshrc?"; then return; fi

    # Remove old block if exists
    if grep -q "$marker" "$zshrc" 2>/dev/null; then
        local temp
        temp=$(mktemp)
        awk "/$marker/{found=1; next} found && /^$/{found=0; next} !found" "$zshrc" > "$temp"
        cp "$temp" "$zshrc"
        rm -f "$temp"
        log_info "Replaced existing env block"
    fi

    # Append new block
    {
        echo ""
        echo "$marker"
        grep -v '^#' "$source" | grep -v '^$'
        echo "$marker"
    } >> "$zshrc"

    log_ok "Environment variables added to .zshrc"
    log_info "Restart shell to apply"
}

_cc_install_env_copy() {
    local source="$CC_CONFIG/env.sh"
    local zshrc="$HOME/.zshrc"
    local marker="# macrift:claude-code env"

    [[ ! -f "$source" ]] && return

    # Remove old block if exists
    if grep -q "$marker" "$zshrc" 2>/dev/null; then
        local temp
        temp=$(mktemp)
        awk "/$marker/{found=1; next} found && /^$/{found=0; next} !found" "$zshrc" > "$temp"
        cp "$temp" "$zshrc"
        rm -f "$temp"
    fi

    {
        echo ""
        echo "$marker"
        grep -v '^#' "$source" | grep -v '^$'
        echo "$marker"
    } >> "$zshrc"

    log_ok "Environment variables added to .zshrc"
}

# Helpers

_cc_ensure_dir() {
    mkdir -p "$CLAUDE_DIR"
}
