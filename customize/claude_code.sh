#!/usr/bin/env bash
# macrift — Claude Code setup

CLAUDE_DIR="$HOME/.claude"
CC_CONFIG="$MACRIFT_DIR/config/claude-code"
CC_ENV_MARKER="# macrift:claude-code env"
CC_RALIAS_MARKER="# macrift:claude-code r-alias"
# Marks the ~/.local/bin PATH block (added by _cc_ensure_local_bin_on_path,
# stripped by reset). Kept here — used outside the Telegram engine file too.
CC_TG_PATH_MARKER="# macrift:claude-code local-bin-path"

claude_code_menu() {
  crumb_push "Claude Code"
  while true; do
    clear

    local choice
    choice=$(show_menu "Claude Code" \
      "Setup ›" \
      "---" \
      "Telegram bot ›" \
      "---" \
      "Reset" \
      "Back")

    case "$choice" in
      1) _cc_custom_menu ;;
      2) source "$MACRIFT_DIR/customize/claude_code_telegram.sh" && _cc_telegram_menu ;;
      3)
        _cc_reset
        wait_enter
        ;;
      0) break ;;
      *) ;;
    esac
  done
  crumb_pop
}

# Component registry — single source of truth for the Setup menu AND the wizard.
# One row per component, in display order. Both consumers derive from this, so
# adding a component is one row here (+ one arm in the wizard dispatch case for
# its batch behavior) instead of editing the menu list, five parallel wizard
# arrays, and two case blocks by hand.
#
# Fields (| delimited, 11 total — never put a literal | inside a field):
#   key | section | menu | wiz | mwait | wdefault | menu_label | wizard_label | menu_handler | desc | usecase
#     menu/wiz : y/n — appears in the Setup menu / the wizard
#     mwait    : y/n — menu dispatch appends wait_enter after the handler
#     wdefault : y/n — wizard panel default answer
#     menu_handler : interactive installer the menu calls (menu rows only)
#     desc/usecase : wizard panel copy (wizard rows only)
_cc_registry() {
  cat <<'REG'
settings|Core|y|y|y|y|Settings|Settings|_cc_install_settings_user|permission allow/deny + plugin enable + hooks wiring|safe defaults, no per-command prompts
statusline|Core|y|y|y|y|Statusline|Statusline|_cc_install_statusline|cwd · branch · model · ctx% · rate% with color escalation|see context burn before /compact bites
doctor|Core|n|y|n|y||Doctor + /doctor command||/doctor command + ~/.claude/doctor.sh — verifies hooks, deps, MCP, CLAUDE.md imports|first-run health check / 'why is X broken'
agents|AI extensions|y|y|n|y|Agents|Agents (4 subagents)|_cc_install_agents|debugger, explorer, reviewer, simplifier — each in fresh context|delegate to specialist without polluting main thread
commands|AI extensions|y|y|n|y|Slash Commands|Slash commands (9)|_cc_install_commands|/canpush /debug /doctor /explore /mcp-context7 /refine /reflect /review /simplify|explicit one-line triggers
rules|AI extensions|y|y|n|y|Rules|Rules (5 behavior files)|_cc_install_rules|code-style, communication, git, security, workflow — @-imported via CLAUDE.md|enforced behavior every session
hooks|AI extensions|y|y|y|y|Hooks|Hooks (format + security-gate + session-start)|_cc_install_hooks|format-on-edit, security gate (blocks force-push), SessionStart git context inject|auto-format, block force-push, save tokens on session start
env|Shell integration|y|y|y|y|Environment (.zshrc env vars)|Env vars (.zshrc)|_cc_install_env|SUBAGENT_MODEL=sonnet-4-6 + CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=99|cheap subagents + manual /compact discipline (Dex's <30% rule)
claude_md|Shell integration|y|y|y|y|CLAUDE.md (rule imports)|CLAUDE.md sync|_cc_install_claude_md|auto-add @~/.claude/rules/<name>.md imports; remove stale ones|leave checked unless skipping rules
ralias|Shell integration|y|y|y|y|'r' alias|'r' alias|_cc_install_r_alias|alias r='bash /tmp/cmd.sh' in ~/.zshrc|workflow.md 'claude writes script, you type r' pattern
mcp|MCP servers|y|n|n|n|MCP Servers (context7, playwright)||_cc_install_mcp||
mcp_context7|MCP servers|n|y|n|y||MCP context7||live library docs lookup (kills hallucinated APIs)|any project pulling third-party libs
mcp_playwright|MCP servers|n|y|n|y||MCP playwright||browser automation / E2E test generation|web testing only
REG
}

# Wizard label for a component key (used by the wizard summary screen).
_cc_wizard_label() {
  local want="$1" key section menu wiz mwait wdefault mlabel wlabel rest
  while IFS='|' read -r key section menu wiz mwait wdefault mlabel wlabel rest; do
    [[ "$key" == "$want" ]] && {
      printf '%s' "$wlabel"
      return
    }
  done < <(_cc_registry)
}

_cc_custom_menu() {
  crumb_push "Setup"
  while true; do
    clear

    # Build the menu (and a parallel dispatch table) from the registry.
    # Item 1 is always the wizard; components follow, grouped by section header.
    local menu_items=("Setup wizard" "---")
    local keys=("__wizard__") handlers=("") waits=("")
    local prev_sec=""
    local key section menu wiz mwait wdefault mlabel wlabel handler desc usecase
    while IFS='|' read -r key section menu wiz mwait wdefault mlabel wlabel handler desc usecase; do
      [[ "$menu" == y ]] || continue
      if [[ "$section" != "$prev_sec" ]]; then
        menu_items+=("## $section")
        prev_sec="$section"
      fi
      menu_items+=("$mlabel")
      keys+=("$key")
      handlers+=("$handler")
      waits+=("$mwait")
    done < <(_cc_registry)
    menu_items+=("Back")

    local choice
    choice=$(show_menu "Setup" "${menu_items[@]}")
    [[ "$choice" == 0 ]] && break

    local sel_key="${keys[$((choice - 1))]}"
    if [[ "$sel_key" == "__wizard__" ]]; then
      _cc_full_setup
      continue
    fi
    "${handlers[$((choice - 1))]}"
    [[ "${waits[$((choice - 1))]}" == y ]] && wait_enter
  done
  crumb_pop
}

# Full Setup

# Wizard internal state — set by 'a' (accept-all-remaining) keypress.
_cc_wizard_accept_all=false

# Render one wizard panel and read decision. Returns:
#   0 = yes (install)
#   1 = no  (skip)
#   2 = quit wizard
_cc_wizard_ask() {
  local section=$1 name=$2 desc=$3 use_case=$4 default=$5 idx=$6 total=$7

  if $_cc_wizard_accept_all; then
    [[ "$default" == "y" ]] && return 0 || return 1
  fi

  # Box helpers (_box_top etc) use dynamically-scoped BP/R — define them here.
  local BP="${BOLD}${GRAY}" R="${RESET}"

  # Box width — fit longest line + 4 padding, min 64
  local uc_str="use case: $use_case"
  local max_len=${#name}
  [[ ${#desc} -gt $max_len ]] && max_len=${#desc}
  [[ ${#uc_str} -gt $max_len ]] && max_len=${#uc_str}
  local inner_w=$((max_len + 4))
  [[ $inner_w -lt 64 ]] && inner_w=64

  local title="Setup wizard · $section · $idx/$total"

  while true; do
    clear

    _box_top "$title" "$inner_w"
    _box_empty "$inner_w"

    # Name (bold)
    local name_content
    name_content=$(printf '%b%s%b' "$BOLD" "$name" "$RESET")
    _box_row "$inner_w" "$name_content" $((inner_w - 2 - ${#name}))
    _box_empty "$inner_w"

    # Description
    _box_row "$inner_w" "$desc" $((inner_w - 2 - ${#desc}))
    _box_empty "$inner_w"

    # Use case (dim)
    local uc_content
    uc_content=$(printf '%buse case:%b %s' "$DIM" "$RESET" "$use_case")
    _box_row "$inner_w" "$uc_content" $((inner_w - 2 - ${#uc_str}))
    _box_empty "$inner_w"

    _box_bottom "$inner_w"

    # Footer — minimal. Enter accepts (default for all panels is yes).
    # 'a' (accept-rest) and 'q' (quit) remain functional but hidden.
    printf '  %by/n%b\n' "$DIM" "$RESET" >&2

    local key
    key=$(_read_key)

    case "$key" in
      y | Y) return 0 ;;
      n | N) return 1 ;;
      a | A)
        _cc_wizard_accept_all=true
        [[ "$default" == "y" ]] && return 0 || return 1
        ;;
      q | Q) return 2 ;;
      enter) [[ "$default" == "y" ]] && return 0 || return 1 ;;
      *) ;; # unknown — re-prompt
    esac
  done
}

_cc_full_setup() {
  if [[ "$MACRIFT_DRY_RUN" == true ]]; then
    log_info "Dry run — would launch setup wizard"
    wait_enter
    return
  fi

  _cc_wizard_accept_all=false

  # Build wizard panels from the component registry (wiz=y rows). Keeping the
  # five values per row together — instead of five index-aligned arrays — is
  # what removes the alignment footgun.
  local r_keys=() r_sections=() r_names=() r_descs=() r_usecases=() r_defaults=()
  local key section menu wiz mwait wdefault mlabel wlabel handler desc usecase
  while IFS='|' read -r key section menu wiz mwait wdefault mlabel wlabel handler desc usecase; do
    [[ "$wiz" == y ]] || continue
    r_keys+=("$key")
    r_sections+=("$section")
    r_names+=("$wlabel")
    r_descs+=("$desc")
    r_usecases+=("$usecase")
    r_defaults+=("$wdefault")
  done < <(_cc_registry)

  local total=${#r_keys[@]}
  local sel=() # collects component keys
  local i=0
  while ((i < total)); do
    _cc_wizard_ask \
      "${r_sections[$i]}" "${r_names[$i]}" "${r_descs[$i]}" \
      "${r_usecases[$i]}" "${r_defaults[$i]}" "$((i + 1))" "$total"
    local rc=$?
    case $rc in
      0) sel+=("${r_keys[$i]}") ;;
      1) ;; # skip
      2)
        log_info "Wizard cancelled"
        return
        ;;
    esac
    i=$((i + 1))
  done

  # Summary + confirm
  clear
  printf '\n  %bAbout to install:%b\n\n' "$BOLD" "$RESET"
  if [[ ${#sel[@]} -eq 0 ]]; then
    log_warn "Nothing selected — exiting"
    wait_enter
    return
  fi
  for s in "${sel[@]}"; do
    printf '    %b•%b %s\n' "$GREEN" "$RESET" "$(_cc_wizard_label "$s")"
  done
  printf '\n'
  if ! confirm "Proceed?" "y"; then
    log_info "Cancelled"
    return
  fi

  # Track for coherence warnings
  local sel_settings=false sel_hooks=false sel_rules=false sel_claude_md=false

  _cc_require_jq
  _cc_ensure_dir

  # Dependency preflight — capability flags so MCP/statusline steps skip with a
  # clear reason instead of failing silently mid-batch on a clean system.
  local have_claude=true have_npx=true have_statusline_rt=true
  command -v claude >/dev/null 2>&1 || have_claude=false
  command -v npx >/dev/null 2>&1 || have_npx=false
  { command -v bun >/dev/null 2>&1 || command -v npx >/dev/null 2>&1; } || have_statusline_rt=false
  $have_claude || log_info "'claude' CLI not detected — get it at https://claude.com/code (file steps below still apply)"

  # Dispatch by component key (matches the registry). Behavior — coherence
  # flags, preflight skips — stays here; only the data lives in the registry.
  for key in "${sel[@]}"; do
    case "$key" in
      settings)
        sel_settings=true
        _cc_install_settings_user --full
        ;;
      statusline)
        if $have_statusline_rt; then
          _cc_install_statusline_copy
        else
          log_warn "Statusline skipped — neither bun nor npx in PATH"
          log_info "  → settings.json still wires it; install bun or node to render"
        fi
        ;;
      doctor) _cc_install_doctor_copy ;;
      agents) _cc_install_dir "agents" ;;
      commands) _cc_install_dir "commands" ;;
      rules)
        sel_rules=true
        _cc_install_dir "rules"
        ;;
      hooks)
        sel_hooks=true
        _cc_install_hooks_copy
        ;;
      env) _cc_install_env_copy ;;
      claude_md)
        sel_claude_md=true
        _cc_install_claude_md_copy
        ;;
      ralias) _cc_install_r_alias_copy ;;
      mcp_context7)
        if ! $have_claude; then
          log_warn "context7 MCP skipped — 'claude' CLI not found"
        elif _cc_mcp_install_one context7; then
          log_ok "context7 MCP installed"
        else
          log_err "context7 MCP install failed"
        fi
        ;;
      mcp_playwright)
        if ! $have_claude; then
          log_warn "playwright MCP skipped — 'claude' CLI not found"
        elif ! $have_npx; then
          log_warn "playwright MCP skipped — needs 'npx' (Node.js)"
        elif _cc_mcp_install_one playwright; then
          log_ok "playwright MCP installed"
        else
          log_err "playwright MCP install failed"
        fi
        ;;
    esac
  done

  # Optional formatters — separate step (these are brew installs, not macrift configs)
  printf '\n'
  log_info "Optional formatters for hooks/format.sh — un-installed ones are silently skipped by the hook:"
  local tool desc
  for tool in prettier ruff shfmt; do
    if command -v "$tool" >/dev/null 2>&1; then
      log_skip "$tool already installed"
      continue
    fi
    case "$tool" in
      prettier) desc=".ts/.js/.json/.yaml/.css/.html" ;;
      ruff) desc=".py" ;;
      shfmt) desc=".sh/.bash (recommended for shell-heavy repos)" ;;
    esac
    if confirm "Install $tool? ($desc)" "n"; then
      _cc_brew_install_optional "$tool"
    fi
  done
  # gofmt (.go) and rustfmt (.rs) are also wired in format.sh — they ship with
  # the Go / Rust toolchains, so there's no standalone formula to brew-install.
  command -v gofmt >/dev/null 2>&1 || log_skip "gofmt absent (.go) — comes with 'brew install go'"
  command -v rustfmt >/dev/null 2>&1 || log_skip "rustfmt absent (.rs) — comes with the Rust toolchain (rustup)"

  # Coherence warnings
  printf '\n'
  if $sel_hooks && ! $sel_settings; then
    log_warn "Hooks installed but Settings skipped — settings.json won't wire them"
    log_info "  → re-run wizard and accept Settings, or hooks won't fire"
  fi
  if $sel_rules && ! $sel_claude_md; then
    log_warn "Rules installed but CLAUDE.md sync skipped — rules won't load into sessions"
    log_info "  → re-run wizard and accept CLAUDE.md sync, or @-import them manually"
  fi

  printf '\n'
  log_ok "Setup complete"
  log_info "Restart shell + Claude Code to apply"
  log_info "Run /doctor or 'bash ~/.claude/doctor.sh' to verify"
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
    log_info "Contains: permissions allow/deny, plugins, model"
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
        if ((jq_status != 0)); then
          log_err "jq merge failed — settings unchanged. Output: $jq_err"
          return 1
        fi
        if [[ -z "$merged" ]]; then
          log_err "jq produced empty output — settings unchanged"
          return 1
        fi

        # Dry-run preview: show diff between current settings and proposed merge.
        # Bake $HOME before diff so the preview reflects the file that will
        # actually be written (the post-merge sed step expands $HOME literals).
        # Skipped in --full to keep batch flow uninterrupted; user can re-run
        # the interactive variant if they want to inspect.
        if ! $full_setup; then
          local merged_baked
          merged_baked=$(printf '%s\n' "$merged" | sed "s|\\\$HOME|$HOME|g")
          local diff_out
          diff_out=$(diff -u \
            <(jq -S . "$target" 2>/dev/null) \
            <(printf '%s\n' "$merged_baked" | jq -S . 2>/dev/null) \
            2>/dev/null)
          if [[ -n "$diff_out" ]]; then
            printf '\n'
            log_info "Proposed changes to ~/.claude/settings.json (current → merged):"
            printf '%s\n' "$diff_out" | head -50
            local diff_lines
            diff_lines=$(printf '%s\n' "$diff_out" | wc -l | tr -d ' ')
            if ((diff_lines > 50)); then
              log_info "($((diff_lines - 50)) more lines truncated)"
            fi
            printf '\n'
            if ! confirm "Apply this merge?" "y"; then
              log_skip "Settings unchanged"
              return
            fi
          else
            log_info "No effective changes — current settings already match merge result"
            return
          fi
        fi

        backup_file "$target"
        printf '%s\n' "$merged" >"$target"
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

  # If any merged value contains the literal string "$HOME", bake the absolute
  # path in — JSON has no env-var interpolation and Claude Code's command
  # runners (statusLine, hooks) don't always expand env vars depending on shell
  # context. Caveat: this sed is global, so any merged user value with "$HOME"
  # in a string position will also expand. In practice that matches user intent.
  if [[ -f "$target" ]] && grep -q '\$HOME' "$target"; then
    sed -i '' "s|\\\$HOME|$HOME|g" "$target"
  fi
}

# Statusline

# Required-dep nudge — jq is the only hard requirement (used by hooks + settings merge).
# Called before the multi-select so the user gets a clear early signal, not a mid-merge failure.

_cc_require_jq() {
  command -v jq >/dev/null 2>&1 && return 0
  log_warn "jq not in PATH — required for settings merge and hooks"
  if command -v brew >/dev/null 2>&1; then
    if confirm "Install jq via brew now?" "y"; then
      brew install jq 2>&1 | tail -3 || log_err "brew install jq failed"
    fi
  else
    log_info "brew not in PATH — install jq manually before re-running setup"
  fi
}

_cc_install_statusline() {
  printf '\n'
  log_info "Statusline is delegated to ccstatusline (community-standard)"
  log_info "Wired via settings.json → statusLine.command = bun x ccstatusline@latest"
  log_info "Customize widgets/colors with: bun x ccstatusline@latest (TUI)"
  printf '\n'

  if [[ "$MACRIFT_DRY_RUN" == true ]]; then
    log_info "Dry run — would verify bun/npx + prime ccstatusline"
    return
  fi

  _cc_install_statusline_copy
}

# Prime the package cache so the first real render isn't slow.
# No-op if bun/npx are missing — settings.json will surface the failure
# loudly enough that the user notices.
_cc_install_statusline_copy() {
  if [[ "$MACRIFT_DRY_RUN" == true ]]; then
    log_info "Would prime ccstatusline cache via bun/npx"
    return
  fi
  if command -v bun >/dev/null 2>&1; then
    if bun x ccstatusline@latest --version >/dev/null 2>&1; then
      log_ok "ccstatusline primed via bun"
    else
      log_warn "ccstatusline prime via bun failed — first render may be slow"
    fi
  elif command -v npx >/dev/null 2>&1; then
    if npx -y ccstatusline@latest --version >/dev/null 2>&1; then
      log_ok "ccstatusline primed via npx"
    else
      log_warn "ccstatusline prime via npx failed — first render may be slow"
    fi
  else
    log_err "neither bun nor npx in PATH — install one to use ccstatusline"
  fi
}

# Doctor — health check script, runnable both standalone and via /doctor

_cc_install_doctor_copy() {
  local source="$CC_CONFIG/doctor.sh"
  local target="$CLAUDE_DIR/doctor.sh"
  [[ -f "$source" ]] || return 0
  if [[ "$MACRIFT_DRY_RUN" == true ]]; then
    log_info "Would copy doctor.sh → $target"
    return
  fi
  _cc_ensure_dir
  copy_config "$source" "$target"
  chmod +x "$target" 2>/dev/null || true
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
  done <<<"$selected"

  printf '\n'
  log_ok "$count hook(s) installed to ~/.claude/hooks/"
}

_cc_install_hooks_copy() {
  local source_dir="$CC_CONFIG/hooks"
  local target_dir="$CLAUDE_DIR/hooks"
  [[ -d "$source_dir" ]] || return 0
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
  done <<<"$selected"

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
  ((count % 2 == 0))
}

# Shell-rc marker-block helper (works for zsh/bash/fish — all use # comments).
# Replaces (or appends) a block in $zshrc bounded by two identical marker lines.
# Body is read from stdin.
_cc_replace_marked_block() {
  local zshrc="$1"
  local marker="$2"

  mkdir -p "$(dirname "$zshrc")" 2>/dev/null  # fish: ~/.config/fish may not exist
  [[ -f "$zshrc" ]] || touch "$zshrc"

  if grep -qF "$marker" "$zshrc" 2>/dev/null; then
    if ! _cc_marker_balanced "$zshrc" "$marker"; then
      log_err "Unbalanced marker '$marker' in $zshrc — refusing to modify (would corrupt file)"
      return 1
    fi
    backup_file "$zshrc"
    local temp
    temp=$(mktemp)
    awk -v m="$marker" '$0==m{skip=!skip; next} !skip' "$zshrc" >"$temp"
    cp "$temp" "$zshrc"
    rm -f "$temp"
  fi

  {
    echo ""
    echo "$marker"
    cat
    echo "$marker"
  } >>"$zshrc"
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
  awk -v m="$marker" '$0==m{skip=!skip; next} !skip' "$zshrc" >"$temp"
  cp "$temp" "$zshrc"
  rm -f "$temp"
}

# Cross-shell support. macrift is zsh-first; bash/fish users get the right rc
# file + syntax. Unknown shells fall back to zsh (macOS default).
_cc_shell_kind() {
  case "${SHELL##*/}" in
    fish) printf 'fish' ;;
    bash) printf 'bash' ;;
    *) printf 'zsh' ;;
  esac
}

_cc_target_rc() {
  case "$(_cc_shell_kind)" in
    fish) printf '%s\n' "$HOME/.config/fish/config.fish" ;;
    bash) printf '%s\n' "$HOME/.bashrc" ;;
    *) printf '%s\n' "$HOME/.zshrc" ;;
  esac
}

# Render an `export VAR=value` line in the target shell's syntax.
# zsh/bash keep `export`; fish uses `set -gx`. Values in env.sh are bare tokens
# (no spaces), so no requoting is needed.
_cc_export_line() {
  local kind="$1" line="$2" body var val
  body="${line#export }"
  var="${body%%=*}"
  val="${body#*=}"
  if [[ "$kind" == fish ]]; then
    printf 'set -gx %s %s\n' "$var" "$val"
  else
    printf '%s\n' "$line"
  fi
}

# Environment

_cc_install_env() {
  local source="$CC_CONFIG/env.sh"

  if [[ ! -f "$source" ]]; then
    log_err "No env.sh found in config/claude-code/"
    return
  fi

  local kind rc
  kind=$(_cc_shell_kind)
  rc=$(_cc_target_rc)
  log_info "Environment variables to add to $rc:"
  printf '\n'
  while IFS= read -r line; do
    printf '  %b›%b %s\n' "$CYAN" "$RESET" "$(_cc_export_line "$kind" "$line")"
  done < <(grep -E '^export ' "$source")
  printf '\n'

  if [[ "$MACRIFT_DRY_RUN" == true ]]; then
    log_info "Dry run — would add env vars to $rc"
    return
  fi

  if ! confirm "Add Claude Code env vars to $rc?"; then return; fi

  _cc_install_env_copy
  log_info "Restart shell to apply"
}

_cc_install_env_copy() {
  local source="$CC_CONFIG/env.sh"
  [[ -f "$source" ]] || return 0
  local kind rc line
  kind=$(_cc_shell_kind)
  rc=$(_cc_target_rc)
  if [[ "$MACRIFT_DRY_RUN" == true ]]; then
    log_info "Would write env block to $rc"
    return
  fi

  while IFS= read -r line; do
    _cc_export_line "$kind" "$line"
  done < <(grep -E '^export ' "$source") |
    _cc_replace_marked_block "$rc" "$CC_ENV_MARKER"
  log_ok "Environment variables added to $rc"
}

# brew install a tool if missing. Used by Full Setup multi-select to
# opt-in formatters / utilities. Silent no-op if already present or brew absent.
_cc_brew_install_optional() {
  local tool=$1
  if command -v "$tool" >/dev/null 2>&1; then
    log_skip "$tool already installed"
    return 0
  fi
  if ! command -v brew >/dev/null 2>&1; then
    log_warn "$tool: brew not in PATH — install manually"
    return 1
  fi
  log_info "brew install $tool"
  brew install "$tool" 2>&1 | tail -3 || {
    log_err "brew install $tool failed"
    return 1
  }
  log_ok "$tool installed"
}

# CLAUDE.md (rule imports)

_cc_install_claude_md() {
  if [[ "$MACRIFT_DRY_RUN" == true ]]; then
    log_info "Dry run — would write rule imports to ~/.claude/CLAUDE.md"
    return
  fi

  log_info "Syncs @~/.claude/rules/<rule>.md imports in ~/.claude/CLAUDE.md"
  log_info "Adds imports for new rules; removes imports whose rule files no longer exist."
  printf '\n'
  if ! confirm "Sync CLAUDE.md rule imports?"; then return; fi

  _cc_install_claude_md_copy
}

_cc_install_claude_md_copy() {
  local rules_dir="$CC_CONFIG/rules"
  local claude_md="$CLAUDE_DIR/CLAUDE.md"

  [[ -d "$rules_dir" ]] || {
    log_err "No rules dir at $rules_dir"
    return
  }

  if [[ "$MACRIFT_DRY_RUN" == true ]]; then
    log_info "Would sync rule imports in $claude_md"
    return
  fi

  _cc_ensure_dir
  [[ -f "$claude_md" ]] || touch "$claude_md"

  local present=()
  local f rule_name
  for f in "$rules_dir"/*.md; do
    [[ -f "$f" ]] || continue
    rule_name="$(basename "$f" .md)"
    present+=("$rule_name")
  done

  local backed_up=false
  local removed=0
  local stale_rules=()
  while IFS= read -r line; do
    [[ "$line" =~ ^@~/.claude/rules/(.+)\.md$ ]] || continue
    rule_name="${BASH_REMATCH[1]}"
    local found=false
    local p
    for p in "${present[@]}"; do
      [[ "$p" == "$rule_name" ]] && {
        found=true
        break
      }
    done
    $found || stale_rules+=("$rule_name")
  done <"$claude_md"

  if [[ ${#stale_rules[@]} -gt 0 ]]; then
    backup_file "$claude_md"
    backed_up=true
    for rule_name in "${stale_rules[@]}"; do
      local line="@~/.claude/rules/$rule_name.md"
      local escaped
      escaped=$(printf '%s' "$line" | sed 's/[\/&]/\\&/g')
      sed -i.tmp "/^${escaped}$/d" "$claude_md" && rm -f "$claude_md.tmp"
      removed=$((removed + 1))
    done
  fi

  local added=0
  for rule_name in "${present[@]}"; do
    local line="@~/.claude/rules/$rule_name.md"
    if ! grep -qF "$line" "$claude_md"; then
      if ! $backed_up; then
        backup_file "$claude_md"
        printf '\n' >>"$claude_md"
        backed_up=true
      fi
      printf '%s\n' "$line" >>"$claude_md"
      added=$((added + 1))
    fi
  done

  if [[ $added -gt 0 || $removed -gt 0 ]]; then
    log_ok "CLAUDE.md synced (+$added import(s), -$removed stale)"
  else
    log_skip "CLAUDE.md already in sync"
  fi
}

# 'r' alias

_cc_install_r_alias() {
  local rc
  rc=$(_cc_target_rc)
  if [[ "$MACRIFT_DRY_RUN" == true ]]; then
    log_info "Dry run — would add 'r' alias to $rc"
    return
  fi

  log_info "Adds: alias r='bash /tmp/cmd.sh'  (used by workflow rule)"
  printf '\n'
  if ! confirm "Add 'r' alias to $rc?"; then return; fi

  _cc_install_r_alias_copy
  log_info "Restart shell to apply"
}

_cc_install_r_alias_copy() {
  local rc
  rc=$(_cc_target_rc)
  if [[ "$MACRIFT_DRY_RUN" == true ]]; then
    log_info "Would add 'r' alias to $rc"
    return
  fi
  # `alias r='bash /tmp/cmd.sh'` is valid in zsh, bash, and fish alike.
  printf "alias r='bash /tmp/cmd.sh'\n" |
    _cc_replace_marked_block "$rc" "$CC_RALIAS_MARKER"
  log_ok "'r' alias added to $rc"
}

# MCP servers
# Installed user-scoped via `claude mcp add --scope user`, so they apply
# across every project without per-repo .mcp.json. Idempotent: skips any
# server already present in `claude mcp list`.

_cc_mcp_names() {
  printf '%s\n' "context7" "playwright"
}

_cc_mcp_desc() {
  case "$1" in
    context7) printf 'live library docs (eliminates hallucinated APIs)' ;;
    playwright) printf 'browser automation / E2E test generation' ;;
  esac
}

_cc_mcp_install_one() {
  command -v claude >/dev/null 2>&1 || {
    log_err "'claude' CLI not found — install Claude Code first"
    return 1
  }
  case "$1" in
    context7)
      claude mcp add --scope user --transport http context7 \
        https://mcp.context7.com/mcp >/dev/null 2>&1
      ;;
    playwright)
      command -v npx >/dev/null 2>&1 || {
        log_err "playwright MCP needs 'npx' (Node.js) — not in PATH"
        return 1
      }
      claude mcp add --scope user playwright -- \
        npx -y @playwright/mcp@latest >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

_cc_install_mcp() {
  if ! command -v claude >/dev/null 2>&1; then
    log_err "'claude' CLI not found — install Claude Code first"
    wait_enter
    return 1
  fi

  local names=()
  while IFS= read -r n; do names+=("$n"); done < <(_cc_mcp_names)

  printf '\n'
  log_info "MCP servers — installed user-scoped (apply to every project):"
  local n
  for n in "${names[@]}"; do
    log_info "  $n — $(_cc_mcp_desc "$n")"
  done
  printf '\n'
  local selected
  selected=$(show_multiselect "MCP Servers" "${names[@]}")
  [[ -z "$selected" ]] && return

  if [[ "$MACRIFT_DRY_RUN" == true ]]; then
    log_info "Dry run — would install: $(echo "$selected" | tr '\n' ' ')"
    wait_enter
    return
  fi

  local existing
  existing=$(claude mcp list 2>/dev/null | awk -F: 'NF{print $1}')

  local count=0 skipped=0 failed=0
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if grep -qx "$name" <<<"$existing"; then
      log_skip "$name already configured"
      skipped=$((skipped + 1))
      continue
    fi
    if _cc_mcp_install_one "$name"; then
      log_ok "$name installed"
      count=$((count + 1))
    else
      log_err "$name install failed"
      failed=$((failed + 1))
    fi
  done <<<"$selected"

  printf '\n'
  log_info "$count installed, $skipped already present, $failed failed"
  wait_enter
}

_cc_install_mcp_copy() {
  _cc_install_mcp
}

# Reset

_cc_reset() {
  local rc
  rc=$(_cc_target_rc)
  clear
  printf '\n'
  printf '  %bClaude Code — Reset%b\n\n' "$BOLD" "$RESET"
  printf '  Will %bDELETE%b:\n' "$RED" "$RESET"
  printf '    %s/settings.json (+ .bak)\n' "$CLAUDE_DIR"
  printf '    %s/settings.local.json\n' "$CLAUDE_DIR"
  printf '    %s/CLAUDE.md\n' "$CLAUDE_DIR"
  printf '    %s/env.sh\n' "$CLAUDE_DIR"
  printf '    %s/{agents,commands,rules,hooks}/ (incl. *.bak inside)\n' "$CLAUDE_DIR"
  printf '    macrift sections in %s (env block + r-alias block)\n\n' "$rc"
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
    "$CLAUDE_DIR/CLAUDE.md.bak" "$CLAUDE_DIR/env.sh"
  rm -rf "$CLAUDE_DIR/agents" "$CLAUDE_DIR/commands" "$CLAUDE_DIR/rules" "$CLAUDE_DIR/hooks"

  _cc_strip_marked_block "$rc" "$CC_ENV_MARKER"
  _cc_strip_marked_block "$rc" "$CC_RALIAS_MARKER"

  log_ok "Claude Code state wiped"

  # Telegram engines (supercharged + ccgram) — opt-in (separate confirms so
  # tokens + repos + uv-tool installs aren't nuked by accident). The Telegram
  # constants + cleanup fn live in the lazily-sourced engine file.
  source "$MACRIFT_DIR/customize/claude_code_telegram.sh"
  local has_super=false has_ccgram=false has_legacy=false
  [[ -e "$HOME/Library/LaunchAgents/com.claude-telegram-ts.plist" ||
    -e "$HOME/.local/bin/supercharged-launcher.sh" ||
    -d "$CC_SUPERCHARGED_REPO" ||
    -f "$HOME/.claude/scripts/telegram-supervisor.ts" ]] && has_super=true
  [[ -e "$CC_CCGRAM_LAUNCH_AGENT" || -e "$CC_CCGRAM_LAUNCHER" ||
    -d "$CC_CCGRAM_CONFIG_DIR" ]] && has_ccgram=true
  [[ -e "$CC_TG_LEGACY_LAUNCH_AGENT" || -e "$CC_TG_LEGACY_OLD_PLIST" ||
    -e "$CC_TG_LEGACY_LAUNCHER" || -e "$CC_TG_LEGACY_OLD_LAUNCHER" ||
    -e "$CC_TG_LEGACY_ENV_FILE" ]] && has_legacy=true

  if $has_super; then
    printf '\n'
    log_info "Telegram supercharged artifacts:"
    [[ -e "$HOME/Library/LaunchAgents/com.claude-telegram-ts.plist" ]] && printf '    %s\n' "$HOME/Library/LaunchAgents/com.claude-telegram-ts.plist"
    [[ -e "$HOME/.local/bin/supercharged-launcher.sh" ]] && printf '    %s\n' "$HOME/.local/bin/supercharged-launcher.sh"
    [[ -d "$CC_SUPERCHARGED_REPO" ]] && printf '    %s/ (repo)\n' "$CC_SUPERCHARGED_REPO"
    [[ -f "$HOME/.claude/scripts/telegram-supervisor.ts" ]] && printf '    %s\n' "$HOME/.claude/scripts/telegram-supervisor.ts"
    printf '\n'
    if confirm "Also wipe Telegram supercharged?" "n"; then
      launchctl bootout "gui/$UID/com.claude-telegram-ts" 2>/dev/null || true
      rm -f "$HOME/Library/LaunchAgents/com.claude-telegram-ts.plist" \
        "$HOME/.local/bin/supercharged-launcher.sh" \
        "$HOME/.claude/scripts/telegram-supervisor.ts" \
        "$HOME/.claude/scripts/claude-daemon-wrapper.exp"
      if confirm "Also delete repo + token (~/.claude/channels/telegram/.env)?" "n"; then
        rm -rf "$CC_SUPERCHARGED_REPO"
        rm -f "$HOME/.claude/channels/telegram/.env"
      fi
      log_ok "Supercharged wiped"
    fi
  fi

  if $has_ccgram; then
    printf '\n'
    log_info "Telegram ccgram artifacts:"
    [[ -e "$CC_CCGRAM_LAUNCH_AGENT" ]] && printf '    %s\n' "$CC_CCGRAM_LAUNCH_AGENT"
    [[ -e "$CC_CCGRAM_LAUNCHER" ]] && printf '    %s\n' "$CC_CCGRAM_LAUNCHER"
    [[ -d "$CC_CCGRAM_CONFIG_DIR" ]] && printf '    %s/ (config + state)\n' "$CC_CCGRAM_CONFIG_DIR"
    printf '\n'
    if confirm "Also wipe Telegram ccgram?" "n"; then
      launchctl bootout "gui/$UID/$CC_CCGRAM_LAUNCH_AGENT_LABEL" 2>/dev/null || true
      pkill -9 -f "/ccgram$\| ccgram$" 2>/dev/null || true
      rm -f "$CC_CCGRAM_LAUNCH_AGENT" "$CC_CCGRAM_LAUNCHER"
      if confirm "Also delete config dir $CC_CCGRAM_CONFIG_DIR (loses .env token + session_map)?" "n"; then
        rm -rf "$CC_CCGRAM_CONFIG_DIR"
      fi
      if command -v uv >/dev/null 2>&1 && uv tool list 2>/dev/null | grep -q '^ccgram'; then
        if confirm "Also uninstall ccgram via 'uv tool uninstall ccgram'?" "n"; then
          uv tool uninstall ccgram 2>&1 | tail -3
        fi
      fi
      log_ok "ccgram wiped"
    fi
  fi

  if $has_legacy; then
    printf '\n'
    log_info "Legacy plugin artifacts:"
    [[ -e "$CC_TG_LEGACY_LAUNCH_AGENT" ]] && printf '    %s\n' "$CC_TG_LEGACY_LAUNCH_AGENT"
    [[ -e "$CC_TG_LEGACY_OLD_PLIST" ]] && printf '    %s\n' "$CC_TG_LEGACY_OLD_PLIST"
    [[ -e "$CC_TG_LEGACY_LAUNCHER" ]] && printf '    %s\n' "$CC_TG_LEGACY_LAUNCHER"
    [[ -e "$CC_TG_LEGACY_OLD_LAUNCHER" ]] && printf '    %s\n' "$CC_TG_LEGACY_OLD_LAUNCHER"
    [[ -e "$CC_TG_LEGACY_ENV_FILE" ]] && printf '    %s (bot token)\n' "$CC_TG_LEGACY_ENV_FILE"
    printf '\n'
    if confirm "Also wipe legacy plugin remnants?" "n"; then
      _cc_uninstall_legacy_plugin_copy
    fi
  fi

  if grep -qF "$CC_TG_PATH_MARKER" "$rc" 2>/dev/null; then
    if confirm "Strip ~/.local/bin PATH block from $rc?" "n"; then
      _cc_strip_marked_block "$rc" "$CC_TG_PATH_MARKER"
      log_ok "PATH block stripped"
    fi
  fi

  log_info "Run Full Setup to reinstall"
}

# Helpers

_cc_ensure_dir() {
  mkdir -p "$CLAUDE_DIR"
}

# Ensure ~/.local/bin is on PATH. uv/bun drop launchers (ccgram, supercharged)
# there, but a clean login shell may not include it. Idempotent via marker block;
# also exports for the current session so the just-installed binary runs now.
# Returns 1 only if the .zshrc write fails (e.g. unbalanced marker).
_cc_ensure_local_bin_on_path() {
  local bindir="$HOME/.local/bin"
  case ":$PATH:" in
    *":$bindir:"*) return 0 ;;
  esac
  local kind rc body
  kind=$(_cc_shell_kind)
  rc=$(_cc_target_rc)
  if [[ "$kind" == fish ]]; then
    body='fish_add_path "$HOME/.local/bin"'
  else
    body='export PATH="$HOME/.local/bin:$PATH"'
  fi
  printf '%s\n' "$body" |
    _cc_replace_marked_block "$rc" "$CC_TG_PATH_MARKER" || return 1
  export PATH="$bindir:$PATH"
  log_ok "Added ~/.local/bin to PATH ($rc + this session)"
}
