#!/usr/bin/env bash
# macrift — Claude Code setup

CLAUDE_DIR="$HOME/.claude"
CC_CONFIG="$MACRIFT_DIR/config/claude-code"
CC_ENV_MARKER="# macrift:claude-code env"
CC_RALIAS_MARKER="# macrift:claude-code r-alias"

# Telegram bot (linuz90/claude-telegram-bot)
# Replaces the old anthropics/claude-plugins-official telegram plugin approach,
# which was unreliable: 409 conflicts when multiple claude sessions opened, no
# way to attach to running session, MCP server died on idle. linuz90's bot
# runs as a standalone Bun process via Claude Agent SDK CLI auth.
CC_TGBOT_REPO_URL="https://github.com/linuz90/claude-telegram-bot"
CC_TGBOT_DIR="$HOME/Documents/Code/Claude/claude-telegram-bot"
CC_TGBOT_LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.claude-telegram-ts.plist"
CC_TGBOT_LAUNCH_AGENT_LABEL="com.claude-telegram-ts"

# Legacy paths from the old plugin setup — kept here so cleanup can find them.
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
            "Telegram bot — linuz90/claude-telegram-bot setup" \
            "---" \
            "Reset — wipe macrift-managed Claude state" \
            "Back")

        case "$choice" in
            1)  _cc_full_setup ;;
            2)  _cc_custom_menu ;;
            3)  _cc_tgbot_menu ;;
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

# Telegram bot (linuz90/claude-telegram-bot)

_cc_tgbot_menu() {
    crumb_push "Telegram"
    while true; do
        clear

        local choice
        choice=$(show_menu "Telegram bot" \
            "Full setup — clone, configure, patch, autostart" \
            "---" \
            "Clone repo + bun install" \
            "Configure .env (token + user_id)" \
            "Patch source (fix grammy 409 conflicts)" \
            "Update Claude Agent SDK to latest" \
            "Install LaunchAgent (autostart on login)" \
            "---" \
            "Migrate from old plugin (cleanup remnants)" \
            "Remove launcher + autostart" \
            "Back")

        case "$choice" in
            1)  _cc_install_tgbot_full; wait_enter ;;
            2)  _cc_install_tgbot_clone; wait_enter ;;
            3)  _cc_install_tgbot_env; wait_enter ;;
            4)  _cc_install_tgbot_patch; wait_enter ;;
            5)  _cc_install_tgbot_sdk_update; wait_enter ;;
            6)  _cc_install_tgbot_launchagent; wait_enter ;;
            7)  _cc_uninstall_legacy_plugin; wait_enter ;;
            8)  _cc_remove_tgbot; wait_enter ;;
            0)  break ;;
            *)  ;;
        esac
    done
    crumb_pop
}

# Clone + bun install

_cc_install_tgbot_clone() {
    if ! command -v git >/dev/null 2>&1; then
        log_err "git not found"
        return 1
    fi
    if ! command -v bun >/dev/null 2>&1; then
        log_err "bun not found. Install: curl -fsSL https://bun.sh/install | bash"
        return 1
    fi
    printf '\n'
    log_info "Clones $CC_TGBOT_REPO_URL into $CC_TGBOT_DIR + runs bun install"
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would clone repo"
        return
    fi
    if ! confirm "Clone the bot repo?"; then return; fi
    _cc_install_tgbot_clone_copy
}

_cc_install_tgbot_clone_copy() {
    if [[ -d "$CC_TGBOT_DIR" ]]; then
        log_skip "$CC_TGBOT_DIR already exists, pulling latest"
        if ! git -C "$CC_TGBOT_DIR" pull --ff-only 2>&1 | tail -5; then
            log_warn "git pull failed — leaving repo as is"
        fi
    else
        mkdir -p "$(dirname "$CC_TGBOT_DIR")"
        if ! git clone "$CC_TGBOT_REPO_URL" "$CC_TGBOT_DIR" 2>&1 | tail -5; then
            log_err "git clone failed"
            return 1
        fi
        log_ok "Cloned to $CC_TGBOT_DIR"
    fi

    log_info "Running bun install..."
    if ! ( cd "$CC_TGBOT_DIR" && bun install --no-summary 2>&1 | tail -5 ); then
        log_err "bun install failed"
        return 1
    fi
    log_ok "Dependencies installed"
}

# Configure .env (token + user_id)

_cc_install_tgbot_env() {
    if [[ ! -d "$CC_TGBOT_DIR" ]]; then
        log_err "Bot repo not found. Run Clone first."
        return 1
    fi
    printf '\n'
    log_info "Bot token from @BotFather, your numeric Telegram ID from @userinfobot"
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would configure .env"
        return
    fi
    if ! confirm "Configure .env now?"; then return; fi
    _cc_install_tgbot_env_copy
}

_cc_install_tgbot_env_copy() {
    local env_file="$CC_TGBOT_DIR/.env"

    # Token
    local existing_token=""
    if [[ -f "$env_file" ]]; then
        existing_token=$(grep -E '^TELEGRAM_BOT_TOKEN=' "$env_file" 2>/dev/null \
                         | tail -1 | sed 's/^TELEGRAM_BOT_TOKEN=//' | tr -d '"' | tr -d "'")
    fi
    local token="$existing_token"
    if [[ -n "$existing_token" ]]; then
        log_info "Existing token: ${existing_token%%:*}:…${existing_token: -4}"
        if confirm "Replace it?" "n"; then token=""; fi
    fi
    if [[ -z "$token" ]]; then
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
                log_ok "Bot verified: @$username"
            else
                log_warn "Could not verify online — saving anyway"
            fi
        fi
    fi

    # User ID — auto-detect from old plugin's access.json if present
    local user_id=""
    local legacy_access="$HOME/.claude/channels/telegram/access.json"
    if [[ -f "$legacy_access" ]] && command -v jq >/dev/null 2>&1; then
        user_id=$(jq -r '.allowFrom[0] // empty' "$legacy_access" 2>/dev/null)
        [[ -n "$user_id" ]] && log_info "Found paired user_id $user_id in legacy access.json"
    fi
    if [[ -z "$user_id" ]]; then
        printf '  Your Telegram user ID (numeric, from @userinfobot): '
        read -r user_id
    fi
    if [[ ! "$user_id" =~ ^[0-9]+$ ]]; then
        log_err "Invalid user_id (expected numeric)"
        return 1
    fi

    # Resolve claude binary path for SDK
    local claude_bin
    claude_bin=$(command -v claude || echo "")
    if [[ -z "$claude_bin" ]]; then
        log_warn "claude CLI not on PATH — SDK may not find it. Run 'claude' once to authenticate."
    fi

    local working_dir="${CLAUDE_WORKING_DIR:-$HOME/Documents/Code}"

    [[ -f "$env_file" ]] && backup_file "$env_file"
    cat > "$env_file" <<ENV
TELEGRAM_BOT_TOKEN=$token
TELEGRAM_ALLOWED_USERS=$user_id
CLAUDE_WORKING_DIR=$working_dir
ALLOWED_PATHS=$HOME/Documents,$HOME/Downloads,$HOME/Desktop,$HOME/.claude
CLAUDE_CODE_PATH=$claude_bin
ENV
    chmod 600 "$env_file"
    log_ok "Wrote $env_file (chmod 600)"
}

# Patch source — fixes the 409 conflicts we hit

_cc_install_tgbot_patch() {
    if [[ ! -f "$CC_TGBOT_DIR/src/index.ts" ]]; then
        log_err "src/index.ts not found in $CC_TGBOT_DIR. Run Clone first."
        return 1
    fi
    printf '\n'
    log_info "Replaces run(bot) → bot.start() and removes sequentialize middleware."
    log_info "Both pull in @grammyjs/runner internals that spawn a competing"
    log_info "getUpdates loop — Telegram rejects this with 409 conflicts."
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would patch src/index.ts"
        return
    fi
    if ! confirm "Apply patch to src/index.ts?"; then return; fi
    _cc_install_tgbot_patch_copy
}

_cc_install_tgbot_patch_copy() {
    local index_ts="$CC_TGBOT_DIR/src/index.ts"
    local session_ts="$CC_TGBOT_DIR/src/session.ts"

    # Patch session.ts (two fixes):
    #  1. systemPrompt → appendSystemPrompt so SDK keeps its default system
    #     prompt (which loads ~/.claude/CLAUDE.md via settingSources) and just
    #     adds linuz90's safety rules on top.
    #  2. mcpServers: MCP_SERVERS → conditional spread. The explicit empty {}
    #     overrides SDK's plugin discovery, so enabledPlugins from user settings
    #     (github, etc) wouldn't reach the bot's claude. Conditional spread lets
    #     them through when no override is configured.
    if [[ -f "$session_ts" ]] && grep -q '^      systemPrompt: SAFETY_PROMPT,$' "$session_ts"; then
        backup_file "$session_ts"
        sed -i '' 's/^      systemPrompt: SAFETY_PROMPT,$/      appendSystemPrompt: SAFETY_PROMPT,/' "$session_ts"
        log_ok "Patched session.ts (systemPrompt → appendSystemPrompt)"
    fi
    if [[ -f "$session_ts" ]] && grep -q '^      mcpServers: MCP_SERVERS,$' "$session_ts"; then
        backup_file "$session_ts"
        sed -i '' 's|^      mcpServers: MCP_SERVERS,$|      ...(Object.keys(MCP_SERVERS).length > 0 ? { mcpServers: MCP_SERVERS } : {}),|' "$session_ts"
        log_ok "Patched session.ts (mcpServers conditional — lets enabledPlugins through)"
    fi

    # Idempotency check for index.ts: patch already applied if `bot.start({` is
    # in file AND the original `run(bot)` is gone.
    if grep -q '^bot\.start({' "$index_ts" && ! grep -q '^const runner = run(bot)' "$index_ts"; then
        log_skip "index.ts patch already applied"
        return 0
    fi

    backup_file "$index_ts"

    # Remove sequentialize middleware (keep import for other uses if any)
    # Replace import line: drop `run,`
    sed -i '' \
        -e 's/import { run, sequentialize } from "@grammyjs\/runner";/import { sequentialize } from "@grammyjs\/runner";/' \
        "$index_ts"

    # Replace `const runner = run(bot);` with `bot.start({...})`
    # And replace stopRunner block
    local tmp
    tmp=$(mktemp)
    awk '
        /^const runner = run\(bot\);/ {
            print "// PATCHED by macrift: use bot.start() (single fetcher) instead of run(bot)."
            print "// run(bot) caused concurrent getUpdates → 409 conflicts."
            print "bot.start({"
            print "  onStart: (info) => console.log(`Bot polling: @${info.username}`),"
            print "});"
            next
        }
        /^const stopRunner = \(\) => \{$/ {
            print "// PATCHED by macrift: simplified shutdown (no runner to check)."
            print "const stopRunner = () => {"
            print "  console.log(\"Stopping bot...\");"
            print "  bot.stop();"
            print "};"
            in_stop = 1
            next
        }
        in_stop && /^};$/ { in_stop = 0; next }
        in_stop { next }
        { print }
    ' "$index_ts" > "$tmp"

    # Comment out bot.use(sequentialize(...)) block — multi-line.
    # The block opens with `bot.use(\n  sequentialize((ctx) => {` and closes with `})`.
    awk '
        /^bot\.use\($/ { in_use = 1; print "/* PATCHED by macrift: sequentialize disabled — see runner patch above"; print; next }
        in_use && /^\);$/ { print; print "*/"; in_use = 0; next }
        { print }
    ' "$tmp" > "$index_ts"
    rm -f "$tmp"

    log_ok "Patched $index_ts (backup: ${index_ts##*/}.bak)"
}

# Update SDK — required because 0.1.76 has error_during_execution bug fixed in 0.1.77+

_cc_install_tgbot_sdk_update() {
    if [[ ! -d "$CC_TGBOT_DIR" ]]; then
        log_err "Bot repo not found"
        return 1
    fi
    if ! command -v bun >/dev/null 2>&1; then
        log_err "bun not found"
        return 1
    fi
    printf '\n'
    log_info "@anthropic-ai/claude-agent-sdk 0.1.76 has an error_during_execution bug"
    log_info "(SDK returns empty/fake result events). Fixed in 0.1.77+."
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would update SDK"
        return
    fi
    if ! confirm "Update SDK to latest?"; then return; fi
    _cc_install_tgbot_sdk_update_copy
}

_cc_install_tgbot_sdk_update_copy() {
    log_info "Running bun update..."
    if ! ( cd "$CC_TGBOT_DIR" && bun update @anthropic-ai/claude-agent-sdk --no-cache 2>&1 | tail -5 ); then
        log_err "bun update failed"
        return 1
    fi
    if command -v jq >/dev/null 2>&1; then
        local v
        v=$(jq -r .version "$CC_TGBOT_DIR/node_modules/@anthropic-ai/claude-agent-sdk/package.json" 2>/dev/null)
        log_ok "SDK now at $v"
    else
        log_ok "SDK updated"
    fi
}

# LaunchAgent — autostart on login + auto-restart on crash

_cc_install_tgbot_launchagent() {
    if [[ ! -f "$CC_TGBOT_DIR/.env" ]]; then
        log_err ".env missing. Configure it first."
        return 1
    fi
    if [[ ! -f "$CC_TGBOT_DIR/src/index.ts" ]]; then
        log_err "src/index.ts missing. Clone first."
        return 1
    fi
    printf '\n'
    log_info "plist: $CC_TGBOT_LAUNCH_AGENT"
    log_info "logs:  /tmp/claude-telegram-bot-ts.{log,err}"
    log_info "KeepAlive=true (auto-restart on crash); RunAtLoad=true (start on login)"
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install LaunchAgent"
        return
    fi
    if ! confirm "Install autostart?"; then return; fi
    _cc_install_tgbot_launchagent_copy
}

_cc_install_tgbot_launchagent_copy() {
    local env_file="$CC_TGBOT_DIR/.env"
    local bun_bin
    bun_bin=$(command -v bun || echo /Users/$USER/.bun/bin/bun)

    # Read each env var so we can bake them into the plist (launchd doesn't read .env)
    local token users wd ap cc_path
    token=$(grep -E '^TELEGRAM_BOT_TOKEN=' "$env_file" | tail -1 | sed 's/^TELEGRAM_BOT_TOKEN=//')
    users=$(grep -E '^TELEGRAM_ALLOWED_USERS=' "$env_file" | tail -1 | sed 's/^TELEGRAM_ALLOWED_USERS=//')
    wd=$(grep -E '^CLAUDE_WORKING_DIR=' "$env_file" | tail -1 | sed 's/^CLAUDE_WORKING_DIR=//')
    ap=$(grep -E '^ALLOWED_PATHS=' "$env_file" | tail -1 | sed 's/^ALLOWED_PATHS=//')
    cc_path=$(grep -E '^CLAUDE_CODE_PATH=' "$env_file" | tail -1 | sed 's/^CLAUDE_CODE_PATH=//')

    cat > "$CC_TGBOT_LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$CC_TGBOT_LAUNCH_AGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$bun_bin</string>
        <string>run</string>
        <string>$CC_TGBOT_DIR/src/index.ts</string>
    </array>
    <key>WorkingDirectory</key><string>$CC_TGBOT_DIR</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>TELEGRAM_BOT_TOKEN</key><string>$token</string>
        <key>TELEGRAM_ALLOWED_USERS</key><string>$users</string>
        <key>CLAUDE_WORKING_DIR</key><string>$wd</string>
        <key>ALLOWED_PATHS</key><string>$ap</string>
        <key>CLAUDE_CODE_PATH</key><string>$cc_path</string>
        <key>RATE_LIMIT_ENABLED</key><string>true</string>
        <key>RATE_LIMIT_REQUESTS</key><string>40</string>
        <key>RATE_LIMIT_WINDOW</key><string>60</string>
        <key>PATH</key>
        <string>$HOME/.bun/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
    <key>KeepAlive</key><true/>
    <key>RunAtLoad</key><true/>
    <key>StandardOutPath</key><string>/tmp/claude-telegram-bot-ts.log</string>
    <key>StandardErrorPath</key><string>/tmp/claude-telegram-bot-ts.err</string>
</dict>
</plist>
PLIST

    if ! plutil -lint "$CC_TGBOT_LAUNCH_AGENT" >/dev/null 2>&1; then
        log_err "Generated plist is invalid"
        plutil -lint "$CC_TGBOT_LAUNCH_AGENT"
        return 1
    fi

    launchctl bootout "gui/$UID/$CC_TGBOT_LAUNCH_AGENT_LABEL" 2>/dev/null || true
    if ! launchctl bootstrap "gui/$UID" "$CC_TGBOT_LAUNCH_AGENT" 2>/tmp/cc-tgbot-bootstrap.err; then
        log_err "launchctl bootstrap failed:"
        cat /tmp/cc-tgbot-bootstrap.err 2>/dev/null
        return 1
    fi
    launchctl kickstart -k "gui/$UID/$CC_TGBOT_LAUNCH_AGENT_LABEL" 2>/dev/null || true
    log_ok "LaunchAgent installed and started"
}

# Full setup — orchestrates all steps

_cc_install_tgbot_full() {
    printf '\n'
    log_info "Full setup: clone → bun install → .env → patch → SDK update → LaunchAgent"
    log_info "Optional: legacy plugin cleanup if old setup detected."
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would run all steps"
        return
    fi
    if ! confirm "Run full setup?"; then return; fi

    # If old plugin artifacts exist, offer cleanup first (otherwise 409)
    if [[ -e "$CC_TG_LEGACY_LAUNCH_AGENT" || -e "$CC_TG_LEGACY_OLD_PLIST" ]] \
        || jq -e '.enabledPlugins["telegram@claude-plugins-official"]' "$CLAUDE_DIR/settings.json" >/dev/null 2>&1; then
        printf '\n'
        log_warn "Old plugin setup detected — would cause 409 conflicts."
        if confirm "Clean it up first?" "y"; then
            _cc_uninstall_legacy_plugin_copy
        fi
    fi

    _cc_install_tgbot_clone_copy        || return 1
    _cc_install_tgbot_env_copy          || return 1
    _cc_install_tgbot_patch_copy        || return 1
    _cc_install_tgbot_sdk_update_copy   || return 1
    if confirm "Install autostart on login?"; then
        _cc_install_tgbot_launchagent_copy || return 1
    fi

    printf '\n'
    log_ok "Telegram bot ready"
    log_info "Logs: tail -f /tmp/claude-telegram-bot-ts.log"
    log_info "Restart: launchctl kickstart -k gui/\$UID/$CC_TGBOT_LAUNCH_AGENT_LABEL"
}

# Migration cleanup — wipe everything from the old plugin setup

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

_cc_remove_tgbot() {
    printf '\n'
    log_info "Removes LaunchAgent. Repo at $CC_TGBOT_DIR and its .env are preserved."
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would remove LaunchAgent"
        return
    fi
    if ! confirm "Remove LaunchAgent?" "n"; then
        log_skip "Removal cancelled"
        return
    fi
    launchctl bootout "gui/$UID/$CC_TGBOT_LAUNCH_AGENT_LABEL" 2>/dev/null || true
    rm -f "$CC_TGBOT_LAUNCH_AGENT"
    pkill -9 -f "$CC_TGBOT_DIR/src/index.ts" 2>/dev/null || true
    log_ok "LaunchAgent removed"
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

    # Telegram bot — opt-in (separate confirms so token + repo aren't nuked by accident)
    local has_new=false has_legacy=false
    [[ -e "$CC_TGBOT_LAUNCH_AGENT" || -d "$CC_TGBOT_DIR" ]] && has_new=true
    [[ -e "$CC_TG_LEGACY_LAUNCH_AGENT" || -e "$CC_TG_LEGACY_OLD_PLIST" \
        || -e "$CC_TG_LEGACY_LAUNCHER" || -e "$CC_TG_LEGACY_OLD_LAUNCHER" \
        || -e "$CC_TG_LEGACY_ENV_FILE" ]] && has_legacy=true

    if $has_new; then
        printf '\n'
        log_info "Telegram bot (linuz90) artifacts:"
        [[ -e "$CC_TGBOT_LAUNCH_AGENT" ]] && printf '    %s\n' "$CC_TGBOT_LAUNCH_AGENT"
        [[ -d "$CC_TGBOT_DIR" ]]          && printf '    %s/ (repo + .env)\n' "$CC_TGBOT_DIR"
        printf '\n'
        if confirm "Also wipe Telegram bot (linuz90)?" "n"; then
            launchctl bootout "gui/$UID/$CC_TGBOT_LAUNCH_AGENT_LABEL" 2>/dev/null || true
            pkill -9 -f "$CC_TGBOT_DIR/src/index.ts" 2>/dev/null || true
            rm -f "$CC_TGBOT_LAUNCH_AGENT"
            if confirm "Also delete repo dir $CC_TGBOT_DIR (you'll lose .env token)?" "n"; then
                rm -rf "$CC_TGBOT_DIR"
            fi
            log_ok "Telegram bot wiped"
        fi
    fi

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
