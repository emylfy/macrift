#!/usr/bin/env bash
# macrift — Claude Code Telegram bot (supercharged + ccgram engines).
# Sourced lazily by customize/claude_code.sh (Telegram menu + reset cleanup)
# so the core file stays focused on the Claude Code config itself.

# Telegram bot — _cc_telegram_menu offers two engines: supercharged or ccgram.
# Engine constants are grouped per engine below.

# VPN-wait gate: apps the launcher may open before starting the bot (the most
# recently used installed one wins). Override for your own VPN client, e.g.
#   export CC_VPN_APPS="Mullvad"        # or "" to skip opening any app
CC_VPN_APPS="${CC_VPN_APPS:-Happ V2RayTun}"

# supercharged engine repo location. Defaults under ~/.claude (locale-independent,
# unlike ~/Documents). Override with: export CC_SUPERCHARGED_REPO=/path/to/repo
CC_SUPERCHARGED_REPO="${CC_SUPERCHARGED_REPO:-$HOME/.claude/telegram-supercharged}"

# ccgram engine (alexei-led/ccgram) — tmux-bridge, parallel sessions per Forum topic.
CC_CCGRAM_REPO_URL="https://github.com/alexei-led/ccgram"
CC_CCGRAM_CONFIG_DIR="$HOME/.ccgram"
CC_CCGRAM_LAUNCH_AGENT_LABEL="com.user.ccgram"
CC_CCGRAM_LAUNCH_AGENT="$HOME/Library/LaunchAgents/$CC_CCGRAM_LAUNCH_AGENT_LABEL.plist"
CC_CCGRAM_LAUNCHER="$HOME/.local/bin/ccgram-launcher.sh"

# Legacy paths from previous plugin / linuz90 setups — kept so cleanup can find them.
CC_TG_LEGACY_LAUNCHER="$HOME/.local/bin/ctg"
CC_TG_LEGACY_LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.claude-tg.plist"
CC_TG_LEGACY_LAUNCH_AGENT_LABEL="com.claude-tg"
CC_TG_LEGACY_ENV_FILE="$HOME/.claude/channels/telegram/.env"
CC_TG_LEGACY_OLD_PLIST="$HOME/Library/LaunchAgents/com.emylfy.claude-telegram.plist"
CC_TG_LEGACY_OLD_LABEL="com.emylfy.claude-telegram"
CC_TG_LEGACY_OLD_LAUNCHER="$HOME/.local/bin/claude-telegram.sh"

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
    printf '  %bccgram%b: tmux-bridge. Each Telegram Forum topic = 1 tmux window =\n' "$CYAN" "$RESET"
    printf '    1 standalone claude session. /esc interrupts, desktop continuity\n'
    printf '    via tmux attach.  ✓ parallel sessions, %brequires forum group%b (not DM)\n\n' "$YELLOW" "$RESET"

    local choice
    choice=$(show_menu "Telegram bot" \
      "supercharged (DM, single session) ›" \
      "ccgram (forum, parallel sessions) ›" \
      "Back")

    case "$choice" in
      1) _cc_supercharged_menu ;;
      2) _cc_ccgram_menu ;;
      0) break ;;
      *) ;;
    esac
  done
  crumb_pop
}

# ccgram engine submenu

_cc_ccgram_menu() {
  crumb_push "ccgram"
  while true; do
    clear

    local choice
    choice=$(show_menu "Telegram bot (ccgram — alexei-led/ccgram)" \
      "Full setup" \
      "---" \
      "Check deps (uv, tmux)" \
      "Install ccgram via uv (or upgrade if already installed)" \
      "Configure ~/.ccgram/.env (token + ALLOWED_USERS)" \
      "Install Claude Code SessionStart hook (ccgram hook --install)" \
      "Pairing help (manual TG forum group + BotFather steps)" \
      "Install LaunchAgent (autostart + VPN-wait wrapper)" \
      "---" \
      "Migrate from supercharged (stop launchd, keep repo as fallback)" \
      "Remove ccgram launcher + autostart (keep config + uv tool)" \
      "Back")

    case "$choice" in
      1)
        _cc_install_ccgram_full
        wait_enter
        ;;
      2)
        _cc_install_ccgram_deps
        wait_enter
        ;;
      3)
        _cc_install_ccgram_install
        wait_enter
        ;;
      4)
        _cc_install_ccgram_env
        wait_enter
        ;;
      5)
        _cc_install_ccgram_hook
        wait_enter
        ;;
      6)
        _cc_install_ccgram_pairing_help
        wait_enter
        ;;
      7)
        _cc_install_ccgram_launchagent
        wait_enter
        ;;
      8)
        _cc_migrate_supercharged_to_ccgram
        wait_enter
        ;;
      9)
        _cc_remove_ccgram
        wait_enter
        ;;
      0) break ;;
      *) ;;
    esac
  done
  crumb_pop
}

# 1. Deps check (uv + tmux are mandatory; ccgram won't run without them)

_cc_install_ccgram_deps() {
  printf '\n'
  log_info "ccgram needs: uv (Python tool), tmux (terminal multiplexer), claude (Claude Code CLI)"
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

  if ((${#missing[@]} == 0)); then
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

# 2. Install ccgram via uv tool

_cc_install_ccgram_install() {
  if ! command -v uv >/dev/null 2>&1; then
    log_err "uv not found — install: brew install uv"
    return 1
  fi
  printf '\n'
  log_info "Installs ccgram from PyPI via 'uv tool install ccgram' (upstream: $CC_CCGRAM_REPO_URL)."
  log_info "If already installed, runs 'uv tool upgrade ccgram' to pull latest."
  printf '\n'
  if [[ "$MACRIFT_DRY_RUN" == true ]]; then
    log_info "Dry run — would install ccgram"
    return
  fi
  if ! confirm "Install / upgrade ccgram?"; then return; fi
  _cc_install_ccgram_install_copy
}

_cc_install_ccgram_install_copy() {
  if uv tool list 2>/dev/null | grep -q '^ccgram'; then
    log_info "Upgrading ccgram..."
    uv tool upgrade ccgram 2>&1 | tail -3 ||
      uv tool install --reinstall ccgram 2>&1 | tail -3
  else
    log_info "Installing ccgram..."
    uv tool install ccgram 2>&1 | tail -3
  fi

  if command -v ccgram >/dev/null 2>&1; then
    log_ok "ccgram binary at: $(command -v ccgram)"
  else
    log_warn "ccgram not on PATH — adding ~/.local/bin"
    if ! _cc_ensure_local_bin_on_path; then
      log_warn "Could not update PATH automatically — add ~/.local/bin to your shell rc"
    fi
  fi
}

# 3. Configure ~/.ccgram/.env

_cc_install_ccgram_env() {
  printf '\n'
  log_info "Stores token + allowed user(s) in $CC_CCGRAM_CONFIG_DIR/.env (chmod 600)."
  printf '\n'
  if [[ "$MACRIFT_DRY_RUN" == true ]]; then
    log_info "Dry run — would prompt for token + user_id"
    return
  fi
  _cc_install_ccgram_env_copy
}

_cc_install_ccgram_env_copy() {
  local env_file="$CC_CCGRAM_CONFIG_DIR/.env"
  mkdir -p "$CC_CCGRAM_CONFIG_DIR"

  # Token — try to reuse from supercharged if available
  local existing_token=""
  if [[ -f "$env_file" ]]; then
    existing_token=$(grep -E '^TELEGRAM_BOT_TOKEN=' "$env_file" 2>/dev/null | tail -1 |
      sed 's/^TELEGRAM_BOT_TOKEN=//' | tr -d '"' | tr -d "'")
  fi
  if [[ -z "$existing_token" ]] && [[ -f "$HOME/.claude/channels/telegram/.env" ]]; then
    existing_token=$(grep -E '^TELEGRAM_BOT_TOKEN=' "$HOME/.claude/channels/telegram/.env" 2>/dev/null | tail -1 |
      sed 's/^TELEGRAM_BOT_TOKEN=//' | tr -d '"' | tr -d "'")
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
    user_id=$(grep -E '^ALLOWED_USERS=' "$env_file" 2>/dev/null | tail -1 |
      sed 's/^ALLOWED_USERS=//' | cut -d, -f1)
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
  cat >"$env_file" <<ENV
TELEGRAM_BOT_TOKEN=$token
ALLOWED_USERS=$user_id
TMUX_SESSION_NAME=ccgram
CLAUDE_COMMAND=claude
ENV
  chmod 600 "$env_file"
  log_ok "Wrote $env_file"
}

# 4. Install ccgram SessionStart hook

_cc_install_ccgram_hook() {
  if ! command -v ccgram >/dev/null 2>&1; then
    log_err "ccgram not in PATH — install first"
    return 1
  fi
  printf '\n'
  log_info "Adds 'ccgram hook' as a SessionStart hook in ~/.claude/settings.json."
  log_info "Each new Claude Code session writes its tmux window↔session mapping"
  log_info "to $CC_CCGRAM_CONFIG_DIR/session_map.json so ccgram can route TG topics to it."
  printf '\n'
  if [[ "$MACRIFT_DRY_RUN" == true ]]; then
    log_info "Dry run — would run 'ccgram hook --install'"
    return
  fi
  if ! confirm "Install hook?"; then return; fi

  backup_file "$CLAUDE_DIR/settings.json"
  if ccgram hook --install 2>&1 | tail -5; then
    log_ok "Hook installed"
  else
    log_err "ccgram hook --install failed"
    return 1
  fi
}

# 5. Manual pairing help — interactive step-by-step checklist
# Each step opens the relevant URL when possible (BotFather chat) and waits
# for user confirmation before moving on. Lets the user pause and resume.

_cc_install_ccgram_pairing_help() {
  printf '\n'
  printf '  %bccgram pairing — interactive step-by-step%b\n\n' "$BOLD" "$RESET"
  printf '  ccgram routes by Forum topics, not DMs. We will walk through 5 manual\n'
  printf '  Telegram steps. Press %b[Enter]%b to advance, %b[s]%b to skip a step,\n' "$BOLD" "$RESET" "$BOLD" "$RESET"
  printf '  %b[q]%b to quit the checklist (you can re-run it later from this menu).\n\n' "$BOLD" "$RESET"
  if ! confirm "Start checklist?" "y"; then return; fi

  _cc_ccgram_step "1/6: Enable Threaded Mode in @BotFather" \
    "Open @BotFather → /mybots → select your bot → Bot Settings → Threaded Mode → Enable" \
    "tg://resolve?domain=BotFather" \
    "https://t.me/BotFather" || return 0

  _cc_ccgram_step "2/6: DISABLE Group Privacy in @BotFather (critical!)" \
    "Same Bot Settings menu → Group Privacy → Turn OFF. Without this, the bot sees ONLY @-mentions in groups, NOT regular messages — ccgram will receive nothing and topics won't trigger directory browser. This is the #1 reason ccgram 'doesn't respond'." \
    "tg://resolve?domain=BotFather" \
    "https://t.me/BotFather" || return 0

  _cc_ccgram_step "3/6: Create or pick a Telegram group with Topics" \
    "In Telegram, create a new group (long-press 'New' → 'New Group') OR open an existing one. In group Settings → enable 'Topics' (forum mode)." \
    "" "" || return 0

  _cc_ccgram_step "4/6: Add your bot to the group as admin" \
    "Group Settings → Administrators → Add Admin → search for your bot → grant 'Send Messages' permission → Save" \
    "" "" || return 0

  _cc_ccgram_step "5/6: Verify ccgram is running" \
    "ccgram is managed by launchd. Status check below — should show 'state = running' with a pid." \
    "" "" || return 0
  if launchctl print "gui/$UID/$CC_CCGRAM_LAUNCH_AGENT_LABEL" 2>&1 | grep -E "^\s*(state|pid)" | head -3; then
    :
  else
    log_warn "ccgram LaunchAgent not loaded — install via 'Install LaunchAgent' menu first"
  fi
  printf '  Press [Enter] when verified... '
  read -r _

  _cc_ccgram_step "6/6: Send first message in a topic" \
    "In your TG group, long-press 'New' → 'New Topic' → name it (e.g. 'macrift'). Send any message. Bot replies with a directory browser — choose your project dir. tmux window opens, claude starts there, your message goes in." \
    "" "" || return 0

  printf '\n'
  log_ok "All 6 steps acknowledged. Watch live with: tail -f /tmp/ccgram.log"
}

# Helper: print a step, optionally open URL(s), wait for input
_cc_ccgram_step() {
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
    q | Q)
      log_skip "checklist quit at: $title"
      return 1
      ;;
    s | S)
      log_skip "skipped: $title"
      return 0
      ;;
    *)
      log_ok "done: $title"
      return 0
      ;;
  esac
}

# 6. LaunchAgent — VPN-aware wrapper, exec ccgram

_cc_install_ccgram_launchagent() {
  if ! command -v ccgram >/dev/null 2>&1; then
    log_err "ccgram binary not in PATH — install first"
    return 1
  fi
  if [[ ! -f "$CC_CCGRAM_CONFIG_DIR/.env" ]]; then
    log_err ".env missing — configure it first"
    return 1
  fi
  printf '\n'
  log_info "Installs $CC_CCGRAM_LAUNCH_AGENT"
  log_info "+ $CC_CCGRAM_LAUNCHER wrapper (exec's ccgram)"
  log_info "Optional VPN-wait gate: open your VPN app ($CC_VPN_APPS), wait for anthropic NOT 403 (max 180s)"
  log_info "Logs: /tmp/ccgram.{log,err}"
  printf '\n'
  if [[ "$MACRIFT_DRY_RUN" == true ]]; then
    log_info "Dry run — would install LaunchAgent + wrapper"
    return
  fi
  if ! confirm "Install autostart?"; then return; fi
  _cc_install_ccgram_launchagent_copy
}

_cc_install_ccgram_launchagent_copy() {
  local ccgram_bin
  ccgram_bin=$(command -v ccgram)

  local with_vpn=false
  if confirm "Add VPN-wait gate to launcher? (opens your VPN app: $CC_VPN_APPS, waits until anthropic returns NOT 403)" "n"; then
    with_vpn=true
  fi

  mkdir -p "$(dirname "$CC_CCGRAM_LAUNCHER")"
  if $with_vpn; then
    {
      printf '#!/bin/zsh\n'
      printf '# ccgram launcher with VPN-aware wait gate (generated by macrift).\n'
      # Inject the configured app list; the body below picks the most-recently-used.
      printf 'vpn_apps=(%s)\n' "$CC_VPN_APPS"
      cat <<'LAUNCHER_EOF'
set -u
export PATH="$HOME/.local/bin:$HOME/.bun/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# Open the most-recently-used installed VPN app (by Application Support mtime).
best=""; best_mtime=0
for app in "${vpn_apps[@]}"; do
  m=$(stat -f %m "$HOME/Library/Application Support/$app" 2>/dev/null || echo 0)
  (( m > best_mtime )) && { best_mtime=$m; best=$app; }
done
if [ -n "$best" ]; then
  echo "[ccgram-launcher] opening $best (mtime=$best_mtime)"
  open -a "$best" 2>/dev/null
else
  echo "[ccgram-launcher] no known VPN app installed (${vpn_apps[*]:-none}) — skipping open"
fi

echo "[ccgram-launcher] waiting for VPN + anthropic routing (max 180s)..."
deadline=$(( $(date +%s) + 180 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  if scutil --nwi 2>/dev/null | grep -q "VPN server"; then
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 https://api.anthropic.com 2>/dev/null || echo 0)
    if [ "$code" != "0" ] && [ "$code" != "403" ]; then
      echo "[ccgram-launcher] VPN up + anthropic routed (HTTP $code)"
      break
    fi
  fi
  sleep 3
done

echo "[ccgram-launcher] exec'ing ccgram"
exec ccgram
LAUNCHER_EOF
    } >"$CC_CCGRAM_LAUNCHER"
  else
    cat >"$CC_CCGRAM_LAUNCHER" <<'LAUNCHER_EOF'
#!/bin/zsh
# ccgram launcher (no VPN gate).

set -u
export PATH="$HOME/.local/bin:$HOME/.bun/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

echo "[ccgram-launcher] exec'ing ccgram"
exec ccgram
LAUNCHER_EOF
  fi
  chmod +x "$CC_CCGRAM_LAUNCHER"
  log_ok "Wrote $CC_CCGRAM_LAUNCHER ($($with_vpn && echo with || echo without) VPN gate)"

  mkdir -p "$(dirname "$CC_CCGRAM_LAUNCH_AGENT")"
  cat >"$CC_CCGRAM_LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$CC_CCGRAM_LAUNCH_AGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$CC_CCGRAM_LAUNCHER</string>
    </array>
    <key>KeepAlive</key><true/>
    <key>RunAtLoad</key><true/>
    <key>ThrottleInterval</key><integer>30</integer>
    <key>StandardOutPath</key><string>/tmp/ccgram.log</string>
    <key>StandardErrorPath</key><string>/tmp/ccgram.err</string>
</dict>
</plist>
PLIST

  if ! plutil -lint "$CC_CCGRAM_LAUNCH_AGENT" >/dev/null 2>&1; then
    log_err "Generated plist is invalid"
    return 1
  fi

  launchctl bootout "gui/$UID/$CC_CCGRAM_LAUNCH_AGENT_LABEL" 2>/dev/null || true
  if ! launchctl bootstrap "gui/$UID" "$CC_CCGRAM_LAUNCH_AGENT" 2>/tmp/cc-ccgram-bootstrap.err; then
    log_err "launchctl bootstrap failed:"
    cat /tmp/cc-ccgram-bootstrap.err 2>/dev/null
    return 1
  fi
  launchctl kickstart -k "gui/$UID/$CC_CCGRAM_LAUNCH_AGENT_LABEL" 2>/dev/null || true
  log_ok "ccgram LaunchAgent installed and started"
}

# 7. Full setup orchestrator

_cc_install_ccgram_full() {
  printf '\n'
  log_info "Full setup: deps check -> install -> env -> hook -> pairing-help -> launchagent"
  log_info "Pairing remains manual (TG forum group setup + BotFather Threaded Mode)."
  printf '\n'
  if [[ "$MACRIFT_DRY_RUN" == true ]]; then
    log_info "Dry run — would run all steps"
    return
  fi
  if ! confirm "Run full setup?"; then return; fi

  _cc_install_ccgram_deps || return 1
  _cc_install_ccgram_install_copy || return 1
  _cc_install_ccgram_env_copy || return 1
  _cc_install_ccgram_hook || return 1
  _cc_install_ccgram_pairing_help

  if confirm "Install LaunchAgent now (recommended after pairing is verified)?" "n"; then
    _cc_install_ccgram_launchagent_copy || return 1
  fi

  printf '\n'
  log_ok "ccgram setup complete"
  log_info "Logs: tail -f /tmp/ccgram.log"
}

# 8. Migrate from supercharged: stop its launchd, leave repo as fallback

_cc_migrate_supercharged_to_ccgram() {
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

  if launchctl bootout "gui/$UID/com.claude-telegram-ts" 2>/dev/null; then
    log_ok "supercharged launchd stopped"
  else
    log_skip "supercharged launchd not loaded"
  fi
  rm -fv "$HOME/Library/LaunchAgents/com.claude-telegram-ts.plist" \
    "$HOME/.local/bin/supercharged-launcher.sh" 2>/dev/null
  pkill -9 -f "telegram-supervisor.ts" 2>/dev/null || true
  pkill -9 -f "claude --channels" 2>/dev/null || true
  log_ok "supercharged stopped — repo + plugin + token preserved"
  log_info "To revert: macrift menu → Telegram → supercharged → Install LaunchAgent"
}

# 9. Remove ccgram launcher + autostart

_cc_remove_ccgram() {
  printf '\n'
  log_info "Removes LaunchAgent + launcher script."
  log_info "Preserves: ccgram binary (uv tool), $CC_CCGRAM_CONFIG_DIR/, hook in settings.json."
  printf '\n'
  if [[ "$MACRIFT_DRY_RUN" == true ]]; then
    log_info "Dry run — would remove LaunchAgent + launcher"
    return
  fi
  if ! confirm "Remove ccgram launcher + autostart?" "n"; then
    log_skip "Removal cancelled"
    return
  fi
  launchctl bootout "gui/$UID/$CC_CCGRAM_LAUNCH_AGENT_LABEL" 2>/dev/null || true
  rm -f "$CC_CCGRAM_LAUNCH_AGENT" "$CC_CCGRAM_LAUNCHER"
  pkill -9 -f "/ccgram$\| ccgram$" 2>/dev/null || true
  log_ok "ccgram launcher and LaunchAgent removed"
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
      "Full setup" \
      "---" \
      "Install/restore official plugin (with upstream fallback)" \
      "Apply supercharged (drop server.ts + supervisor + skills)" \
      "Create runtime dirs (data/inbox)" \
      "Set bot token (writes ~/.claude/channels/telegram/.env)" \
      "Pairing help (manual step in fresh claude --channels session)" \
      "Install LaunchAgent (autostart + VPN-wait wrapper)" \
      "---" \
      "Re-apply after plugin auto-update overwrote server.ts" \
      "Migrate from old plugin / linuz90 (cleanup remnants)" \
      "Remove launcher + autostart (keep repo + token)" \
      "Back")

    case "$choice" in
      1)
        _cc_install_supercharged_full
        wait_enter
        ;;
      2)
        _cc_install_supercharged_plugin
        wait_enter
        ;;
      3)
        _cc_install_supercharged_apply
        wait_enter
        ;;
      4)
        _cc_install_supercharged_dirs
        wait_enter
        ;;
      5)
        _cc_install_supercharged_token
        wait_enter
        ;;
      6)
        _cc_install_supercharged_pairing_help
        wait_enter
        ;;
      7)
        _cc_install_supercharged_launchagent
        wait_enter
        ;;
      8)
        _cc_install_supercharged_reapply
        wait_enter
        ;;
      9)
        _cc_uninstall_legacy_plugin
        wait_enter
        ;;
      10)
        _cc_remove_supercharged
        wait_enter
        ;;
      0) break ;;
      *) ;;
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
    if jq -e '.plugins["telegram@claude-plugins-official"]' "$installed" >/dev/null 2>&1 &&
      [[ ! -d "$plugin_base" ]]; then
      log_info "Removing stale installed_plugins entry (no cache present)"
      local tmp_json
      tmp_json=$(mktemp)
      jq 'del(.plugins["telegram@claude-plugins-official"])' "$installed" >"$tmp_json"
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
        ' "$settings" >"$tmp_json"
    mv "$tmp_json" "$settings"
    log_ok "Plugin enabled + 9 supercharged tools merged into permissions.allow"
  fi

  local plugin_version
  plugin_version=$(find "$plugin_base" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort -V | tail -1)
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
  local repo="$CC_SUPERCHARGED_REPO"
  local plugin_base="$HOME/.claude/plugins/cache/claude-plugins-official/telegram"
  local plugin_version
  plugin_version=$(find "$plugin_base" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort -V | tail -1)
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
  [[ -f "$repo/supervisor.ts" ]] && cp "$repo/supervisor.ts" "$scripts_dir/telegram-supervisor.ts" &&
    log_ok "supervisor.ts -> $scripts_dir"
  [[ -f "$repo/scripts/claude-daemon-wrapper.exp" ]] &&
    cp "$repo/scripts/claude-daemon-wrapper.exp" "$scripts_dir/" &&
    log_ok "claude-daemon-wrapper.exp -> $scripts_dir"

  if [[ -d "$repo/skills" ]]; then
    mkdir -p "$plugin_dir/skills"
    cp -R "$repo/skills/." "$plugin_dir/skills/"
    log_ok "skills/ copied (additive)"
  fi

  # Run bun install in plugin dir to ensure deps current (supercharged may
  # add deps over time; safe even if package.json unchanged).
  log_info "Running bun install in plugin dir..."
  (cd "$plugin_dir" && bun install --no-summary 2>&1 | tail -3)
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
    existing=$(grep -E '^TELEGRAM_BOT_TOKEN=' "$env_file" 2>/dev/null | tail -1 |
      sed 's/^TELEGRAM_BOT_TOKEN=//' | tr -d '"' | tr -d "'")
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
  printf 'TELEGRAM_BOT_TOKEN=%s\n' "$token" >"$env_file"
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
  log_info "+ ~/.local/bin/supercharged-launcher.sh wrapper (exec's bun supervisor.ts)"
  log_info "Optional VPN-wait gate: open your VPN app ($CC_VPN_APPS), wait for anthropic reachability"
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

  local with_vpn=false
  if confirm "Add VPN-wait gate to launcher? (open your VPN app ($CC_VPN_APPS), wait for anthropic reachability)" "n"; then
    with_vpn=true
  fi

  mkdir -p "$(dirname "$launcher")"
  if $with_vpn; then
    cat >"$launcher" <<LAUNCHER
#!/bin/zsh
# Supercharged supervisor launcher with VPN-wait gate (generated by macrift).
# Opens the most-recently-used configured VPN app (assuming "Connect on launch"
# is set in the app), then waits for api.anthropic.com before exec'ing supervisor.

set -u
export PATH="\$HOME/.bun/bin:\$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\$PATH"

vpn_apps=($CC_VPN_APPS)
best=""; best_mtime=0
for app in "\${vpn_apps[@]}"; do
  m=\$(stat -f %m "\$HOME/Library/Application Support/\$app" 2>/dev/null || echo 0)
  (( m > best_mtime )) && { best_mtime=\$m; best=\$app; }
done
[ -n "\$best" ] && open -a "\$best" 2>/dev/null

for i in \$(seq 1 30); do
  curl -s --max-time 5 -o /dev/null https://api.anthropic.com && break
  sleep 2
done

exec "$bun_bin" "\$HOME/.claude/scripts/telegram-supervisor.ts"
LAUNCHER
  else
    cat >"$launcher" <<LAUNCHER
#!/bin/zsh
# Supercharged supervisor launcher (no VPN gate).

set -u
export PATH="\$HOME/.bun/bin:\$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\$PATH"

exec "$bun_bin" "\$HOME/.claude/scripts/telegram-supervisor.ts"
LAUNCHER
  fi
  chmod +x "$launcher"
  log_ok "Wrote $launcher ($($with_vpn && echo with || echo without) VPN gate)"

  mkdir -p "$(dirname "$plist")"
  cat >"$plist" <<PLIST
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

  _cc_ensure_local_bin_on_path
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

  _cc_install_supercharged_plugin_copy || return 1
  _cc_install_supercharged_apply_copy || return 1
  _cc_install_supercharged_dirs_copy || return 1
  _cc_install_supercharged_token_copy || return 1
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
  log_info "Preserves: repo ($CC_SUPERCHARGED_REPO),"
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
        "$settings" >"$tmp"
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
      jq 'del(.plugins["telegram@claude-plugins-official"])' "$installed" >"$tmp"
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

