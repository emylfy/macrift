#!/usr/bin/env bash
# macrift — Claude Code setup

CLAUDE_DIR="$HOME/.claude"
CC_CONFIG="$MACRIFT_DIR/config/claude-code"
CC_ENV_MARKER="# macrift:claude-code env"
CC_RALIAS_MARKER="# macrift:claude-code r-alias"

# Telegram bot — _cc_telegram_menu offers two engines: supercharged or ccbot.
# Engine constants are grouped per engine below.

# CCBot engine (six-ddc/ccmux) — tmux-bridge, parallel sessions per Forum topic.
CC_CCBOT_REPO_URL="https://github.com/six-ddc/ccmux.git"
CC_CCBOT_CONFIG_DIR="$HOME/.ccbot"
CC_CCBOT_LAUNCH_AGENT_LABEL="com.user.ccbot"
CC_CCBOT_LAUNCH_AGENT="$HOME/Library/LaunchAgents/$CC_CCBOT_LAUNCH_AGENT_LABEL.plist"
CC_CCBOT_LAUNCHER="$HOME/.local/bin/ccbot-launcher.sh"

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
            "Telegram bot — choose engine (supercharged / ccbot)" \
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

# Telegram bot — engine selector

_cc_telegram_menu() {
    crumb_push "Telegram"
    while true; do
        clear
        printf '\n'
        printf '  %bChoose engine%b — both manage to ~/.claude/channels/telegram + their own dirs\n\n' "$BOLD" "$RESET"
        printf '  %bsupercharged%b: drop-in over the official anthropic plugin. DM-friendly,\n' "$CYAN" "$RESET"
        printf '    pairing flow with 6-char code, SQLite memory, Telegraph instant view,\n'
        printf '    one shared claude session.  ✓ simpler setup\n\n'
        printf '  %bccbot%b: tmux-bridge. Each Telegram Forum topic = 1 tmux window =\n' "$CYAN" "$RESET"
        printf '    1 standalone claude session. /esc interrupts, desktop continuity\n'
        printf '    via tmux attach.  ✓ parallel sessions, %brequires forum group%b (not DM)\n\n' "$YELLOW" "$RESET"

        local choice
        choice=$(show_menu "Telegram bot" \
            "supercharged — drop-in for anthropic plugin (DM, single session)" \
            "ccbot — tmux-bridge (forum group, parallel sessions per topic)" \
            "Back")

        case "$choice" in
            1)  _cc_supercharged_menu ;;
            2)  _cc_ccbot_menu ;;
            0)  break ;;
            *)  ;;
        esac
    done
    crumb_pop
}

# CCBot engine submenu

_cc_ccbot_menu() {
    crumb_push "ccbot"
    while true; do
        clear

        local choice
        choice=$(show_menu "Telegram bot (ccbot — six-ddc/ccmux)" \
            "Full setup — install + env + hook + autostart" \
            "---" \
            "Check deps (uv, tmux)" \
            "Install ccbot via uv (or upgrade if already installed)" \
            "Configure ~/.ccbot/.env (token + ALLOWED_USERS)" \
            "Install Claude Code SessionStart hook (ccbot hook --install)" \
            "Pairing help (manual TG forum group + BotFather steps)" \
            "Install LaunchAgent (autostart + VPN-wait wrapper)" \
            "---" \
            "Migrate from supercharged (stop launchd, keep repo as fallback)" \
            "Remove ccbot launcher + autostart (keep config + uv tool)" \
            "Back")

        case "$choice" in
            1)  _cc_install_ccbot_full; wait_enter ;;
            2)  _cc_install_ccbot_deps; wait_enter ;;
            3)  _cc_install_ccbot_install; wait_enter ;;
            4)  _cc_install_ccbot_env; wait_enter ;;
            5)  _cc_install_ccbot_hook; wait_enter ;;
            6)  _cc_install_ccbot_pairing_help; wait_enter ;;
            7)  _cc_install_ccbot_launchagent; wait_enter ;;
            8)  _cc_migrate_supercharged_to_ccbot; wait_enter ;;
            9)  _cc_remove_ccbot; wait_enter ;;
            0)  break ;;
            *)  ;;
        esac
    done
    crumb_pop
}

# 1. Deps check (uv + tmux are mandatory; ccbot won't run without them)

_cc_install_ccbot_deps() {
    printf '\n'
    log_info "ccbot needs: uv (Python tool), tmux (terminal multiplexer), claude (Claude Code CLI)"
    printf '\n'

    local missing=()
    if command -v uv >/dev/null 2>&1; then
        log_ok "uv: $(uv --version 2>/dev/null | head -1)"
    else
        log_err "uv not found"
        missing+=("uv")
    fi
    if command -v tmux >/dev/null 2>&1; then
        log_ok "tmux: $(tmux -V)"
    else
        log_err "tmux not found"
        missing+=("tmux")
    fi
    if command -v claude >/dev/null 2>&1; then
        log_ok "claude: $(claude --version 2>/dev/null | head -1)"
    else
        log_err "claude not found — install from https://claude.com/code"
        # claude isn't on brew; user must install separately. Treat as fatal.
        return 1
    fi

    if (( ${#missing[@]} == 0 )); then
        return 0
    fi

    if ! command -v brew >/dev/null 2>&1; then
        log_err "Homebrew not installed — can't auto-install missing deps. Install brew first: https://brew.sh"
        return 1
    fi

    printf '\n'
    log_info "Missing brew packages: ${missing[*]}"
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would run: brew install ${missing[*]}"
        return 1
    fi
    if ! confirm "Install via 'brew install ${missing[*]}'?" "y"; then
        log_skip "Skipped — install manually then re-run"
        return 1
    fi

    if brew install "${missing[@]}" 2>&1 | tail -8; then
        log_ok "brew install completed"
    else
        log_err "brew install failed"
        return 1
    fi

    # Re-verify
    local still_missing=0
    for pkg in "${missing[@]}"; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            log_err "$pkg still not found after install"
            still_missing=1
        fi
    done
    return $still_missing
}

# 2. Install ccbot via uv tool

_cc_install_ccbot_install() {
    if ! command -v uv >/dev/null 2>&1; then
        log_err "uv not found — install: brew install uv"
        return 1
    fi
    printf '\n'
    log_info "Installs ccbot from $CC_CCBOT_REPO_URL via 'uv tool install'."
    log_info "If already installed, runs 'uv tool upgrade ccbot' to pull latest."
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install ccbot"
        return
    fi
    if ! confirm "Install / upgrade ccbot?"; then return; fi
    _cc_install_ccbot_install_copy
}

_cc_install_ccbot_install_copy() {
    if uv tool list 2>/dev/null | grep -q '^ccbot'; then
        log_info "Upgrading ccbot..."
        uv tool upgrade ccbot 2>&1 | tail -3 || \
            uv tool install --reinstall "git+$CC_CCBOT_REPO_URL" 2>&1 | tail -3
    else
        log_info "Installing ccbot..."
        uv tool install "git+$CC_CCBOT_REPO_URL" 2>&1 | tail -3
    fi

    if command -v ccbot >/dev/null 2>&1; then
        log_ok "ccbot binary at: $(command -v ccbot)"
    else
        log_warn "ccbot installed but not in PATH. Add to ~/.zshrc:"
        log_warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        _cc_ensure_local_bin_on_path 2>/dev/null || true
    fi
}

# 3. Configure ~/.ccbot/.env

_cc_install_ccbot_env() {
    printf '\n'
    log_info "Stores token + allowed user(s) in $CC_CCBOT_CONFIG_DIR/.env (chmod 600)."
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would prompt for token + user_id"
        return
    fi
    _cc_install_ccbot_env_copy
}

_cc_install_ccbot_env_copy() {
    local env_file="$CC_CCBOT_CONFIG_DIR/.env"
    mkdir -p "$CC_CCBOT_CONFIG_DIR"

    # Token — try to reuse from supercharged if available
    local existing_token=""
    if [[ -f "$env_file" ]]; then
        existing_token=$(grep -E '^TELEGRAM_BOT_TOKEN=' "$env_file" 2>/dev/null | tail -1 \
                         | sed 's/^TELEGRAM_BOT_TOKEN=//' | tr -d '"' | tr -d "'")
    fi
    if [[ -z "$existing_token" ]] && [[ -f "$HOME/.claude/channels/telegram/.env" ]]; then
        existing_token=$(grep -E '^TELEGRAM_BOT_TOKEN=' "$HOME/.claude/channels/telegram/.env" 2>/dev/null | tail -1 \
                         | sed 's/^TELEGRAM_BOT_TOKEN=//' | tr -d '"' | tr -d "'")
        [[ -n "$existing_token" ]] && log_info "Reusing token from supercharged (.claude/channels/telegram/.env)"
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
            log_err "Invalid format (expected NNNNN:AA…)"
            return 1
        fi
    fi

    # User ID — auto-detect from supercharged access.json
    local user_id=""
    local access_json="$HOME/.claude/channels/telegram/access.json"
    if [[ -f "$access_json" ]] && command -v jq >/dev/null 2>&1; then
        user_id=$(jq -r '.allowFrom[0] // empty' "$access_json" 2>/dev/null)
        [[ -n "$user_id" ]] && log_info "Found paired user_id $user_id from supercharged access.json"
    fi
    if [[ -z "$user_id" ]] && [[ -f "$env_file" ]]; then
        user_id=$(grep -E '^ALLOWED_USERS=' "$env_file" 2>/dev/null | tail -1 \
                  | sed 's/^ALLOWED_USERS=//' | cut -d, -f1)
        [[ -n "$user_id" ]] && log_info "Using existing ALLOWED_USERS=$user_id"
    fi
    if [[ -z "$user_id" ]]; then
        printf '  Your Telegram user ID (from @userinfobot): '
        read -r user_id
    fi
    if [[ ! "$user_id" =~ ^[0-9]+$ ]]; then
        log_err "Invalid user_id (expected numeric)"
        return 1
    fi

    [[ -f "$env_file" ]] && backup_file "$env_file"
    cat > "$env_file" <<ENV
TELEGRAM_BOT_TOKEN=$token
ALLOWED_USERS=$user_id
TMUX_SESSION_NAME=ccbot
CLAUDE_COMMAND=claude
ENV
    chmod 600 "$env_file"
    log_ok "Wrote $env_file"
}

# 4. Install ccbot SessionStart hook

_cc_install_ccbot_hook() {
    if ! command -v ccbot >/dev/null 2>&1; then
        log_err "ccbot not in PATH — install first"
        return 1
    fi
    printf '\n'
    log_info "Adds 'ccbot hook' as a SessionStart hook in ~/.claude/settings.json."
    log_info "Each new Claude Code session writes its tmux window↔session mapping"
    log_info "to $CC_CCBOT_CONFIG_DIR/session_map.json so ccbot can route TG topics to it."
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would run 'ccbot hook --install'"
        return
    fi
    if ! confirm "Install hook?"; then return; fi

    backup_file "$CLAUDE_DIR/settings.json"
    if ccbot hook --install 2>&1 | tail -5; then
        log_ok "Hook installed"
    else
        log_err "ccbot hook --install failed"
        return 1
    fi
}

# 5. Manual pairing help — interactive step-by-step checklist
# Each step opens the relevant URL when possible (BotFather chat) and waits
# for user confirmation before moving on. Lets the user pause and resume.

_cc_install_ccbot_pairing_help() {
    printf '\n'
    printf '  %bccbot pairing — interactive step-by-step%b\n\n' "$BOLD" "$RESET"
    printf '  ccbot routes by Forum topics, not DMs. We will walk through 5 manual\n'
    printf '  Telegram steps. Press %b[Enter]%b to advance, %b[s]%b to skip a step,\n' "$BOLD" "$RESET" "$BOLD" "$RESET"
    printf '  %b[q]%b to quit the checklist (you can re-run it later from this menu).\n\n' "$BOLD" "$RESET"
    if ! confirm "Start checklist?" "y"; then return; fi

    _cc_ccbot_step "1/5: Enable Threaded Mode in @BotFather" \
        "Open @BotFather → /mybots → select your bot → Bot Settings → Threaded Mode → Enable" \
        "tg://resolve?domain=BotFather" \
        "https://t.me/BotFather" || return

    _cc_ccbot_step "2/5: Create or pick a Telegram group with Topics" \
        "In Telegram, create a new group (long-press 'New' → 'New Group') OR open an existing one. In group Settings → enable 'Topics' (forum mode)." \
        "" "" || return

    _cc_ccbot_step "3/5: Add your bot to the group as admin" \
        "Group Settings → Administrators → Add Admin → search for your bot → grant message permissions" \
        "" "" || return

    _cc_ccbot_step "4/5: Verify ccbot is running" \
        "ccbot is managed by launchd. Status check below — should show 'state = running' with a pid." \
        "" "" || return
    if launchctl print "gui/$UID/$CC_CCBOT_LAUNCH_AGENT_LABEL" 2>&1 | grep -E "^\s*(state|pid)" | head -3; then
        :
    else
        log_warn "ccbot LaunchAgent not loaded — install via 'Install LaunchAgent' menu first"
    fi
    printf '  Press [Enter] when verified... '
    read -r _

    _cc_ccbot_step "5/5: Send first message in a topic" \
        "In your TG group, long-press 'New' → 'New Topic' → name it (e.g. 'macrift'). Send any message. Bot replies with a directory browser — choose your project dir. tmux window opens, claude starts there, your message goes in." \
        "" "" || return

    printf '\n'
    log_ok "All 5 steps acknowledged. Watch live with: tail -f /tmp/ccbot.log"
}

# Helper: print a step, optionally open URL(s), wait for input
_cc_ccbot_step() {
    local title="$1" body="$2" tg_url="$3" web_url="$4"
    printf '\n'
    printf '  %b%s%b\n' "$BOLD" "$title" "$RESET"
    printf '  %s\n' "$body"
    if [[ -n "$tg_url" ]]; then
        printf '  %b›%b opening %s\n' "$CYAN" "$RESET" "$tg_url"
        open "$tg_url" 2>/dev/null || open "$web_url" 2>/dev/null || true
    fi
    printf '  Press %b[Enter]%b to mark done · %b[s]%b skip · %b[q]%b quit: ' "$BOLD" "$RESET" "$DIM" "$RESET" "$DIM" "$RESET"
    local key
    read -r key
    case "$key" in
        q|Q) log_skip "checklist quit at: $title"; return 1 ;;
        s|S) log_skip "skipped: $title"; return 0 ;;
        *)   log_ok "done: $title"; return 0 ;;
    esac
}

# 6. LaunchAgent — VPN-aware wrapper, exec ccbot

_cc_install_ccbot_launchagent() {
    if ! command -v ccbot >/dev/null 2>&1; then
        log_err "ccbot binary not in PATH — install first"
        return 1
    fi
    if [[ ! -f "$CC_CCBOT_CONFIG_DIR/.env" ]]; then
        log_err ".env missing — configure it first"
        return 1
    fi
    printf '\n'
    log_info "Installs $CC_CCBOT_LAUNCH_AGENT"
    log_info "+ $CC_CCBOT_LAUNCHER wrapper that:"
    log_info "  - opens last-used VPN app (Happ or V2RayTun by mtime)"
    log_info "  - waits for VPN tunnel + api.anthropic.com NOT 403 (max 180s)"
    log_info "  - exec's ccbot"
    log_info "Logs: /tmp/ccbot.{log,err}"
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install LaunchAgent + wrapper"
        return
    fi
    if ! confirm "Install autostart?"; then return; fi
    _cc_install_ccbot_launchagent_copy
}

_cc_install_ccbot_launchagent_copy() {
    local ccbot_bin
    ccbot_bin=$(command -v ccbot)

    mkdir -p "$(dirname "$CC_CCBOT_LAUNCHER")"
    cat > "$CC_CCBOT_LAUNCHER" <<'LAUNCHER_EOF'
#!/bin/zsh
# ccbot launcher with VPN-aware wait gate. Same logic as supercharged-launcher:
# pick last-used VPN by mtime, wait until anthropic returns NOT 403, then exec.

set -u
export PATH="$HOME/.local/bin:$HOME/.bun/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

happ_mtime=$(stat -f %m "$HOME/Library/Application Support/Happ" 2>/dev/null || echo 0)
v2ray_mtime=$(stat -f %m "$HOME/Library/Application Support/V2RayTun" 2>/dev/null || echo 0)

if (( v2ray_mtime > happ_mtime )); then
  echo "[ccbot-launcher] opening V2RayTun (mtime=$v2ray_mtime > Happ=$happ_mtime)"
  open -a "V2RayTun" 2>/dev/null
else
  echo "[ccbot-launcher] opening Happ (mtime=$happ_mtime >= V2RayTun=$v2ray_mtime)"
  open -a "Happ" 2>/dev/null
fi

echo "[ccbot-launcher] waiting for VPN + anthropic routing (max 180s)..."
deadline=$(( $(date +%s) + 180 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  if scutil --nwi 2>/dev/null | grep -q "VPN server"; then
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 https://api.anthropic.com 2>/dev/null || echo 0)
    if [ "$code" != "0" ] && [ "$code" != "403" ]; then
      echo "[ccbot-launcher] VPN up + anthropic routed (HTTP $code)"
      break
    fi
  fi
  sleep 3
done

echo "[ccbot-launcher] exec'ing ccbot"
exec ccbot
LAUNCHER_EOF
    chmod +x "$CC_CCBOT_LAUNCHER"
    log_ok "Wrote $CC_CCBOT_LAUNCHER"

    cat > "$CC_CCBOT_LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$CC_CCBOT_LAUNCH_AGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$CC_CCBOT_LAUNCHER</string>
    </array>
    <key>KeepAlive</key><true/>
    <key>RunAtLoad</key><true/>
    <key>ThrottleInterval</key><integer>30</integer>
    <key>StandardOutPath</key><string>/tmp/ccbot.log</string>
    <key>StandardErrorPath</key><string>/tmp/ccbot.err</string>
</dict>
</plist>
PLIST

    if ! plutil -lint "$CC_CCBOT_LAUNCH_AGENT" >/dev/null 2>&1; then
        log_err "Generated plist is invalid"
        return 1
    fi

    launchctl bootout "gui/$UID/$CC_CCBOT_LAUNCH_AGENT_LABEL" 2>/dev/null || true
    if ! launchctl bootstrap "gui/$UID" "$CC_CCBOT_LAUNCH_AGENT" 2>/tmp/cc-ccbot-bootstrap.err; then
        log_err "launchctl bootstrap failed:"
        cat /tmp/cc-ccbot-bootstrap.err 2>/dev/null
        return 1
    fi
    launchctl kickstart -k "gui/$UID/$CC_CCBOT_LAUNCH_AGENT_LABEL" 2>/dev/null || true
    log_ok "ccbot LaunchAgent installed and started"
}

# 7. Full setup orchestrator

_cc_install_ccbot_full() {
    printf '\n'
    log_info "Full setup: deps check -> install -> env -> hook -> pairing-help -> launchagent"
    log_info "Pairing remains manual (TG forum group setup + BotFather Threaded Mode)."
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would run all steps"
        return
    fi
    if ! confirm "Run full setup?"; then return; fi

    _cc_install_ccbot_deps                    || return 1
    _cc_install_ccbot_install_copy            || return 1
    _cc_install_ccbot_env_copy                || return 1
    _cc_install_ccbot_hook                    || return 1
    _cc_install_ccbot_pairing_help

    if confirm "Install LaunchAgent now (recommended after pairing is verified)?" "n"; then
        _cc_install_ccbot_launchagent_copy    || return 1
    fi

    printf '\n'
    log_ok "ccbot setup complete"
    log_info "Logs: tail -f /tmp/ccbot.log"
}

# 8. Migrate from supercharged: stop its launchd, leave repo as fallback

_cc_migrate_supercharged_to_ccbot() {
    printf '\n'
    log_info "Stops the supercharged supervisor (com.claude-telegram-ts) and deletes"
    log_info "its plist + launcher. The supercharged repo + plugin install + token"
    log_info "are PRESERVED so you can revert by reinstalling the LaunchAgent."
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would stop supercharged"
        return
    fi
    if ! confirm "Stop supercharged?" "y"; then return; fi

    launchctl bootout "gui/$UID/com.claude-telegram-ts" 2>/dev/null && log_ok "supercharged launchd stopped" || log_skip "supercharged launchd not loaded"
    rm -fv "$HOME/Library/LaunchAgents/com.claude-telegram-ts.plist" \
           "$HOME/.local/bin/supercharged-launcher.sh" 2>/dev/null
    pkill -9 -f "telegram-supervisor.ts" 2>/dev/null || true
    pkill -9 -f "claude --channels" 2>/dev/null || true
    log_ok "supercharged stopped — repo + plugin + token preserved"
    log_info "To revert: macrift menu → Telegram → supercharged → Install LaunchAgent"
}

# 9. Remove ccbot launcher + autostart

_cc_remove_ccbot() {
    printf '\n'
    log_info "Removes LaunchAgent + launcher script."
    log_info "Preserves: ccbot binary (uv tool), $CC_CCBOT_CONFIG_DIR/, hook in settings.json."
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would remove LaunchAgent + launcher"
        return
    fi
    if ! confirm "Remove ccbot launcher + autostart?" "n"; then
        log_skip "Removal cancelled"
        return
    fi
    launchctl bootout "gui/$UID/$CC_CCBOT_LAUNCH_AGENT_LABEL" 2>/dev/null || true
    rm -f "$CC_CCBOT_LAUNCH_AGENT" "$CC_CCBOT_LAUNCHER"
    pkill -9 -f "/ccbot$\| ccbot$" 2>/dev/null || true
    log_ok "ccbot launcher and LaunchAgent removed"
}

# Telegram bot — k1p1l0/claude-telegram-supercharged (drop-in for the official
# anthropic plugin, with 15+ extra features: SQLite history, conversation
# memory, context watchdog, single-instance lock, forum topics, Telegraph
# instant view, supervisor daemon. supercharged inherits the official plugin's
# pairing flow and respects user settings.json — unlike standalone bots).

_cc_supercharged_menu() {
    crumb_push "Telegram"
    while true; do
        clear

        local choice
        choice=$(show_menu "Telegram bot (supercharged)" \
            "Full setup — plugin + apply + dirs + token + autostart" \
            "---" \
            "1. Install/restore official plugin (with upstream fallback)" \
            "2. Apply supercharged (drop server.ts + supervisor + skills)" \
            "3. Create runtime dirs (data/inbox)" \
            "4. Set bot token (writes ~/.claude/channels/telegram/.env)" \
            "5. Pairing help (manual step in fresh claude --channels session)" \
            "6. Install LaunchAgent (autostart + VPN-wait wrapper)" \
            "---" \
            "Re-apply after plugin auto-update overwrote server.ts" \
            "Migrate from old plugin / linuz90 (cleanup remnants)" \
            "Remove launcher + autostart (keep repo + token)" \
            "Back")

        case "$choice" in
            1)  _cc_install_supercharged_full; wait_enter ;;
            2)  _cc_install_supercharged_plugin; wait_enter ;;
            3)  _cc_install_supercharged_apply; wait_enter ;;
            4)  _cc_install_supercharged_dirs; wait_enter ;;
            5)  _cc_install_supercharged_token; wait_enter ;;
            6)  _cc_install_supercharged_pairing_help; wait_enter ;;
            7)  _cc_install_supercharged_launchagent; wait_enter ;;
            8)  _cc_install_supercharged_reapply; wait_enter ;;
            9)  _cc_uninstall_legacy_plugin; wait_enter ;;
            10) _cc_remove_supercharged; wait_enter ;;
            0)  break ;;
            *)  ;;
        esac
    done
    crumb_pop
}

# 1. Install official plugin (supercharged is a drop-in on top of it)

_cc_install_supercharged_plugin() {
    if ! command -v claude >/dev/null 2>&1; then
        log_err "claude CLI not found"
        return 1
    fi
    printf '\n'
    log_info "Adds telegram@claude-plugins-official to enabledPlugins,"
    log_info "fetches plugin source from upstream if marketplace dir is empty,"
    log_info "and runs claude plugin install to populate cache."
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install plugin"
        return
    fi
    if ! confirm "Install / restore the official telegram plugin?"; then return; fi
    _cc_install_supercharged_plugin_copy
}

_cc_install_supercharged_plugin_copy() {
    local marketplace_tg="$HOME/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/telegram"
    local plugin_base="$HOME/.claude/plugins/cache/claude-plugins-official/telegram"
    local installed="$HOME/.claude/plugins/installed_plugins.json"

    # If marketplace's external_plugins/telegram is empty (we hit this in real
    # debugging — the dir gets removed during cleanup runs and `marketplace
    # update` doesn't restore the source files, only metadata), sparse-clone
    # the directory directly from upstream.
    if [[ ! -d "$marketplace_tg" ]] || [[ -z "$(ls -A "$marketplace_tg" 2>/dev/null)" ]]; then
        log_info "Marketplace telegram source missing — sparse-cloning from upstream"
        local tmp="/tmp/claude-plugins-official-fetch-$$"
        rm -rf "$tmp"
        if ! git clone --depth 1 --filter=blob:none --sparse \
                https://github.com/anthropics/claude-plugins-official.git "$tmp" 2>&1 | tail -3; then
            log_err "git clone failed"
            return 1
        fi
        git -C "$tmp" sparse-checkout set external_plugins/telegram >/dev/null 2>&1
        mkdir -p "$(dirname "$marketplace_tg")"
        cp -R "$tmp/external_plugins/telegram" "$marketplace_tg"
        rm -rf "$tmp"
        log_ok "Restored marketplace source"
    fi

    # Force-clean half-state (entry in installed_plugins.json but no cache),
    # which can happen if a previous install was interrupted.
    if [[ -f "$installed" ]] && command -v jq >/dev/null 2>&1; then
        if jq -e '.plugins["telegram@claude-plugins-official"]' "$installed" >/dev/null 2>&1 \
            && [[ ! -d "$plugin_base" ]]; then
            log_info "Removing stale installed_plugins entry (no cache present)"
            local tmp_json
            tmp_json=$(mktemp)
            jq 'del(.plugins["telegram@claude-plugins-official"])' "$installed" > "$tmp_json"
            mv "$tmp_json" "$installed"
        fi
    fi

    if claude plugin install telegram@claude-plugins-official </dev/null >/dev/null 2>&1; then
        log_ok "claude plugin install reported success"
    else
        log_warn "claude plugin install returned error — verifying cache anyway"
    fi

    if [[ ! -d "$plugin_base" ]] || [[ -z "$(ls -A "$plugin_base" 2>/dev/null)" ]]; then
        log_err "Plugin cache still empty at $plugin_base"
        log_info "Try interactively: open a new terminal, run 'claude', then '/plugin install telegram@claude-plugins-official'"
        return 1
    fi

    # Enable in settings.json + add tools to allow
    local settings="$CLAUDE_DIR/settings.json"
    if [[ -f "$settings" ]] && command -v jq >/dev/null 2>&1; then
        backup_file "$settings"
        local tools='["mcp__plugin_telegram_telegram__reply","mcp__plugin_telegram_telegram__react","mcp__plugin_telegram_telegram__edit_message","mcp__plugin_telegram_telegram__ask_user","mcp__plugin_telegram_telegram__get_history","mcp__plugin_telegram_telegram__search_messages","mcp__plugin_telegram_telegram__clear_history","mcp__plugin_telegram_telegram__save_memory","mcp__plugin_telegram_telegram__create_telegraph_page"]'
        local tmp_json
        tmp_json=$(mktemp)
        jq --argjson tools "$tools" '
          .enabledPlugins["telegram@claude-plugins-official"] = true |
          .permissions.allow = ((.permissions.allow // []) + $tools | unique)
        ' "$settings" > "$tmp_json"
        mv "$tmp_json" "$settings"
        log_ok "Plugin enabled + 9 supercharged tools merged into permissions.allow"
    fi

    local plugin_version
    plugin_version=$(ls "$plugin_base" | sort -V | tail -1)
    log_ok "Plugin installed at $plugin_base/$plugin_version"
}

# 2. Apply supercharged (drop server.ts + supervisor + skills)

_cc_install_supercharged_apply() {
    local plugin_base="$HOME/.claude/plugins/cache/claude-plugins-official/telegram"
    if [[ ! -d "$plugin_base" ]] || [[ -z "$(ls -A "$plugin_base" 2>/dev/null)" ]]; then
        log_err "Plugin cache missing — run 'Install/restore official plugin' first"
        return 1
    fi
    if ! command -v git >/dev/null 2>&1 || ! command -v bun >/dev/null 2>&1; then
        log_err "git and bun required"
        return 1
    fi
    printf '\n'
    log_info "Clones k1p1l0/claude-telegram-supercharged + drops:"
    log_info "  - server.ts on top of the official plugin"
    log_info "  - supervisor.ts to ~/.claude/scripts/telegram-supervisor.ts"
    log_info "  - skills/ to plugin dir (additive)"
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would apply supercharged"
        return
    fi
    if ! confirm "Apply supercharged?"; then return; fi
    _cc_install_supercharged_apply_copy
}

_cc_install_supercharged_apply_copy() {
    local repo="$HOME/Documents/Code/Claude/claude-telegram-supercharged"
    local plugin_base="$HOME/.claude/plugins/cache/claude-plugins-official/telegram"
    local plugin_version
    plugin_version=$(ls "$plugin_base" | sort -V | tail -1)
    local plugin_dir="$plugin_base/$plugin_version"
    local scripts_dir="$HOME/.claude/scripts"

    if [[ -d "$repo" ]]; then
        log_info "Pulling latest in $repo"
        git -C "$repo" pull --ff-only 2>&1 | tail -3
    else
        mkdir -p "$(dirname "$repo")"
        git clone https://github.com/k1p1l0/claude-telegram-supercharged "$repo" 2>&1 | tail -3
    fi

    # Save official server.ts as backup (only if not already saved)
    if [[ ! -f "$plugin_dir/server.ts.official.bak" ]]; then
        cp "$plugin_dir/server.ts" "$plugin_dir/server.ts.official.bak"
    fi
    cp "$repo/server.ts" "$plugin_dir/server.ts"
    log_ok "server.ts replaced (official saved as server.ts.official.bak)"

    mkdir -p "$scripts_dir"
    [[ -f "$repo/supervisor.ts" ]] && cp "$repo/supervisor.ts" "$scripts_dir/telegram-supervisor.ts" \
        && log_ok "supervisor.ts -> $scripts_dir"
    [[ -f "$repo/scripts/claude-daemon-wrapper.exp" ]] \
        && cp "$repo/scripts/claude-daemon-wrapper.exp" "$scripts_dir/" \
        && log_ok "claude-daemon-wrapper.exp -> $scripts_dir"

    if [[ -d "$repo/skills" ]]; then
        mkdir -p "$plugin_dir/skills"
        cp -R "$repo/skills/." "$plugin_dir/skills/"
        log_ok "skills/ copied (additive)"
    fi

    # Run bun install in plugin dir to ensure deps current (supercharged may
    # add deps over time; safe even if package.json unchanged).
    log_info "Running bun install in plugin dir..."
    ( cd "$plugin_dir" && bun install --no-summary 2>&1 | tail -3 )
}

# 3. Create runtime dirs (supercharged crashes without these — we hit ENOENT
#    on data/telegram.lock during real debugging)

_cc_install_supercharged_dirs() {
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would create ~/.claude/channels/telegram/{data,inbox}"
        return
    fi
    _cc_install_supercharged_dirs_copy
}

_cc_install_supercharged_dirs_copy() {
    local data_dir="$HOME/.claude/channels/telegram/data"
    local inbox_dir="$HOME/.claude/channels/telegram/inbox"
    mkdir -p "$data_dir" "$inbox_dir"
    log_ok "Created $data_dir and $inbox_dir"
}

# 4. Bot token

_cc_install_supercharged_token() {
    printf '\n'
    log_info "Stores bot token in ~/.claude/channels/telegram/.env (chmod 600)."
    log_info "If you already had it from a previous setup, this preserves it."
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would prompt for bot token"
        return
    fi
    _cc_install_supercharged_token_copy
}

_cc_install_supercharged_token_copy() {
    local env_file="$HOME/.claude/channels/telegram/.env"

    local existing=""
    if [[ -f "$env_file" ]]; then
        existing=$(grep -E '^TELEGRAM_BOT_TOKEN=' "$env_file" 2>/dev/null | tail -1 \
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
        log_err "Invalid format (expected NNNNN:AA…)"
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

    mkdir -p "$(dirname "$env_file")"
    [[ -f "$env_file" ]] && backup_file "$env_file"
    printf 'TELEGRAM_BOT_TOKEN=%s\n' "$token" > "$env_file"
    chmod 600 "$env_file"
    log_ok "Token saved to $env_file"
}

# 5. Pairing instructions (manual; pairing requires interactive claude session)

_cc_install_supercharged_pairing_help() {
    printf '\n'
    printf '  %bSupercharged pairing — manual step%b\n\n' "$BOLD" "$RESET"
    printf '  Pairing requires an interactive `claude --channels` session, which\n'
    printf '  cannot be done from inside this tool. Open a NEW terminal window and:\n\n'
    printf '  %b1.%b  claude --channels plugin:telegram@claude-plugins-official\n' "$CYAN" "$RESET"
    printf '      (wait for "Listening for channel messages from: ..." line)\n\n'
    printf '  %b2.%b  In Telegram, DM your bot. Bot replies with a 6-character code.\n' "$CYAN" "$RESET"
    printf '      For groups: add bot, @-mention it, get the same pairing code.\n\n'
    printf '  %b3.%b  In the Claude window, type:\n' "$CYAN" "$RESET"
    printf '         /telegram:access pair <CODE>\n'
    printf '         /telegram:access policy allowlist\n\n'
    printf '  %b4.%b  Close that Claude window — pairing is saved in access.json.\n\n' "$CYAN" "$RESET"
    printf '  Then come back and run "Install LaunchAgent" so the bot stays alive\n'
    printf '  across reboots.\n\n'
}

# 6. LaunchAgent (supervisor + VPN-wait wrapper)

_cc_install_supercharged_launchagent() {
    if [[ ! -f "$HOME/.claude/scripts/telegram-supervisor.ts" ]]; then
        log_err "supervisor.ts missing — run 'Apply supercharged' first"
        return 1
    fi
    printf '\n'
    log_info "Installs ~/Library/LaunchAgents/com.claude-telegram-ts.plist"
    log_info "+ ~/.local/bin/supercharged-launcher.sh wrapper that:"
    log_info "  - opens last-used VPN app (Happ or V2RayTun by mtime)"
    log_info "  - waits for api.anthropic.com reachability (max 60s)"
    log_info "  - exec's bun ~/.claude/scripts/telegram-supervisor.ts"
    log_info "Logs: /tmp/claude-telegram-bot-ts.{log,err}"
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install LaunchAgent + wrapper"
        return
    fi
    if ! confirm "Install autostart?"; then return; fi
    _cc_install_supercharged_launchagent_copy
}

_cc_install_supercharged_launchagent_copy() {
    local launcher="$HOME/.local/bin/supercharged-launcher.sh"
    local plist="$HOME/Library/LaunchAgents/com.claude-telegram-ts.plist"
    local label="com.claude-telegram-ts"
    local bun_bin
    bun_bin=$(command -v bun || echo "$HOME/.bun/bin/bun")

    mkdir -p "$(dirname "$launcher")"
    cat > "$launcher" <<LAUNCHER
#!/bin/zsh
# Supercharged supervisor launcher with VPN-wait gate.
# Picks whichever VPN app (Happ / V2RayTun) was used most recently, opens it
# (assuming "Connect on launch" is configured in the app's own settings),
# then waits for api.anthropic.com to be reachable before exec'ing supervisor.

set -u
export PATH="\$HOME/.bun/bin:\$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\$PATH"

happ_mtime=\$(stat -f %m "\$HOME/Library/Application Support/Happ" 2>/dev/null || echo 0)
v2ray_mtime=\$(stat -f %m "\$HOME/Library/Application Support/V2RayTun" 2>/dev/null || echo 0)
if (( v2ray_mtime > happ_mtime )); then
  open -a "V2RayTun" 2>/dev/null
else
  open -a "Happ" 2>/dev/null
fi

for i in \$(seq 1 30); do
  curl -s --max-time 5 -o /dev/null https://api.anthropic.com && break
  sleep 2
done

exec "$bun_bin" "\$HOME/.claude/scripts/telegram-supervisor.ts"
LAUNCHER
    chmod +x "$launcher"
    log_ok "Wrote $launcher"

    cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>$launcher</string>
    </array>
    <key>KeepAlive</key><true/>
    <key>RunAtLoad</key><true/>
    <key>ThrottleInterval</key><integer>30</integer>
    <key>StandardOutPath</key><string>/tmp/claude-telegram-bot-ts.log</string>
    <key>StandardErrorPath</key><string>/tmp/claude-telegram-bot-ts.err</string>
</dict>
</plist>
PLIST

    if ! plutil -lint "$plist" >/dev/null 2>&1; then
        log_err "Generated plist is invalid"
        return 1
    fi

    launchctl bootout "gui/$UID/$label" 2>/dev/null || true
    if ! launchctl bootstrap "gui/$UID" "$plist" 2>/tmp/cc-supercharged-bootstrap.err; then
        log_err "launchctl bootstrap failed:"
        cat /tmp/cc-supercharged-bootstrap.err 2>/dev/null
        return 1
    fi
    launchctl kickstart -k "gui/$UID/$label" 2>/dev/null || true
    log_ok "LaunchAgent installed and started"

    _cc_ensure_local_bin_on_path 2>/dev/null || true
}

# 7. Full setup orchestrator

_cc_install_supercharged_full() {
    printf '\n'
    log_info "Full setup: plugin -> apply -> dirs -> token -> pairing-help -> launchagent"
    log_info "Pairing remains a manual step (requires interactive claude session)."
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would run all steps"
        return
    fi
    if ! confirm "Run full setup?"; then return; fi

    # If old plugin/linuz90 artifacts exist, offer cleanup first
    if [[ -e "$CC_TG_LEGACY_LAUNCH_AGENT" || -e "$CC_TG_LEGACY_OLD_PLIST" ]]; then
        printf '\n'
        log_warn "Old plugin/linuz90 artifacts detected — would conflict with supercharged."
        if confirm "Clean them up first?" "y"; then
            _cc_uninstall_legacy_plugin_copy
        fi
    fi

    _cc_install_supercharged_plugin_copy   || return 1
    _cc_install_supercharged_apply_copy    || return 1
    _cc_install_supercharged_dirs_copy     || return 1
    _cc_install_supercharged_token_copy    || return 1
    _cc_install_supercharged_pairing_help

    if confirm "Install LaunchAgent now (recommended after pairing is done)?" "n"; then
        _cc_install_supercharged_launchagent_copy || return 1
    fi

    printf '\n'
    log_ok "Supercharged setup complete"
    log_info "Logs: tail -f /tmp/claude-telegram-bot-ts.log"
}

# 8. Re-apply after plugin auto-update overwrote server.ts (known supercharged
#    pain — the official plugin auto-updates and clobbers our drop)

_cc_install_supercharged_reapply() {
    printf '\n'
    log_info "When the official plugin auto-updates, it overwrites server.ts with"
    log_info "the official version. This re-applies the supercharged drop."
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would re-apply supercharged"
        return
    fi
    if ! confirm "Re-apply now?"; then return; fi

    _cc_install_supercharged_apply_copy || return 1

    # Restart launchd if it was active
    local label="com.claude-telegram-ts"
    if launchctl list 2>/dev/null | grep -q "$label"; then
        launchctl kickstart -k "gui/$UID/$label" 2>/dev/null
        log_ok "Restarted LaunchAgent"
    fi
}

# 9. Remove launcher + LaunchAgent (preserves repo + token + plugin)

_cc_remove_supercharged() {
    local launcher="$HOME/.local/bin/supercharged-launcher.sh"
    local plist="$HOME/Library/LaunchAgents/com.claude-telegram-ts.plist"
    local label="com.claude-telegram-ts"

    printf '\n'
    log_info "Removes LaunchAgent + launcher script."
    log_info "Preserves: repo (~/Documents/Code/Claude/claude-telegram-supercharged),"
    log_info "  ~/.claude/channels/telegram/.env (token), plugin install, supervisor.ts."
    printf '\n'
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would remove LaunchAgent + launcher"
        return
    fi
    if ! confirm "Remove launcher + autostart?" "n"; then
        log_skip "Removal cancelled"
        return
    fi
    launchctl bootout "gui/$UID/$label" 2>/dev/null || true
    rm -f "$plist" "$launcher"
    log_ok "Launcher and LaunchAgent removed"
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

    # Telegram engines (supercharged + ccbot) — opt-in (separate confirms so
    # tokens + repos + uv-tool installs aren't nuked by accident)
    local has_super=false has_ccbot=false has_legacy=false
    [[ -e "$HOME/Library/LaunchAgents/com.claude-telegram-ts.plist" \
        || -e "$HOME/.local/bin/supercharged-launcher.sh" \
        || -d "$HOME/Documents/Code/Claude/claude-telegram-supercharged" \
        || -f "$HOME/.claude/scripts/telegram-supervisor.ts" ]] && has_super=true
    [[ -e "$CC_CCBOT_LAUNCH_AGENT" || -e "$CC_CCBOT_LAUNCHER" \
        || -d "$CC_CCBOT_CONFIG_DIR" ]] && has_ccbot=true
    [[ -e "$CC_TG_LEGACY_LAUNCH_AGENT" || -e "$CC_TG_LEGACY_OLD_PLIST" \
        || -e "$CC_TG_LEGACY_LAUNCHER" || -e "$CC_TG_LEGACY_OLD_LAUNCHER" \
        || -e "$CC_TG_LEGACY_ENV_FILE" ]] && has_legacy=true

    if $has_super; then
        printf '\n'
        log_info "Telegram supercharged artifacts:"
        [[ -e "$HOME/Library/LaunchAgents/com.claude-telegram-ts.plist" ]] && printf '    %s\n' "$HOME/Library/LaunchAgents/com.claude-telegram-ts.plist"
        [[ -e "$HOME/.local/bin/supercharged-launcher.sh" ]]               && printf '    %s\n' "$HOME/.local/bin/supercharged-launcher.sh"
        [[ -d "$HOME/Documents/Code/Claude/claude-telegram-supercharged" ]] && printf '    %s/ (repo)\n' "$HOME/Documents/Code/Claude/claude-telegram-supercharged"
        [[ -f "$HOME/.claude/scripts/telegram-supervisor.ts" ]]            && printf '    %s\n' "$HOME/.claude/scripts/telegram-supervisor.ts"
        printf '\n'
        if confirm "Also wipe Telegram supercharged?" "n"; then
            launchctl bootout "gui/$UID/com.claude-telegram-ts" 2>/dev/null || true
            rm -f "$HOME/Library/LaunchAgents/com.claude-telegram-ts.plist" \
                  "$HOME/.local/bin/supercharged-launcher.sh" \
                  "$HOME/.claude/scripts/telegram-supervisor.ts" \
                  "$HOME/.claude/scripts/claude-daemon-wrapper.exp"
            if confirm "Also delete repo + token (~/.claude/channels/telegram/.env)?" "n"; then
                rm -rf "$HOME/Documents/Code/Claude/claude-telegram-supercharged"
                rm -f "$HOME/.claude/channels/telegram/.env"
            fi
            log_ok "Supercharged wiped"
        fi
    fi

    if $has_ccbot; then
        printf '\n'
        log_info "Telegram ccbot artifacts:"
        [[ -e "$CC_CCBOT_LAUNCH_AGENT" ]] && printf '    %s\n' "$CC_CCBOT_LAUNCH_AGENT"
        [[ -e "$CC_CCBOT_LAUNCHER" ]]     && printf '    %s\n' "$CC_CCBOT_LAUNCHER"
        [[ -d "$CC_CCBOT_CONFIG_DIR" ]]   && printf '    %s/ (config + state)\n' "$CC_CCBOT_CONFIG_DIR"
        printf '\n'
        if confirm "Also wipe Telegram ccbot?" "n"; then
            launchctl bootout "gui/$UID/$CC_CCBOT_LAUNCH_AGENT_LABEL" 2>/dev/null || true
            pkill -9 -f "/ccbot$\| ccbot$" 2>/dev/null || true
            rm -f "$CC_CCBOT_LAUNCH_AGENT" "$CC_CCBOT_LAUNCHER"
            if confirm "Also delete config dir $CC_CCBOT_CONFIG_DIR (loses .env token + session_map)?" "n"; then
                rm -rf "$CC_CCBOT_CONFIG_DIR"
            fi
            if command -v uv >/dev/null 2>&1 && uv tool list 2>/dev/null | grep -q '^ccbot'; then
                if confirm "Also uninstall ccbot via 'uv tool uninstall ccbot'?" "n"; then
                    uv tool uninstall ccbot 2>&1 | tail -3
                fi
            fi
            log_ok "ccbot wiped"
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
