#!/usr/bin/env bash
# macrift — Claude Code setup

CLAUDE_DIR="$HOME/.claude"
CC_CONFIG="$MACRIFT_DIR/config/claude-code"
CC_ENV_MARKER="# macrift:claude-code env"
CC_RALIAS_MARKER="# macrift:claude-code r-alias"

# Telegram bridge (anthropics/claude-plugins-official telegram plugin)
CC_TG_LAUNCHER="$HOME/.local/bin/ctg"
CC_TG_LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.claude-tg.plist"
CC_TG_LAUNCH_AGENT_LABEL="com.claude-tg"
CC_TG_ENV_FILE="$HOME/.claude/channels/telegram/.env"
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
            "Telegram bridge — plugin, token, launcher, autostart" \
            "---" \
            "Reset — wipe macrift-managed Claude state" \
            "Back")

        case "$choice" in
            1)  _cc_full_setup ;;
            2)  _cc_custom_menu ;;
            3)  _cc_telegram_menu ;;
            4)  _cc_reset; wait_enter ;;
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

# Telegram bridge

_cc_telegram_menu() {
    crumb_push "Telegram"
    while true; do
        clear

        local choice
        choice=$(show_menu "Telegram bridge" \
            "Full setup — plugin + token + launcher + autostart" \
            "---" \
            "Plugin only — claude plugin install telegram@…" \
            "Bot token — saved to ~/.claude/channels/telegram/.env (chmod 600)" \
            "Launcher 'ctg' — ~/.local/bin/ctg" \
            "Autostart on login — LaunchAgent" \
            "---" \
            "Remove launcher + autostart (keeps token)" \
            "Back")

        case "$choice" in
            1)  _cc_install_tg_full; wait_enter ;;
            2)  _cc_install_tg_plugin; wait_enter ;;
            3)  _cc_install_tg_token; wait_enter ;;
            4)  _cc_install_tg_launcher; wait_enter ;;
            5)  _cc_install_tg_launchagent; wait_enter ;;
            6)  _cc_remove_tg_launcher_autostart; wait_enter ;;
            0)  break ;;
            *)  ;;
        esac
    done
    crumb_pop
}

_cc_install_tg_plugin() {
    if ! command -v claude >/dev/null 2>&1; then
        log_err "claude CLI not found. Install: https://claude.com/code"
        return 1
    fi
    printf '\n'
    log_info "Adds anthropics/claude-plugins-official marketplace + installs telegram plugin"
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install plugin"
        return
    fi
    if ! confirm "Install Telegram plugin?"; then return; fi
    _cc_install_tg_plugin_copy
}

_cc_install_tg_plugin_copy() {
    if ! command -v claude >/dev/null 2>&1; then
        log_err "claude CLI not found"
        return 1
    fi
    if ! claude plugin marketplace list 2>/dev/null | grep -q claude-plugins-official; then
        log_info "Adding marketplace claude-plugins-official…"
        if ! claude plugin marketplace add anthropics/claude-plugins-official </dev/null >/dev/null 2>&1; then
            log_err "Failed to add marketplace"
            return 1
        fi
        log_ok "Marketplace added"
    else
        log_skip "Marketplace already configured"
    fi
    if ! claude plugin list 2>/dev/null | grep -q '^telegram@claude-plugins-official'; then
        log_info "Installing telegram@claude-plugins-official…"
        if ! claude plugin install telegram@claude-plugins-official </dev/null >/dev/null 2>&1; then
            log_err "Failed to install plugin"
            return 1
        fi
        log_ok "Plugin installed"
    else
        log_skip "Plugin already installed"
    fi
}

_cc_install_tg_token() {
    printf '\n'
    log_info "Stores bot token in $CC_TG_ENV_FILE (chmod 600)"
    log_info "Get one from @BotFather: /newbot"
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would prompt for bot token"
        return
    fi

    local existing=""
    if [[ -f "$CC_TG_ENV_FILE" ]]; then
        existing=$(grep -E '^TELEGRAM_BOT_TOKEN=' "$CC_TG_ENV_FILE" 2>/dev/null | tail -1 \
                   | sed 's/^TELEGRAM_BOT_TOKEN=//' | tr -d '"' | tr -d "'")
    fi
    if [[ -n "$existing" ]]; then
        log_info "Existing token: ${existing%%:*}:…${existing: -4}"
        if ! confirm "Replace it?" "n"; then
            log_skip "Token unchanged"
            return
        fi
    fi

    local token
    printf '  Bot token: '
    read -r token
    if [[ ! "$token" =~ ^[0-9]+:[A-Za-z0-9_-]{30,}$ ]]; then
        log_err "Invalid token format (expected NNNNN:AA…)"
        return 1
    fi

    if command -v curl >/dev/null 2>&1; then
        local resp
        resp=$(curl -fsSL --max-time 8 "https://api.telegram.org/bot${token}/getMe" 2>/dev/null || true)
        if [[ "$resp" == *'"ok":true'* ]]; then
            local username
            username=$(printf '%s' "$resp" | sed -n 's/.*"username":"\([^"]*\)".*/\1/p')
            log_ok "Bot verified: @$username (https://t.me/$username)"
        else
            log_warn "Could not verify online — saving anyway"
        fi
    fi

    mkdir -p "$(dirname "$CC_TG_ENV_FILE")"
    if [[ -f "$CC_TG_ENV_FILE" ]]; then
        backup_file "$CC_TG_ENV_FILE"
        local tmp
        tmp=$(mktemp)
        grep -v '^TELEGRAM_BOT_TOKEN=' "$CC_TG_ENV_FILE" >"$tmp" 2>/dev/null || true
        printf 'TELEGRAM_BOT_TOKEN=%s\n' "$token" >>"$tmp"
        mv "$tmp" "$CC_TG_ENV_FILE"
    else
        printf 'TELEGRAM_BOT_TOKEN=%s\n' "$token" >"$CC_TG_ENV_FILE"
    fi
    chmod 600 "$CC_TG_ENV_FILE"
    log_ok "Token saved to $CC_TG_ENV_FILE"
}

_cc_install_tg_launcher() {
    if ! command -v claude >/dev/null 2>&1; then
        log_err "claude CLI not found"
        return 1
    fi
    if ! command -v bun >/dev/null 2>&1; then
        log_err "bun not found. Install: curl -fsSL https://bun.sh/install | bash"
        return 1
    fi
    printf '\n'
    log_info "Creates $CC_TG_LAUNCHER — runs: claude --channels plugin:telegram@…"
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install launcher"
        return
    fi
    if ! confirm "Install ctg launcher?"; then return; fi
    _cc_install_tg_launcher_copy
}

_cc_install_tg_launcher_copy() {
    local claude_bin bun_bin
    claude_bin=$(command -v claude || true)
    bun_bin=$(command -v bun || true)
    if [[ -z "$claude_bin" || -z "$bun_bin" ]]; then
        log_err "claude or bun not found — cannot bake launcher"
        return 1
    fi

    local path_dirs=("$(dirname "$claude_bin")" "$(dirname "$bun_bin")" "/opt/homebrew/bin" "/usr/local/bin")
    local path_line="" seen=":"
    local d
    for d in "${path_dirs[@]}"; do
        case "$seen" in *":$d:"*) ;; *) path_line+="$d:"; seen+="$d:" ;; esac
    done
    path_line="${path_line%:}"

    mkdir -p "$(dirname "$CC_TG_LAUNCHER")"
    cat >"$CC_TG_LAUNCHER" <<SH
#!/bin/zsh
export PATH="$path_line:\$PATH"
exec "$claude_bin" --channels plugin:telegram@claude-plugins-official
SH
    chmod +x "$CC_TG_LAUNCHER"
    log_ok "Launcher installed: $CC_TG_LAUNCHER"

    _cc_ensure_local_bin_on_path
}

# Idempotent: writes a marker-bounded `export PATH=…` block to ~/.zshrc only if
# ~/.local/bin isn't already on PATH (current shell or .zshrc text). Re-running
# replaces the macrift block in place; user-added PATH lines are left alone.
_cc_ensure_local_bin_on_path() {
    case ":$PATH:" in
        *":$HOME/.local/bin:"*)
            log_info "~/.local/bin already on PATH — run: ctg"
            return
            ;;
    esac

    local zshrc="$HOME/.zshrc"
    # If user has their own .local/bin entry (not ours), don't fight it — just inform.
    if [[ -f "$zshrc" ]] && grep -q '\.local/bin' "$zshrc" 2>/dev/null \
        && ! grep -qF "$CC_TG_PATH_MARKER" "$zshrc" 2>/dev/null; then
        log_warn "~/.local/bin appears in ~/.zshrc but isn't active in current shell"
        log_info "Run: source ~/.zshrc  (or open a new terminal)"
        return
    fi

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Would add ~/.local/bin to PATH in $zshrc"
        return
    fi

    printf 'export PATH="$HOME/.local/bin:$PATH"\n' \
        | _cc_replace_marked_block "$zshrc" "$CC_TG_PATH_MARKER"
    log_ok "Added ~/.local/bin to PATH in ~/.zshrc"
    log_info "Run: source ~/.zshrc  (or open a new terminal) — then: ctg"
}

_cc_install_tg_launchagent() {
    if [[ ! -x "$CC_TG_LAUNCHER" ]]; then
        log_err "Launcher missing at $CC_TG_LAUNCHER — install it first"
        return 1
    fi
    printf '\n'
    log_info "Opens claude+telegram on login via Ghostty (or Terminal)"
    log_info "plist: $CC_TG_LAUNCH_AGENT"
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install LaunchAgent"
        return
    fi
    if ! confirm "Install autostart?"; then return; fi
    _cc_install_tg_launchagent_copy
}

_cc_install_tg_launchagent_copy() {
    local term="/Applications/Ghostty.app"
    [[ -d "$term" ]] || term="/System/Applications/Utilities/Terminal.app"
    log_info "Terminal app: $term"

    cat >"$CC_TG_LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$CC_TG_LAUNCH_AGENT_LABEL</string>
  <key>ProgramArguments</key><array>
    <string>/usr/bin/open</string><string>-na</string><string>$term</string>
    <string>--args</string><string>-e</string><string>$CC_TG_LAUNCHER</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>/tmp/claude-tg.log</string>
  <key>StandardErrorPath</key><string>/tmp/claude-tg.err</string>
</dict></plist>
PLIST

    if ! plutil -lint "$CC_TG_LAUNCH_AGENT" >/dev/null 2>&1; then
        log_err "Generated plist is invalid"
        return 1
    fi
    launchctl bootout "gui/$UID/$CC_TG_LAUNCH_AGENT_LABEL" 2>/dev/null || true
    if ! launchctl bootstrap "gui/$UID" "$CC_TG_LAUNCH_AGENT" 2>/tmp/claude-tg.boot.err; then
        log_err "launchctl bootstrap failed:"
        cat /tmp/claude-tg.boot.err 2>/dev/null
        return 1
    fi
    log_ok "Autostart installed"
}

_cc_install_tg_full() {
    printf '\n'
    log_info "Full Telegram bridge install: plugin + token + launcher + autostart"
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would run all four steps"
        return
    fi
    if ! confirm "Run full Telegram bridge setup?"; then return; fi

    _cc_install_tg_plugin_copy   || return
    _cc_install_tg_token         || return
    _cc_install_tg_launcher_copy || return
    if confirm "Enable autostart on login?"; then
        _cc_install_tg_launchagent_copy || return
    fi

    printf '\n'
    log_ok "Telegram bridge ready"
    log_info "Run 'ctg' anytime. In Telegram: message your bot, copy the 6-char code,"
    log_info "then in Claude say: pair me with code <CODE>"
}

_cc_remove_tg_launcher_autostart() {
    printf '\n'
    log_info "Removes ctg launcher and LaunchAgent. Token at $CC_TG_ENV_FILE preserved."
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would remove launcher and LaunchAgent"
        return
    fi
    if ! confirm "Remove launcher and autostart?" "n"; then
        log_skip "Removal cancelled"
        return
    fi
    launchctl bootout "gui/$UID/$CC_TG_LAUNCH_AGENT_LABEL" 2>/dev/null || true
    rm -f "$CC_TG_LAUNCH_AGENT" "$CC_TG_LAUNCHER"
    log_ok "Launcher and autostart removed"
}

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

    # Telegram bridge — opt-in (separate confirm so token isn't nuked by accident)
    if [[ -e "$CC_TG_LAUNCHER" || -e "$CC_TG_LAUNCH_AGENT" || -e "$CC_TG_ENV_FILE" ]] \
        || grep -qF "$CC_TG_PATH_MARKER" "$HOME/.zshrc" 2>/dev/null; then
        printf '\n'
        log_info "Telegram bridge artifacts also present:"
        [[ -e "$CC_TG_LAUNCHER" ]]     && printf '    %s\n' "$CC_TG_LAUNCHER"
        [[ -e "$CC_TG_LAUNCH_AGENT" ]] && printf '    %s\n' "$CC_TG_LAUNCH_AGENT"
        [[ -e "$CC_TG_ENV_FILE" ]]     && printf '    %s (bot token)\n' "$CC_TG_ENV_FILE"
        grep -qF "$CC_TG_PATH_MARKER" "$HOME/.zshrc" 2>/dev/null \
            && printf '    PATH block in ~/.zshrc\n'
        printf '\n'
        if confirm "Also wipe Telegram bridge?" "n"; then
            launchctl bootout "gui/$UID/$CC_TG_LAUNCH_AGENT_LABEL" 2>/dev/null || true
            rm -f "$CC_TG_LAUNCH_AGENT" "$CC_TG_LAUNCHER" "$CC_TG_ENV_FILE"
            _cc_strip_marked_block "$HOME/.zshrc" "$CC_TG_PATH_MARKER"
            log_ok "Telegram bridge wiped"
        else
            log_skip "Telegram bridge preserved"
        fi
    fi

    log_info "Run Full Setup to reinstall"
}

# Helpers

_cc_ensure_dir() {
    mkdir -p "$CLAUDE_DIR"
}
