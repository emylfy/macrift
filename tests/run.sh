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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
