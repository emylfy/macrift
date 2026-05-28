#!/usr/bin/env bash
# macrift — Claude Code toolkit catalog. Lists what macrift installed into
# ~/.claude (agents, commands, rules, hooks, env, statusline, MCP). Reads the
# live state, so it never goes stale. Standalone or via /macrift.
#
# Sibling to doctor.sh: doctor answers "is it healthy?", this answers "what do
# I have, and what does each piece do?".

set -uo pipefail
shopt -s nullglob

B=$'\033[1m'
D=$'\033[2m'
C=$'\033[36m'
N=$'\033[0m'

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
case "${SHELL##*/}" in
  fish) SHELL_RC="$HOME/.config/fish/config.fish" ;;
  bash) SHELL_RC="$HOME/.bashrc" ;;
  *) SHELL_RC="$HOME/.zshrc" ;;
esac

section() { printf '\n%b%s%b\n' "$B" "$*" "$N"; }
row() { printf '  %b%-13s%b %s\n' "$C" "$1" "$N" "$2"; }
name() { printf '  %b%s%b\n' "$C" "$1" "$N"; }

# First line of an md file's frontmatter `description:` (inline or `|` block).
desc_of() {
  awk '
    /^description:[[:space:]]*\|/ { blk = 1; next }
    blk == 1 { sub(/^[[:space:]]+/, ""); print; exit }
    /^description:/ { sub(/^description:[[:space:]]*/, ""); if (length) print; exit }
  ' "$1" | cut -c1-72
}

printf '%bmacrift — Claude Code toolkit%b %b(%s)%b\n' "$B" "$N" "$D" "$CLAUDE_DIR" "$N"

agents=("$CLAUDE_DIR"/agents/*.md)
if ((${#agents[@]})); then
  section "Agents"
  for f in "${agents[@]}"; do row "$(basename "$f" .md)" "$(desc_of "$f")"; done
fi

commands=("$CLAUDE_DIR"/commands/*.md)
if ((${#commands[@]})); then
  section "Commands"
  for f in "${commands[@]}"; do row "/$(basename "$f" .md)" "$(desc_of "$f")"; done
fi

rules=("$CLAUDE_DIR"/rules/*.md)
if ((${#rules[@]})); then
  section "Rules"
  for f in "${rules[@]}"; do name "$(basename "$f" .md)"; done
fi

hooks=("$CLAUDE_DIR"/hooks/*.sh)
if ((${#hooks[@]})); then
  section "Hooks"
  for f in "${hooks[@]}"; do name "$(basename "$f")"; done
fi

if grep -q '^# macrift:claude-code env' "$SHELL_RC" 2>/dev/null; then
  section "Env (${SHELL_RC/#$HOME/\~})"
  awk '/^# macrift:claude-code env/ { n++; next } n == 1 && /^(export|set -gx)/ { print "  " $0 }' "$SHELL_RC"
fi

if command -v jq >/dev/null 2>&1 && [[ -f "$CLAUDE_DIR/settings.json" ]]; then
  sl=$(jq -r '.statusLine.command // empty' "$CLAUDE_DIR/settings.json" 2>/dev/null)
  [[ -n "$sl" ]] && {
    section "Statusline"
    printf '  %s\n' "$sl"
  }
fi

if command -v claude >/dev/null 2>&1; then
  mcp=$(claude mcp list 2>/dev/null | sed 's/^/  /')
  [[ -n "$mcp" ]] && {
    section "MCP servers"
    printf '%s\n' "$mcp"
  }
fi

printf '\n%bTip:%b /doctor checks health · macrift → Claude Code → Setup to change\n' "$D" "$N"
