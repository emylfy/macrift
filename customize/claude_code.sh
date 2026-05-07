#!/usr/bin/env bash
# macrift — Claude Code setup

CLAUDE_DIR="$HOME/.claude"
CC_CONFIG="$MACRIFT_DIR/config/claude-code"
CC_ENV_MARKER="# macrift:claude-code env"
CC_RALIAS_MARKER="# macrift:claude-code r-alias"

# Telegram bot — see _cc_telegram_menu for the active engine setup.
# Legacy paths from previous plugin / linuz90 setups — kept so cleanup can find them.
CC_TG_LEGACY_LAUNCHER="$HOME/.local/bin/ctg"
CC_TG_LEGACY_LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.claude-tg.plist"
CC_TG_LEGACY_LAUNCH_AGENT_LABEL="com.claude-tg"
CC_TG_LEGACY_ENV_FILE="$HOME/.claude/channels/telegram/.env"
CC_TG_LEGACY_OLD_PLIST="$HOME/Library/LaunchAgents/com.emylfy.claude-telegram.plist"
CC_TG_LEGACY_OLD_LABEL="com.emylfy.claude-telegram"
CC_TG_LEGACY_OLD_LAUNCHER="$HOME/.local/bin/claude-telegram.sh"
CC_TG_PATH_MARKER="# macrift:claude-code local-bin-path"

claude_code_menu() {
    crumb_push "Claude Code"
    while true; do
        clear


        local choice
        choice=$(show_menu "Claude Code" \
            "Full Setup — install everything to ~/.claude/" \
            "Custom Setup — pick what to install" \
            "---" \
            "Reset — wipe macrift-managed Claude state" \
            "Back")

        case "$choice" in
            1)  _cc_full_setup ;;
            2)  _cc_custom_menu ;;
            3)  _cc_reset; wait_enter ;;
            0)  break ;;
            *)  ;;
        esac
    done
    crumb_pop
}

_cc_custom_menu() {
    crumb_push "Custom Setup"
    while true; do
        clear

        local choice
        choice=$(show_menu "Custom Setup" \
            "Settings (user) — permissions, plugins, model" \
            "Statusline — project/branch/model/ctx%/rate% display" \
            "Agents — debugger, reviewer, simplifier" \
            "Slash Commands — /debug, /review, /simplify" \
            "Rules — code-style, git, security, workflow" \
            "Hooks — format-on-edit, security gate" \
            "Environment — CLAUDE_CODE_* env vars in .zshrc" \
            "CLAUDE.md (rule imports) — load rules into every session" \
            "'r' alias — alias r='bash /tmp/cmd.sh' for workflow rule" \
            "Back")

        case "$choice" in
            1)  _cc_install_settings_user; wait_enter ;;
            2)  _cc_install_statusline; wait_enter ;;
            3)  _cc_install_agents ;;
            4)  _cc_install_commands ;;
            5)  _cc_install_rules ;;
            6)  _cc_install_hooks; wait_enter ;;
            7)  _cc_install_env; wait_enter ;;
            8)  _cc_install_claude_md; wait_enter ;;
            9)  _cc_install_r_alias; wait_enter ;;
            0)  break ;;
            *)  ;;
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
    printf '  %b›%b  Statusline (project, branch, model, ctx%%, rate%%)\n' "$CYAN" "$RESET"
    printf '  %b›%b  Agents (debugger, reviewer, simplifier)\n' "$CYAN" "$RESET"
    printf '  %b›%b  Slash commands (/debug, /review, /simplify)\n' "$CYAN" "$RESET"
    printf '  %b›%b  Rules (code-style, git, security, workflow)\n' "$CYAN" "$RESET"
    printf '  %b›%b  Hooks (format-on-edit, security gate)\n' "$CYAN" "$RESET"
    printf '  %b›%b  Environment variables in .zshrc\n' "$CYAN" "$RESET"
    printf '  %b›%b  CLAUDE.md with rule imports\n' "$CYAN" "$RESET"
    printf "  %b›%b  'r' alias for /tmp/cmd.sh in .zshrc\n" "$CYAN" "$RESET"
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
    _cc_install_settings_user --full
    _cc_install_statusline_copy
    _cc_install_dir "agents"
    _cc_install_dir "commands"
    _cc_install_dir "rules"
    _cc_install_hooks_copy
    _cc_install_env_copy
    _cc_install_claude_md_copy
    _cc_install_r_alias_copy

    printf '\n'
    log_ok "Claude Code fully configured"
    log_info "Restart your shell and Claude Code to apply"
    wait_enter
}

# Settings

# --full: skip the back-prompt, default mode = merge (no extra menu in Full Setup)
_cc_install_settings_user() {
    local source="$CC_CONFIG/settings/user.json"
    local target="$CLAUDE_DIR/settings.json"
    local full_setup=false
    [[ "${1:-}" == "--full" ]] && full_setup=true

    if [[ ! -f "$source" ]]; then
        log_err "No user settings found in config/claude-code/settings/"
        $full_setup || wait_enter
        return
    fi

    _cc_ensure_dir

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install user settings"
        return
    fi

    if ! $full_setup; then
        printf '\n'
        log_info "Source: $source"
        log_info "Target: $target"
        log_info "Contains: permissions allow/deny, plugins, effort level, model"
        printf '\n'
    fi

    local mode="merge"
    if [[ -f "$target" ]]; then
        if $full_setup; then
            mode="merge"
        else
            local choice
            choice=$(show_menu "Settings — existing ~/.claude/settings.json" \
                "Merge (macrift keys win on conflict)" \
                "Overwrite (clean install)" \
                "Skip" \
                "Back")
            case "$choice" in
                1) mode="merge" ;;
                2) mode="overwrite" ;;
                3) mode="skip" ;;
                *) return ;;
            esac
        fi
    fi

    case "$mode" in
        skip)
            log_skip "Settings unchanged"
            return
            ;;
        merge)
            if ! command -v jq >/dev/null 2>&1; then
                log_err "merge mode needs 'jq' — install: brew install jq"
                return
            fi
            if [[ -f "$target" ]]; then
                backup_file "$target"
                local merged jq_err err_log
                # jq `*` deep-merges objects but REPLACES arrays — so any user-added
                # entries in permissions.allow/deny will be overwritten by macrift's lists.
                # Capture stderr separately: if it leaked into $merged, a jq warning
                # would corrupt settings.json.
                err_log=$(mktemp)
                merged=$(jq -s '.[0] * .[1]' "$target" "$source" 2>"$err_log")
                local jq_status=$?
                jq_err=$(cat "$err_log")
                rm -f "$err_log"
                if (( jq_status != 0 )); then
                    log_err "jq merge failed — settings unchanged. Output: $jq_err"
                    return 1
                fi
                if [[ -z "$merged" ]]; then
                    log_err "jq produced empty output — settings unchanged"
                    return 1
                fi
                printf '%s\n' "$merged" > "$target"
                log_ok "User settings merged (objects deep-merged, arrays replaced)"
            else
                copy_config "$source" "$target"
                log_ok "User settings installed"
            fi
            ;;
        overwrite)
            copy_config "$source" "$target"
            log_ok "User settings installed"
            ;;
    esac

    # The source user.json intentionally contains the literal string "$HOME"
    # (e.g. in statusLine.command) because JSON has no env-var interpolation.
    # We bake the absolute path in here because Claude Code's statusLine runner
    # does not always expand env vars depending on shell context.
    # Caveat: this sed is global — if a merged user value contains "$HOME" in
    # any string position (paths, custom commands, etc.), it will also expand.
    # In practice that matches user intent, but worth knowing.
    if [[ -f "$target" ]] && grep -q '\$HOME' "$target"; then
        sed -i '' "s|\\\$HOME|$HOME|g" "$target"
    fi
}

# Statusline

_cc_install_statusline() {
    local source="$CC_CONFIG/statusline.sh"
    local target="$CLAUDE_DIR/statusline.sh"

    if [[ ! -f "$source" ]]; then
        log_err "No statusline.sh found in config/claude-code/"
        return
    fi

    printf '\n'
    log_info "Source: $source"
    log_info "Target: $target"
    log_info "Renders project, branch, model, ctx%, rate% in the Claude Code statusline"
    printf '\n'

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install statusline.sh"
        return
    fi

    if ! confirm "Install statusline.sh?"; then return; fi

    _cc_install_statusline_copy
}

_cc_install_statusline_copy() {
    local source="$CC_CONFIG/statusline.sh"
    local target="$CLAUDE_DIR/statusline.sh"
    [[ -f "$source" ]] || return
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Would copy statusline.sh → $target"
        return
    fi
    _cc_ensure_dir
    copy_config "$source" "$target"
}

# Hooks

_cc_install_hooks() {
    local source_dir="$CC_CONFIG/hooks"
    local target_dir="$CLAUDE_DIR/hooks"

    if [[ ! -d "$source_dir" ]]; then
        log_err "No hooks dir at $source_dir"
        return
    fi

    local items=()
    for f in "$source_dir"/*.sh; do
        [[ -f "$f" ]] || continue
        items+=("$(basename "$f")")
    done

    if [[ ${#items[@]} -eq 0 ]]; then
        log_info "No hooks found"
        return
    fi

    printf '\n'
    log_info "Lifecycle hooks invoked by settings.json (PostToolUse, PreToolUse)"
    log_info "Will be copied to ~/.claude/hooks/"
    printf '\n'

    local selected
    selected=$(show_multiselect "Hooks" "${items[@]}")
    [[ -z "$selected" ]] && return

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install selected hooks"
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
    log_ok "$count hook(s) installed to ~/.claude/hooks/"
}

_cc_install_hooks_copy() {
    local source_dir="$CC_CONFIG/hooks"
    local target_dir="$CLAUDE_DIR/hooks"
    [[ -d "$source_dir" ]] || return
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Would copy hooks → $target_dir"
        return
    fi
    mkdir -p "$target_dir"
    for f in "$source_dir"/*.sh; do
        [[ -f "$f" ]] || continue
        copy_config "$f" "$target_dir/$(basename "$f")"
    done
    log_ok "Hooks installed"
}

# Agents / Commands / Rules

_cc_install_agents() {
    _cc_install_component "agents" "Agents" "md" \
        "Custom subagents Claude can spawn (e.g. via /debug, /review)"
}

_cc_install_commands() {
    _cc_install_component "commands" "Slash Commands" "md" \
        "Slash commands you can invoke in Claude (/<name>)"
}

_cc_install_rules() {
    _cc_install_component "rules" "Rules" "md" \
        "Behavior rules — imported into every session via CLAUDE.md"
}

_cc_install_component() {
    local dir_name="$1"
    local label="$2"
    local ext="$3"
    local hint="${4:-}"
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

    if [[ -n "$hint" ]]; then
        printf '\n'
        log_info "$hint"
        log_info "Will be copied to ~/.claude/$dir_name/"
        printf '\n'
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

# Verify marker pairing in $file before awk-toggle modifies it.
# Unbalanced markers would make awk swallow the whole file tail. Returns 0 if safe.
_cc_marker_balanced() {
    local file="$1"
    local marker="$2"
    local count
    count=$(grep -cF "$marker" "$file" 2>/dev/null) || count=0
    (( count % 2 == 0 ))
}

# .zshrc marker-block helper
# Replaces (or appends) a block in $zshrc bounded by two identical marker lines.
# Body is read from stdin.
_cc_replace_marked_block() {
    local zshrc="$1"
    local marker="$2"

    [[ -f "$zshrc" ]] || touch "$zshrc"

    if grep -qF "$marker" "$zshrc" 2>/dev/null; then
        if ! _cc_marker_balanced "$zshrc" "$marker"; then
            log_err "Unbalanced marker '$marker' in $zshrc — refusing to modify (would corrupt file)"
            return 1
        fi
        backup_file "$zshrc"
        local temp
        temp=$(mktemp)
        awk -v m="$marker" '$0==m{skip=!skip; next} !skip' "$zshrc" > "$temp"
        cp "$temp" "$zshrc"
        rm -f "$temp"
    fi

    {
        echo ""
        echo "$marker"
        cat
        echo "$marker"
    } >> "$zshrc"
}

# Strip a marker-bounded block from $zshrc (no replacement)
_cc_strip_marked_block() {
    local zshrc="$1"
    local marker="$2"

    [[ -f "$zshrc" ]] || return 0
    grep -qF "$marker" "$zshrc" 2>/dev/null || return 0

    if ! _cc_marker_balanced "$zshrc" "$marker"; then
        log_err "Unbalanced marker '$marker' in $zshrc — refusing to strip (would corrupt file)"
        return 1
    fi
    backup_file "$zshrc"

    local temp
    temp=$(mktemp)
    awk -v m="$marker" '$0==m{skip=!skip; next} !skip' "$zshrc" > "$temp"
    cp "$temp" "$zshrc"
    rm -f "$temp"
}

# Environment

_cc_install_env() {
    local source="$CC_CONFIG/env.sh"

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

    _cc_install_env_copy
    log_info "Restart shell to apply"
}

_cc_install_env_copy() {
    local source="$CC_CONFIG/env.sh"
    [[ -f "$source" ]] || return
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Would write env block to .zshrc"
        return
    fi
    grep -v '^#' "$source" | grep -v '^$' \
        | _cc_replace_marked_block "$HOME/.zshrc" "$CC_ENV_MARKER"
    log_ok "Environment variables added to .zshrc"
}

# CLAUDE.md (rule imports)

_cc_install_claude_md() {
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would write rule imports to ~/.claude/CLAUDE.md"
        return
    fi

    log_info "Adds @~/.claude/rules/<rule>.md imports to ~/.claude/CLAUDE.md"
    printf '\n'
    if ! confirm "Write CLAUDE.md rule imports?"; then return; fi

    _cc_install_claude_md_copy
}

_cc_install_claude_md_copy() {
    local rules_dir="$CC_CONFIG/rules"
    local claude_md="$CLAUDE_DIR/CLAUDE.md"

    [[ -d "$rules_dir" ]] || { log_err "No rules dir at $rules_dir"; return; }

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Would write rule imports to $claude_md"
        return
    fi

    _cc_ensure_dir
    [[ -f "$claude_md" ]] || touch "$claude_md"

    local added=0 backed_up=false
    for f in "$rules_dir"/*.md; do
        [[ -f "$f" ]] || continue
        local rule_name
        rule_name="$(basename "$f" .md)"
        local line="@~/.claude/rules/$rule_name.md"
        if ! grep -qF "$line" "$claude_md"; then
            if ! $backed_up; then
                backup_file "$claude_md"
                printf '\n' >> "$claude_md"
                backed_up=true
            fi
            printf '%s\n' "$line" >> "$claude_md"
            added=$((added + 1))
        fi
    done

    if [[ $added -gt 0 ]]; then
        log_ok "CLAUDE.md updated ($added import(s) added)"
    else
        log_skip "CLAUDE.md already has all rule imports"
    fi
}

# 'r' alias

_cc_install_r_alias() {
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would add 'r' alias to .zshrc"
        return
    fi

    log_info "Adds: alias r='bash /tmp/cmd.sh'  (used by workflow rule)"
    printf '\n'
    if ! confirm "Add 'r' alias to .zshrc?"; then return; fi

    _cc_install_r_alias_copy
    log_info "Restart shell to apply"
}

_cc_install_r_alias_copy() {
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Would add 'r' alias to .zshrc"
        return
    fi
    printf "alias r='bash /tmp/cmd.sh'\n" \
        | _cc_replace_marked_block "$HOME/.zshrc" "$CC_RALIAS_MARKER"
    log_ok "'r' alias added to .zshrc"
}

_cc_uninstall_legacy_plugin() {
    printf '\n'
    log_info "Removes:"
    log_info "  enabledPlugins.telegram@... in settings.json"
    log_info "  $HOME/.claude/plugins/{cache,marketplaces}/.../telegram"
    log_info "  $CC_TG_LEGACY_LAUNCH_AGENT, $CC_TG_LEGACY_LAUNCHER (ctg)"
    log_info "  $CC_TG_LEGACY_OLD_PLIST, $CC_TG_LEGACY_OLD_LAUNCHER"
    log_info "  $CC_TG_LEGACY_ENV_FILE (legacy token)"
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would clean up legacy plugin"
        return
    fi
    if ! confirm "Clean up old plugin setup?" "y"; then return; fi
    _cc_uninstall_legacy_plugin_copy
}

_cc_uninstall_legacy_plugin_copy() {
    # 1. Disable plugin in settings.json
    local settings="$CLAUDE_DIR/settings.json"
    if [[ -f "$settings" ]] && command -v jq >/dev/null 2>&1; then
        if jq -e '.enabledPlugins["telegram@claude-plugins-official"]' "$settings" >/dev/null 2>&1; then
            backup_file "$settings"
            local tmp
            tmp=$(mktemp)
            jq 'del(.enabledPlugins["telegram@claude-plugins-official"]) |
                (.permissions.allow // []) |= map(select(test("mcp__plugin_telegram_telegram") | not))' \
                "$settings" > "$tmp"
            mv "$tmp" "$settings"
            log_ok "Disabled plugin in settings.json"
        fi
    fi

    # 2. claude plugin uninstall (best-effort)
    if command -v claude >/dev/null 2>&1; then
        claude plugin uninstall telegram@claude-plugins-official </dev/null >/dev/null 2>&1 || true
    fi

    # 3. installed_plugins.json
    local installed="$HOME/.claude/plugins/installed_plugins.json"
    if [[ -f "$installed" ]] && command -v jq >/dev/null 2>&1; then
        if jq -e '.plugins["telegram@claude-plugins-official"]' "$installed" >/dev/null 2>&1; then
            backup_file "$installed"
            local tmp
            tmp=$(mktemp)
            jq 'del(.plugins["telegram@claude-plugins-official"])' "$installed" > "$tmp"
            mv "$tmp" "$installed"
            log_ok "Removed entry from installed_plugins.json"
        fi
    fi

    # 4. plugin cache + marketplace dir (auto-respawn source)
    rm -rf "$HOME/.claude/plugins/cache/claude-plugins-official/telegram" 2>/dev/null
    rm -rf "$HOME/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/telegram" 2>/dev/null

    # 5. LaunchAgents from both old setups
    launchctl bootout "gui/$UID/$CC_TG_LEGACY_LAUNCH_AGENT_LABEL" 2>/dev/null || true
    launchctl bootout "gui/$UID/$CC_TG_LEGACY_OLD_LABEL" 2>/dev/null || true
    rm -f "$CC_TG_LEGACY_LAUNCH_AGENT" "$CC_TG_LEGACY_OLD_PLIST" \
          "$CC_TG_LEGACY_LAUNCHER" "$CC_TG_LEGACY_OLD_LAUNCHER" \
          "$CC_TG_LEGACY_ENV_FILE"

    # 6. Kill any orphan plugin polling processes
    pkill -9 -f "bun.*server\\.ts" 2>/dev/null || true
    pkill -9 -f "claude.*--channels" 2>/dev/null || true

    log_ok "Legacy plugin cleanup done"
}

# Remove launcher + LaunchAgent (keeps repo + .env so reinstall is fast)


# Reset

_cc_reset() {
    clear
    printf '\n'
    printf '  %bClaude Code — Reset%b\n\n' "$BOLD" "$RESET"
    printf '  Will %bDELETE%b:\n' "$RED" "$RESET"
    printf '    %s/settings.json (+ .bak)\n' "$CLAUDE_DIR"
    printf '    %s/settings.local.json\n' "$CLAUDE_DIR"
    printf '    %s/CLAUDE.md\n' "$CLAUDE_DIR"
    printf '    %s/env.sh\n' "$CLAUDE_DIR"
    printf '    %s/statusline.sh (+ .bak)\n' "$CLAUDE_DIR"
    printf '    %s/{agents,commands,rules,hooks}/ (incl. *.bak inside)\n' "$CLAUDE_DIR"
    printf '    macrift sections in ~/.zshrc (env block + r-alias block)\n\n'
    printf '  Will %bPRESERVE%b: sessions, history, projects, plugins, channels, cache\n\n' "$GREEN" "$RESET"

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would wipe Claude Code state"
        return
    fi

    if ! confirm "Confirm full reset?" "n"; then
        log_skip "Reset cancelled"
        return
    fi

    rm -f "$CLAUDE_DIR/settings.json" "$CLAUDE_DIR/settings.json.bak" \
          "$CLAUDE_DIR/settings.local.json" "$CLAUDE_DIR/CLAUDE.md" \
          "$CLAUDE_DIR/CLAUDE.md.bak" "$CLAUDE_DIR/env.sh" \
          "$CLAUDE_DIR/statusline.sh" "$CLAUDE_DIR/statusline.sh.bak"
    rm -rf "$CLAUDE_DIR/agents" "$CLAUDE_DIR/commands" "$CLAUDE_DIR/rules" "$CLAUDE_DIR/hooks"

    _cc_strip_marked_block "$HOME/.zshrc" "$CC_ENV_MARKER"
    _cc_strip_marked_block "$HOME/.zshrc" "$CC_RALIAS_MARKER"

    log_ok "Claude Code state wiped"

    # Telegram legacy plugin artifacts — opt-in cleanup (separate confirm so
    # token isn't nuked by accident; the active engine has its own remove flow)
    local has_legacy=false
    [[ -e "$CC_TG_LEGACY_LAUNCH_AGENT" || -e "$CC_TG_LEGACY_OLD_PLIST" \
        || -e "$CC_TG_LEGACY_LAUNCHER" || -e "$CC_TG_LEGACY_OLD_LAUNCHER" \
        || -e "$CC_TG_LEGACY_ENV_FILE" ]] && has_legacy=true

    if $has_legacy; then
        printf '\n'
        log_info "Legacy plugin artifacts:"
        [[ -e "$CC_TG_LEGACY_LAUNCH_AGENT" ]]   && printf '    %s\n' "$CC_TG_LEGACY_LAUNCH_AGENT"
        [[ -e "$CC_TG_LEGACY_OLD_PLIST" ]]      && printf '    %s\n' "$CC_TG_LEGACY_OLD_PLIST"
        [[ -e "$CC_TG_LEGACY_LAUNCHER" ]]       && printf '    %s\n' "$CC_TG_LEGACY_LAUNCHER"
        [[ -e "$CC_TG_LEGACY_OLD_LAUNCHER" ]]   && printf '    %s\n' "$CC_TG_LEGACY_OLD_LAUNCHER"
        [[ -e "$CC_TG_LEGACY_ENV_FILE" ]]       && printf '    %s (bot token)\n' "$CC_TG_LEGACY_ENV_FILE"
        printf '\n'
        if confirm "Also wipe legacy plugin remnants?" "n"; then
            _cc_uninstall_legacy_plugin_copy
        fi
    fi

    if grep -qF "$CC_TG_PATH_MARKER" "$HOME/.zshrc" 2>/dev/null; then
        if confirm "Strip ~/.local/bin PATH block from ~/.zshrc?" "n"; then
            _cc_strip_marked_block "$HOME/.zshrc" "$CC_TG_PATH_MARKER"
            log_ok "PATH block stripped"
        fi
    fi

    log_info "Run Full Setup to reinstall"
}

# Helpers

_cc_ensure_dir() {
    mkdir -p "$CLAUDE_DIR"
}
