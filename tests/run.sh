#!/usr/bin/env bash
# macrift test suite — plain bash, no external deps (no bats/shfmt needed).
# Run: bash tests/run.sh
#
# Focus: lock the Claude Code component registry so the menu/wizard derived
# from it can never silently drift from the intended set (the casing bug that
# started this work lived in the old hand-synced parallel arrays).

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export MACRIFT_DIR="$ROOT"
: "${HOME:=/tmp}"

pass=0 fail=0
ok() {
  pass=$((pass + 1))
  printf '  ok   %s\n' "$1"
}
no() {
  fail=$((fail + 1))
  printf '  FAIL %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '         %s\n' "$2"
}
eq() { # name actual expected
  if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1" "expected [$3] got [$2]"; fi
}

# Function defs only — claude_code.sh has no top-level side effects.
# shellcheck disable=SC1091
source "$ROOT/customize/claude_code.sh"

rows="$(_cc_registry)"

printf '== registry integrity ==\n'
eq "13 component rows" "$(printf '%s\n' "$rows" | grep -c '|')" "13"

bad_fields=0
while IFS= read -r r; do
  [[ -z "$r" ]] && continue
  pipes="${r//[^|]/}"
  [[ ${#pipes} -eq 10 ]] || bad_fields=$((bad_fields + 1))
done <<<"$rows"
eq "every row has 11 fields" "$bad_fields" "0"

printf '== menu derivation (golden) ==\n'
# Golden values captured from the pre-registry _cc_custom_menu.
menu_keys="" menu_render="" bad_handler=0
prev=""
while IFS='|' read -r key section menu wiz mwait wdefault mlabel wlabel handler desc usecase; do
  [[ "$menu" == y ]] || continue
  [[ -n "$handler" ]] || bad_handler=$((bad_handler + 1))
  if [[ "$section" != "$prev" ]]; then
    menu_render+="## $section"$'\n'
    prev="$section"
  fi
  menu_render+="$mlabel"$'\n'
  menu_keys+="$key "
done <<<"$rows"
menu_keys="${menu_keys% }"

eq "menu keys + order" "$menu_keys" \
  "settings statusline agents commands rules hooks env claude_md ralias mcp"
eq "every menu row has a handler" "$bad_handler" "0"

read -r -d '' golden_menu_render <<'EOF'
## Core
Settings
Statusline
## AI extensions
Agents
Slash Commands
Rules
Hooks
## Shell integration
Environment (.zshrc env vars)
CLAUDE.md (rule imports)
'r' alias
## MCP servers
MCP Servers (context7, playwright)
EOF
eq "menu render (headers + labels)" "${menu_render%$'\n'}" "$golden_menu_render"

printf '== wizard derivation (golden) ==\n'
wiz_keys="" wiz_sections="" wiz_defaults=""
while IFS='|' read -r key section menu wiz mwait wdefault mlabel wlabel handler desc usecase; do
  [[ "$wiz" == y ]] || continue
  wiz_keys+="$key "
  wiz_sections+="$section|"
  wiz_defaults+="$wdefault"
done <<<"$rows"
wiz_keys="${wiz_keys% }"

eq "wizard keys + order" "$wiz_keys" \
  "settings statusline doctor agents commands rules hooks env claude_md ralias mcp_context7 mcp_playwright"
eq "wizard panel sections" "$wiz_sections" \
  "Core|Core|Core|AI extensions|AI extensions|AI extensions|AI extensions|Shell integration|Shell integration|Shell integration|MCP servers|MCP servers|"
eq "wizard defaults all yes" "$wiz_defaults" "yyyyyyyyyyyy"

printf '== _cc_wizard_label lookup ==\n'
eq "label: doctor" "$(_cc_wizard_label doctor)" "Doctor + /doctor command"
eq "label: mcp_context7" "$(_cc_wizard_label mcp_context7)" "MCP context7"
eq "label: settings" "$(_cc_wizard_label settings)" "Settings"

printf '== _cc_marker_balanced ==\n'
tmp="$(mktemp)"
printf '# M\nfoo\n# M\n' >"$tmp"
if _cc_marker_balanced "$tmp" "# M"; then ok "balanced pair → 0"; else no "balanced pair → 0"; fi
printf '# M\nfoo\n' >"$tmp"
if _cc_marker_balanced "$tmp" "# M"; then no "single marker → should be non-zero"; else ok "single marker → non-zero"; fi
rm -f "$tmp"

printf '== cross-shell resolver (_cc_target_rc / _cc_shell_kind) ==\n'
eq "zsh → .zshrc" "$(SHELL=/bin/zsh _cc_target_rc)" "$HOME/.zshrc"
eq "bash → .bashrc" "$(SHELL=/bin/bash _cc_target_rc)" "$HOME/.bashrc"
eq "fish → config.fish" "$(SHELL=/usr/local/bin/fish _cc_target_rc)" "$HOME/.config/fish/config.fish"
eq "unknown → zsh fallback" "$(SHELL=/bin/sh _cc_target_rc)" "$HOME/.zshrc"

printf '== export-line translation (_cc_export_line) ==\n'
eq "zsh keeps export" "$(_cc_export_line zsh 'export FOO=bar')" "export FOO=bar"
eq "bash keeps export" "$(_cc_export_line bash 'export FOO=bar')" "export FOO=bar"
eq "fish → set -gx" "$(_cc_export_line fish 'export FOO=bar')" "set -gx FOO bar"
eq "fish real var" "$(_cc_export_line fish 'export CLAUDE_CODE_SUBAGENT_MODEL=claude-sonnet-4-6')" \
  "set -gx CLAUDE_CODE_SUBAGENT_MODEL claude-sonnet-4-6"

printf '== _cc_effect_for (every wizard component has a system-effect line) ==\n'
missing_eff=0
while IFS='|' read -r key section menu wiz rest; do
  [[ "$wiz" == y ]] || continue
  [[ -n "$(_cc_effect_for "$key")" ]] || missing_eff=$((missing_eff + 1))
done < <(_cc_registry)
eq "all wizard keys have an effect" "$missing_eff" "0"
eq "effect: settings mentions merge+kept" \
  "$(_cc_effect_for settings | grep -c 'merged')" "1"

printf '== _cc_caveat_for ==\n'
eq "ralias caveat warns at default 'r'" "$(CC_RUN_ALIAS=r _cc_caveat_for ralias | grep -c shadows)" "1"
eq "ralias caveat silent when renamed" "$(CC_RUN_ALIAS=rr _cc_caveat_for ralias)" ""
eq "rules caveat present" "$([ -n "$(_cc_caveat_for rules)" ] && echo yes)" "yes"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
