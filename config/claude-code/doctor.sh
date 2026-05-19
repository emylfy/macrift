#!/usr/bin/env bash
# Claude Code health check.
# Verifies that the macrift Claude Code config is wired up and dependencies
# are present. Exit 0 if no FAIL items; exit 1 if any FAIL.

set -u

# Color output if stdout is a TTY.
if [[ -t 1 ]]; then
  G=$'\e[32m' # green
  Y=$'\e[33m' # yellow
  R=$'\e[31m' # red
  D=$'\e[2m'  # dim
  B=$'\e[1m'  # bold
  N=$'\e[0m'  # reset
else
  G='' Y='' R='' D='' B='' N=''
fi

ok_count=0
miss_count=0
fail_count=0

ok() {
  printf '%b[OK]%b   %s\n' "$G" "$N" "$*"
  ok_count=$((ok_count + 1))
}
miss() {
  printf '%b[MISS]%b %s\n' "$Y" "$N" "$*"
  miss_count=$((miss_count + 1))
}
fail() {
  printf '%b[FAIL]%b %s\n' "$R" "$N" "$*"
  fail_count=$((fail_count + 1))
}
note() { printf '%b%s%b\n' "$D" "$*" "$N"; }

section() { printf '\n%b%s%b\n' "$B" "$*" "$N"; }

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"

printf '%bClaude Code health check%b\n' "$B" "$N"
printf '%b%s%b\n' "$D" "$(date '+%Y-%m-%d %H:%M')" "$N"

# Required commands
section "Required tools"
for tool in jq claude; do
  if command -v "$tool" >/dev/null 2>&1; then
    ver=$("$tool" --version 2>/dev/null | head -1)
    ok "$tool $D($ver)$N"
  else
    fail "$tool not in PATH"
  fi
done

# Optional formatters
section "Formatters (optional — used by hooks/format.sh)"
declare -A fmt_purpose=(
  [prettier]=".ts/.js/.json/.yaml/.css/.html"
  [ruff]=".py"
  [shfmt]=".sh/.bash"
  [gofmt]=".go"
  [rustfmt]=".rs"
)
for tool in prettier ruff shfmt gofmt rustfmt; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool"
  else
    miss "$tool — ${fmt_purpose[$tool]} won't be auto-formatted"
  fi
done

# Hooks (invoked via `bash $path`, so +x bit is cosmetic — only check existence)
section "Hooks installed"
for hook in format.sh security-gate.sh session-start.sh; do
  p="$CLAUDE_DIR/hooks/$hook"
  if [[ -f "$p" ]]; then
    ok "$p"
  else
    fail "$p missing"
  fi
done

# Agents / commands files exist
section "Agents and commands"
agents_dir="$CLAUDE_DIR/agents"
commands_dir="$CLAUDE_DIR/commands"
[[ -d "$agents_dir" ]] && ok "agents dir ($(ls "$agents_dir" 2>/dev/null | grep -c '\.md$') .md files)" || fail "$agents_dir missing"
[[ -d "$commands_dir" ]] && ok "commands dir ($(ls "$commands_dir" 2>/dev/null | grep -c '\.md$') .md files)" || fail "$commands_dir missing"

# CLAUDE.md @-imports
section "CLAUDE.md rule imports"
claude_md="$CLAUDE_DIR/CLAUDE.md"
if [[ ! -f "$claude_md" ]]; then
  fail "$claude_md missing"
else
  total=0
  broken=0
  while IFS= read -r line; do
    [[ "$line" =~ ^@~/.claude/rules/(.+)\.md$ ]] || continue
    rule_name="${BASH_REMATCH[1]}"
    target="$CLAUDE_DIR/rules/$rule_name.md"
    total=$((total + 1))
    [[ -f "$target" ]] || {
      fail "@$rule_name.md → $target not found"
      broken=$((broken + 1))
    }
  done <"$claude_md"
  if ((broken == 0 && total > 0)); then
    ok "CLAUDE.md ($total imports, all resolve)"
  elif ((total == 0)); then
    miss "CLAUDE.md has no @-imports (rule files won't be loaded)"
  fi
fi

# settings.json
section "settings.json"
settings="$CLAUDE_DIR/settings.json"
if [[ ! -f "$settings" ]]; then
  fail "$settings missing"
elif ! jq empty "$settings" 2>/dev/null; then
  fail "$settings is not valid JSON"
else
  ok "settings.json valid"
  if jq -e '.statusLine.command' "$settings" >/dev/null 2>&1; then
    sl=$(jq -r '.statusLine.command' "$settings")
    ok "statusLine wired $D($sl)$N"
  else
    miss "no statusLine wired (default Claude bar)"
  fi
  hook_count=$(jq -r '.hooks // {} | keys[]' "$settings" 2>/dev/null | wc -l | tr -d ' ')
  if ((hook_count > 0)); then
    wired=$(jq -r '.hooks | keys | join(", ")' "$settings")
    ok "$hook_count hook event(s) wired $D($wired)$N"
  else
    miss "no hooks wired"
  fi
fi

# MCP servers
section "MCP servers"
if command -v claude >/dev/null 2>&1; then
  mcp_out=$(claude mcp list 2>&1)
  mcp_rc=$?
  if ((mcp_rc != 0)); then
    fail "claude mcp list returned $mcp_rc"
    note "$mcp_out"
  else
    # Parse lines of the form "name: command - status"
    connected=$(grep -c ' Connected' <<<"$mcp_out" 2>/dev/null || echo 0)
    failed=$(grep -cE ' (Failed|✗)' <<<"$mcp_out" 2>/dev/null || echo 0)
    connected=${connected//[^0-9]/}
    failed=${failed//[^0-9]/}
    connected=${connected:-0}
    failed=${failed:-0}
    names=$(awk -F': ' '/ - / {print $1}' <<<"$mcp_out" | tr '\n' ' ')
    if ((connected > 0)); then
      ok "$connected MCP server(s) connected $D($names)$N"
    fi
    if ((failed > 0)); then
      fail "$failed MCP server(s) failed to connect"
    fi
    if ((connected == 0 && failed == 0)); then
      note "no MCP servers configured"
    fi
  fi
else
  note "(claude CLI missing — skipping MCP check)"
fi

# /tmp writable
section "/tmp + workflow"
if touch /tmp/.cc-doctor-test 2>/dev/null && rm /tmp/.cc-doctor-test 2>/dev/null; then
  ok "/tmp writable"
else
  fail "/tmp not writable — workflow.md /tmp/cmd.sh pattern broken"
fi

if grep -q "alias r='bash /tmp/cmd.sh'" "$HOME/.zshrc" 2>/dev/null; then
  ok "'r' alias set in ~/.zshrc"
else
  miss "'r' alias missing — workflow.md tells Claude to suggest \`r\`, fallback is manual \`bash /tmp/cmd.sh\`"
fi

if grep -q '^# macrift:claude-code env' "$HOME/.zshrc" 2>/dev/null; then
  ok "env block in ~/.zshrc"
else
  miss "no env block in ~/.zshrc — subagent model / autocompact / concurrency not set"
fi

# Statusline (delegated to ccstatusline via bunx — see settings.json)
section "Statusline"
if command -v bun >/dev/null 2>&1 || command -v npx >/dev/null 2>&1; then
  ok "bunx/npx available — ccstatusline can run"
else
  fail "neither bun nor npx in PATH — ccstatusline cannot run"
fi
if [[ -f "$HOME/.config/ccstatusline/settings.json" ]]; then
  ok "ccstatusline config at ~/.config/ccstatusline/settings.json"
else
  miss "no ccstatusline config (first run will write defaults)"
fi

# Summary
printf '\n%b━━━━━━━━━━━━━━━━━━━━━%b\n' "$D" "$N"
total=$((ok_count + miss_count + fail_count))
printf '%bSummary:%b %d checks — %b%d ok%b, %b%d miss%b, %b%d fail%b\n' \
  "$B" "$N" "$total" "$G" "$ok_count" "$N" "$Y" "$miss_count" "$N" "$R" "$fail_count" "$N"

if ((fail_count > 0)); then
  printf '%bFAIL items need attention.%b\n' "$R" "$N"
  exit 1
elif ((miss_count > 0)); then
  printf '%bAll critical components healthy. MISS items are optional / informational.%b\n' "$Y" "$N"
  exit 0
else
  printf '%bAll checks passed.%b\n' "$G" "$N"
  exit 0
fi
