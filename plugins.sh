#!/usr/bin/env bash
# macrift plugin loader — discovery, manifest reading, compat checks.
#
# Plugin runtime state lives under $HOME/.macrift/plugins/, one subdirectory
# per installed plugin. Each plugin dir holds:
#   plugin.json   manifest (see schemas/plugin.schema.json)
#   menu.sh       entry point — defines the function named in menu.function
#   handlers/     install / uninstall scripts (sourced from menu.sh)
#   config/       static config files
#
# This file ships the LOAD-TIME side: enumerate installed plugins, parse
# manifests, check compat. The CLI commands (`macrift plugin add/list/...`)
# are layered on top in macrift.sh. See PLUGINS.md for the full author
# contract and SECURITY.md for the trust model.

MACRIFT_PLUGINS_DIR="${MACRIFT_PLUGINS_DIR:-$HOME/.macrift/plugins}"

# Public-API version. Bump only on breaking changes to the helpers documented
# in PLUGINS.md (show_menu / log_* / audit_default / copy_config / journal).
# Plugins declare the API version they target in compat.macrift_api; a
# mismatch is a load-time error, not a runtime crash. Exported so plugin
# code can branch on it if a backward-compatible feature is added mid-major.
export MACRIFT_API_VERSION=1

# Everything below shells out to jq for manifest and lockfile parsing — guard
# once at the entry points (_plugin_load_all / _plugin_cli) so a missing jq is
# one clear message, not dozens of mid-flow errors.
_plugin_require_jq() {
    command -v jq >/dev/null 2>&1 && return 0
    log_warn "plugins require jq — brew install jq"
    return 1
}

# Print one plugin directory per line for every entry in $MACRIFT_PLUGINS_DIR
# that has a plugin.json. Silent (no error) on a fresh install where the dir
# doesn't exist yet, and on subdirs without a manifest (treated as not a plugin).
_plugin_discover() {
    [[ -d "$MACRIFT_PLUGINS_DIR" ]] || return 0
    local d
    shopt -s nullglob
    for d in "$MACRIFT_PLUGINS_DIR"/*/; do
        [[ -f "${d}plugin.json" ]] && printf '%s\n' "${d%/}"
    done
    shopt -u nullglob
}

# Read one field from a plugin's manifest via jq.
#   _plugin_field <plugin-dir> <jq-path>
# Returns 1 on missing manifest, invalid JSON, or missing field (jq -r prints
# "null" for missing fields, so we treat that as missing too).
_plugin_field() {
    local dir="$1" path="$2" v
    [[ -f "$dir/plugin.json" ]] || return 1
    v=$(jq -r "$path // empty" "$dir/plugin.json" 2>/dev/null) || return 1
    [[ -n "$v" ]] || return 1
    printf '%s' "$v"
}

# Compat check for one plugin directory. Returns 0 if macrift can safely load
# the plugin, 1 otherwise. On failure, logs a specific warning so the user
# sees WHY a plugin disappeared from the menu.
_plugin_compat_ok() {
    local dir="$1"
    local name api macrift_min macos_min

    # Required identity field (used in subsequent log_warns)
    name=$(_plugin_field "$dir" .name) || {
        log_warn "Plugin in $(basename "$dir"): missing or invalid .name"
        return 1
    }
    # .name is used as a filesystem path component (install dir, lockfile key),
    # so constrain it to the schema's kebab pattern — a manifest with
    # .name="../../x" must not escape $MACRIFT_PLUGINS_DIR on install.
    if ! [[ "$name" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] || (( ${#name} > 64 )); then
        log_warn "Plugin in $(basename "$dir"): .name '$name' is not a valid kebab-case identifier (a-z, 0-9, -; 2–64 chars)"
        return 1
    fi

    # macrift API version — integer, exact match within a major
    api=$(_plugin_field "$dir" .compat.macrift_api) || {
        log_warn "Plugin $name: missing compat.macrift_api"
        return 1
    }
    if ! [[ "$api" =~ ^[0-9]+$ ]]; then
        log_warn "Plugin $name: compat.macrift_api must be an integer (got '$api')"
        return 1
    fi
    if (( api != MACRIFT_API_VERSION )); then
        if (( api > MACRIFT_API_VERSION )); then
            log_warn "Plugin $name needs macrift API v$api — this build is v$MACRIFT_API_VERSION (upgrade macrift)"
        else
            log_warn "Plugin $name targets older API v$api — this build is v$MACRIFT_API_VERSION (ask author to update)"
        fi
        return 1
    fi

    # macrift_min — calver (YY.MM[.N])
    macrift_min=$(_plugin_field "$dir" .compat.macrift_min) || {
        log_warn "Plugin $name: missing compat.macrift_min"
        return 1
    }
    if _macrift_version_gt "$macrift_min" "$MACRIFT_VERSION"; then
        log_warn "Plugin $name needs macrift $macrift_min — this build is $MACRIFT_VERSION"
        return 1
    fi

    # macos_min — optional
    if macos_min=$(_plugin_field "$dir" .compat.macos_min 2>/dev/null); then
        if _macrift_version_gt "$macos_min" "$MACRIFT_OS_VER"; then
            log_warn "Plugin $name needs macOS $macos_min — you are on $MACRIFT_OS_VER"
            return 1
        fi
    fi

    return 0
}

# Plugin registry — populated by _plugin_load_all at startup. Each entry is
# tab-separated:  target \t entry \t function
# `target` carries a one-char discriminator prefix: `p:<slug>` injects INTO a
# built-in submenu (tweaks/apps/customize/security/cleanup); `s:<name>` is a
# top-level section. (A single non-empty field, rather than separate parent/
# section columns, avoids `read` collapsing an empty tab-delimited field — tab
# is IFS-whitespace.) Read by macrift.sh's main_menu (s:) and the submenu
# functions via _plugin_attach_builtin (p:).
MACRIFT_PLUGIN_REGISTRY=()

# Discover, compat-check, source, and register every plugin under
# $MACRIFT_PLUGINS_DIR. Idempotent: clears the registry first. Skips plugins
# whose menu.sh fails to source or doesn't define the declared function.
# Plugin failures emit log_warn but never abort the startup of macrift itself.
_plugin_load_all() {
    MACRIFT_PLUGIN_REGISTRY=()
    _plugin_require_jq || return 0
    local dir name parent section entry func target
    while IFS= read -r dir; do
        [[ -z "$dir" ]] && continue
        _plugin_compat_ok "$dir" || continue

        # name is already validated by _plugin_compat_ok; safe to read.
        name=$(_plugin_field "$dir" .name)

        # menu.parent (inject into a built-in submenu) and menu.section (new
        # top-level grouping) are optional but mutually exclusive — exactly one.
        parent=$(_plugin_field "$dir" .menu.parent || true)
        section=$(_plugin_field "$dir" .menu.section || true)
        if [[ -n "$parent" && -n "$section" ]]; then
            log_warn "Plugin $name: menu.parent and menu.section are mutually exclusive — skipping"
            continue
        fi
        if [[ -n "$parent" ]]; then
            case "$parent" in
                tweaks|apps|customize|security|cleanup) ;;
                *) log_warn "Plugin $name: menu.parent '$parent' is not a built-in submenu — skipping"; continue ;;
            esac
        elif [[ -z "$section" ]]; then
            log_warn "Plugin $name: needs menu.parent or menu.section — skipping"
            continue
        fi
        entry=$(_plugin_field "$dir" .menu.entry) || {
            log_warn "Plugin $name: missing menu.entry — skipping"
            continue
        }
        func=$(_plugin_field "$dir" .menu.function) || {
            log_warn "Plugin $name: missing menu.function — skipping"
            continue
        }

        # MACRIFT_PLUGIN_DIR is the plugin's own root, exposed only while its
        # menu.sh is being sourced. Menu functions run later (on selection), when
        # this loop var would be stale — so a plugin that ships config/handlers
        # must capture it at top level (e.g. `_FOO_DIR="$MACRIFT_PLUGIN_DIR"`).
        export MACRIFT_PLUGIN_DIR="$dir"

        # `if !` suspends set -e inside the source so a broken plugin can't
        # take macrift down; the function-defined check below catches partial
        # sources (syntax error mid-file leaves the function undefined). We
        # log_warn ourselves on failure, so silence the bash-level error too.
        # shellcheck source=/dev/null
        if ! source "$dir/menu.sh" 2>/dev/null; then
            log_warn "Plugin $name: failed to source menu.sh — skipping (run 'bash -n $dir/menu.sh' to diagnose)"
            continue
        fi
        if ! declare -F "$func" >/dev/null 2>&1; then
            log_warn "Plugin $name: menu.sh did not define '$func' — skipping"
            continue
        fi

        if [[ -n "$parent" ]]; then target="p:$parent"; else target="s:$section"; fi
        MACRIFT_PLUGIN_REGISTRY+=("$target"$'\t'"$entry"$'\t'"$func")
    done < <(_plugin_discover)
    # Don't leak the last-loaded plugin's dir into the rest of the program.
    unset MACRIFT_PLUGIN_DIR
}

# Count selectable (non-`---`, non-`## `) entries in a menu items array (nameref).
# Used by built-in submenus to know how many of their own rows precede any
# injected plugin entries, so the plugin dispatch index is correct.
_menu_selectable_count() {
    local -n _arr="$1"
    local n=0 it
    for it in "${_arr[@]}"; do
        [[ "$it" == "---" || "$it" == "## "* ]] && continue
        n=$((n + 1))
    done
    printf '%s' "$n"
}

# Append plugin entries targeting built-in submenu <slug> to an items array
# (nameref $2), recording their handler functions in a parallel funcs array
# (nameref $3). Prepends one `---` divider when at least one entry is added.
# No-op (funcs left empty) when no plugin targets <slug>.
_plugin_attach_builtin() {
    local slug="$1"
    local -n _items="$2"
    local -n _funcs="$3"
    _funcs=()
    local rec target entry func added=0
    for rec in "${MACRIFT_PLUGIN_REGISTRY[@]}"; do
        IFS=$'\t' read -r target entry func <<<"$rec"
        [[ "$target" == "p:$slug" ]] || continue
        (( added == 0 )) && _items+=("---")
        _items+=("$entry")
        _funcs+=("$func")
        added=1
    done
}

# Reproducibility lockfile — records the exact source / ref / commit / install
# time for every plugin so `plugin restore` (future) can rehydrate on another
# machine. Lives at $HOME/.macrift/plugins.lock.json.
MACRIFT_PLUGINS_LOCK="${MACRIFT_PLUGINS_LOCK:-$HOME/.macrift/plugins.lock.json}"

_plugin_lock_init() {
    [[ -f "$MACRIFT_PLUGINS_LOCK" ]] && return 0
    mkdir -p "$(dirname "$MACRIFT_PLUGINS_LOCK")"
    printf '{ "version": 1, "plugins": {} }\n' >"$MACRIFT_PLUGINS_LOCK"
}

_plugin_lock_add() {
    local name="$1" version="$2" src="$3" ref="$4" install_dir="$5"
    _plugin_lock_init
    local commit=""
    if [[ -d "$install_dir/.git" ]]; then
        commit=$(git -C "$install_dir" rev-parse HEAD 2>/dev/null || true)
    fi
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local merged
    merged=$(jq --arg n "$name" --arg v "$version" --arg s "$src" --arg r "$ref" \
                --arg c "$commit" --arg t "$now" '
        .plugins[$n] = {
            version: $v,
            source: $s,
            ref:    (if $r == "" then null else $r end),
            commit: (if $c == "" then null else $c end),
            installed_at: $t
        }
    ' "$MACRIFT_PLUGINS_LOCK" 2>/dev/null) || {
        log_warn "could not update $MACRIFT_PLUGINS_LOCK (jq error)"
        return 0
    }
    printf '%s\n' "$merged" >"$MACRIFT_PLUGINS_LOCK"
}

_plugin_lock_remove() {
    local name="$1"
    [[ -f "$MACRIFT_PLUGINS_LOCK" ]] || return 0
    local merged
    merged=$(jq --arg n "$name" 'del(.plugins[$n])' "$MACRIFT_PLUGINS_LOCK" 2>/dev/null) || return 0
    printf '%s\n' "$merged" >"$MACRIFT_PLUGINS_LOCK"
}

# Normalize a user-provided source string to a git-clonable URL/path.
# Supported forms:
#   github.com/user/repo   → https://github.com/user/repo.git
#   https://... / http://...   → as-is
#   git@host:...             → as-is (SSH)
#   ssh://... / file://...     → as-is
#   /abs/path  or  ./relative  → as-is (local clone)
_plugin_normalize_source() {
    local src="$1"
    case "$src" in
        file://*|https://*|http://*|ssh://*|git@*) printf '%s' "$src" ;;
        github.com/*)       printf 'https://%s' "$src" ;;
        /*|./*|../*)        printf '%s' "$src" ;;
        *)
            log_err "Unrecognized source: $src"
            log_hint "expected one of: github.com/user/repo, https://..., file://..., /local/path"
            return 1
            ;;
    esac
}

# Validate a CLI-supplied plugin name before it becomes a path component under
# $MACRIFT_PLUGINS_DIR — same kebab constraint the manifest schema enforces, so
# 'plugin remove ../../x' can't escape the plugins dir.
_plugin_name_ok() {
    [[ "$1" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] && (( ${#1} <= 64 ))
}

# `macrift plugin add <source>[@<ref>]` — clone, validate, prompt, install.
_plugin_cli_add() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: macrift plugin add <source>[@<ref>]"
        log_hint "examples: 'github.com/emylfy/claudemac', 'github.com/emylfy/claudemac@v1.0.0', 'file:///abs/path'"
        return 1
    fi

    # Split optional @<ref>. To avoid catching the @ inside SSH URLs
    # (git@host:...), only treat @ as a separator when it appears AFTER any path
    # separator, i.e. there is a / between the last @ and EOL.
    local raw="$1" ref=""
    if [[ "$raw" == *@* && "${raw##*@}" != *"/"* && "${raw%@*}" == */* ]]; then
        ref="${raw##*@}"
        raw="${raw%@*}"
    fi

    local src
    src=$(_plugin_normalize_source "$raw") || return 1

    local tmp
    tmp=$(mktemp -d) || { log_err "mktemp failed"; return 1; }

    log_info "Cloning $src${ref:+ @ $ref}..."
    local clone_status=0 clone_err
    if [[ -n "$ref" ]]; then
        clone_err=$(git clone -q --depth=1 --branch "$ref" "$src" "$tmp/clone" 2>&1) || clone_status=1
        if (( clone_status != 0 )); then
            # --branch only resolves tags/branches; a commit SHA needs a full
            # clone + checkout.
            rm -rf "$tmp/clone"
            clone_status=0
            clone_err=$({ git clone -q "$src" "$tmp/clone" && git -C "$tmp/clone" checkout -q "$ref"; } 2>&1) || clone_status=1
        fi
    else
        clone_err=$(git clone -q --depth=1 "$src" "$tmp/clone" 2>&1) || clone_status=1
    fi
    if [[ $clone_status -ne 0 || ! -d "$tmp/clone" ]]; then
        log_err "git clone failed"
        [[ -n "$clone_err" ]] && printf '%s\n' "$clone_err" | tail -5 | sed 's/^/    /'
        rm -rf "$tmp"
        return 1
    fi

    local clone_dir="$tmp/clone"

    if [[ ! -f "$clone_dir/plugin.json" ]]; then
        log_err "No plugin.json at the source — not a macrift plugin"
        log_hint "see PLUGINS.md for the expected layout"
        rm -rf "$tmp"
        return 1
    fi
    if ! jq . "$clone_dir/plugin.json" >/dev/null 2>&1; then
        log_err "plugin.json is not valid JSON"
        rm -rf "$tmp"
        return 1
    fi

    # Schema mismatches are surfaced but don't block install — a working plugin
    # with a cosmetic manifest miss shouldn't be unusable. `plugin lint` is strict.
    local schema_issues
    schema_issues=$(_plugin_schema_check "$clone_dir") || true
    if [[ -n "$schema_issues" ]]; then
        log_warn "plugin.json doesn't fully match the schema (installing anyway — run 'macrift plugin lint $clone_dir'):"
        printf '%s\n' "$schema_issues" | sed 's|^|    |'
    fi

    local name version desc
    name=$(_plugin_field "$clone_dir" .name) || {
        log_err "plugin.json: missing or invalid .name"
        rm -rf "$tmp"
        return 1
    }
    version=$(_plugin_field "$clone_dir" .version 2>/dev/null) || version="?"
    desc=$(_plugin_field "$clone_dir" .description 2>/dev/null) || desc=""

    if ! _plugin_compat_ok "$clone_dir"; then
        log_err "Plugin $name is incompatible — see warnings above; not installing"
        rm -rf "$tmp"
        return 1
    fi

    # Collision check + optional overwrite
    mkdir -p "$MACRIFT_PLUGINS_DIR"
    local target="$MACRIFT_PLUGINS_DIR/$name" backup=""
    if [[ -e "$target" ]]; then
        log_warn "Plugin $name is already installed at $target"
        if ! confirm "Overwrite existing installation?" "n"; then
            log_skip "kept existing $name"
            rm -rf "$tmp"
            return 0
        fi
        local ts
        ts=$(date +%s)
        backup="$target.bak.$ts"
        mv "$target" "$backup"
    fi

    # Pre-install summary
    printf '\n'
    log_info "About to install:"
    printf '    Name:    %s\n' "$name"
    printf '    Version: %s\n' "$version"
    printf '    Source:  %s\n' "$src"
    [[ -n "$ref" ]] && printf '    Ref:     %s\n' "$ref"
    printf '    Target:  %s\n' "$target"
    [[ -n "$desc" ]] && printf '    Desc:    %s\n' "$desc"
    printf '\n'

    local m_entry m_parent m_section
    if m_entry=$(_plugin_field "$clone_dir" .menu.entry 2>/dev/null); then
        m_parent=$(_plugin_field "$clone_dir" .menu.parent 2>/dev/null) || m_parent=""
        m_section=$(_plugin_field "$clone_dir" .menu.section 2>/dev/null) || m_section=""
        log_info "Menu entries:"
        if [[ -n "$m_parent" ]]; then
            printf '    %s  (in the built-in %s submenu)\n' "$m_entry" "$m_parent"
        elif [[ -n "$m_section" ]]; then
            printf '    %s  (new section: %s)\n' "$m_entry" "$m_section"
        else
            printf '    %s\n' "$m_entry"
        fi
        printf '\n'
    fi

    if [[ -f "$clone_dir/README.md" ]]; then
        log_info "README preview:"
        printf '    ────────\n'
        # Wrap long paragraph lines at word boundaries, then cap the row count
        # so a README with 600-char lines can't flood the screen.
        fold -s -w 76 "$clone_dir/README.md" | head -n 12 | sed 's/^/    /'
        printf '    ────────\n\n'
    fi

    if [[ -d "$clone_dir/.git" ]]; then
        log_info "Recent commits:"
        git -C "$clone_dir" log --oneline -10 2>/dev/null | sed 's/^/    /'
        printf '\n'
    fi

    if ! confirm "Install $name?" "y"; then
        log_skip "cancelled"
        if [[ -n "$backup" ]]; then
            mv "$backup" "$target"
            log_info "Restored previous $name"
        fi
        rm -rf "$tmp"
        return 0
    fi

    if ! mv "$clone_dir" "$target"; then
        log_err "Failed to move plugin into $target"
        if [[ -n "$backup" ]]; then
            mv "$backup" "$target"
            log_info "Restored previous $name"
        fi
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$tmp"
    [[ -n "$backup" ]] && rm -rf "$backup"

    _plugin_lock_add "$name" "$version" "$src" "$ref" "$target"

    printf '\n'
    log_ok "Installed $name $version → $target"
    # In the TUI the registry is refreshed on exit (see plugins_menu), so the
    # restart hint only applies to the bare `macrift plugin add` CLI path.
    [[ "${MACRIFT_IN_TUI:-}" == 1 ]] || log_hint "restart macrift to see '$name' in the main menu"
}

# `macrift plugin remove <name>` — delete the plugin dir and update the
# lockfile. State changes the plugin made (defaults / launchd / rc-file
# markers) need `macrift undo` separately — full per-plugin journal-undo is
# future work (the journal currently tags by session, not plugin).
_plugin_cli_remove() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: macrift plugin remove <name>"
        return 1
    fi
    local name="$1"
    if ! _plugin_name_ok "$name"; then
        log_err "Invalid plugin name: $name"
        return 1
    fi
    local target="$MACRIFT_PLUGINS_DIR/$name"

    if [[ ! -d "$target" ]]; then
        log_err "Plugin $name is not installed"
        log_hint "list installed plugins with: macrift plugin list"
        return 1
    fi

    local version
    version=$(_plugin_field "$target" .version 2>/dev/null) || version="?"

    printf '\n'
    log_warn "About to remove plugin $name ($version) from $target"
    log_hint "this deletes the plugin's files; to revert any state it changed (defaults, rc-file, launchd) run 'macrift undo' afterward"
    if ! confirm "Continue?" "n"; then
        log_skip "kept $name"
        return 0
    fi

    rm -rf "$target"
    _plugin_lock_remove "$name"

    log_ok "Removed $name"
    [[ "${MACRIFT_IN_TUI:-}" == 1 ]] || log_hint "restart macrift to drop the entry from the main menu"
}

# `macrift plugin update [<name>]` — git pull each git-checkout plugin (or
# just the named one). Re-validates compat after pull and bumps the lockfile.
_plugin_cli_update() {
    local target_name="${1:-}"
    local updated=0 skipped=0 failed=0
    if [[ -n "$target_name" ]]; then
        if ! _plugin_name_ok "$target_name"; then
            log_err "Invalid plugin name: $target_name"
            return 1
        fi
        local target="$MACRIFT_PLUGINS_DIR/$target_name"
        [[ -d "$target" ]] || { log_err "Plugin $target_name is not installed"; return 1; }
        if _plugin_update_one "$target"; then updated=$((updated + 1)); else
            local rc=$?; [[ $rc -eq 2 ]] && skipped=$((skipped + 1)) || failed=$((failed + 1))
        fi
    else
        local d
        while IFS= read -r d; do
            [[ -z "$d" ]] && continue
            if _plugin_update_one "$d"; then updated=$((updated + 1)); else
                local rc=$?; [[ $rc -eq 2 ]] && skipped=$((skipped + 1)) || failed=$((failed + 1))
            fi
        done < <(_plugin_discover)
    fi
    printf '\n'
    log_info "Updated: $updated  Skipped: $skipped  Failed: $failed"
}

# Return codes: 0 updated, 2 skipped (no-op / not-a-git-checkout / already current), 1 failed.
_plugin_update_one() {
    local dir="$1" name before after
    name=$(_plugin_field "$dir" .name) || { log_warn "$(basename "$dir"): missing .name"; return 1; }
    if [[ ! -d "$dir/.git" ]]; then
        log_skip "$name: not a git checkout (likely symlinked), skipping"
        return 2
    fi
    # Tag/SHA-pinned installs sit on a detached HEAD — `git pull` would error.
    if ! git -C "$dir" symbolic-ref -q HEAD >/dev/null 2>&1; then
        local pin
        pin=$(jq -r --arg n "$name" '.plugins[$n].ref // empty' "$MACRIFT_PLUGINS_LOCK" 2>/dev/null || true)
        [[ -z "$pin" || "$pin" == "null" ]] && pin=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo "?")
        log_skip "$name: pinned at $pin — re-add with a newer ref to update"
        return 2
    fi
    log_info "Updating $name..."
    before=$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)
    if ! git -C "$dir" pull --ff-only 2>&1 | tail -3; then
        log_warn "$name: git pull failed"
        return 1
    fi
    after=$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)
    if [[ "$before" == "$after" ]]; then
        log_skip "$name: already at latest"
        return 2
    fi
    if ! _plugin_compat_ok "$dir"; then
        log_warn "$name: post-update compat check failed — plugin won't load until fixed"
        return 1
    fi
    local version src ref
    version=$(_plugin_field "$dir" .version 2>/dev/null) || version="?"
    src=$(jq -r --arg n "$name" '.plugins[$n].source // empty' "$MACRIFT_PLUGINS_LOCK" 2>/dev/null || true)
    ref=$(jq -r --arg n "$name" '.plugins[$n].ref // empty'    "$MACRIFT_PLUGINS_LOCK" 2>/dev/null || true)
    [[ "$ref" == "null" ]] && ref=""
    _plugin_lock_add "$name" "$version" "$src" "$ref" "$dir"
    log_ok "$name updated to $version"
}

# `macrift plugin info <name>` — manifest fields + compat status + lint
# findings + lockfile entry + README pointer. Read-only.
_plugin_cli_info() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: macrift plugin info <name>"
        return 1
    fi
    local name="$1"
    if ! _plugin_name_ok "$name"; then
        log_err "Invalid plugin name: $name"
        return 1
    fi
    local dir="$MACRIFT_PLUGINS_DIR/$name"
    [[ -d "$dir" ]] || { log_err "Plugin $name is not installed"; return 1; }

    local version desc author license homepage
    version=$(_plugin_field "$dir" .version 2>/dev/null)     || version="?"
    desc=$(_plugin_field "$dir" .description 2>/dev/null)    || desc=""
    author=$(_plugin_field "$dir" .author 2>/dev/null)       || author=""
    license=$(_plugin_field "$dir" .license 2>/dev/null)     || license=""
    homepage=$(_plugin_field "$dir" .homepage 2>/dev/null)   || homepage=""

    printf '\n  %s %s\n' "$name" "$version"
    [[ -n "$desc" ]] && printf '  %s\n' "$desc"
    printf '\n'
    [[ -n "$author"   ]] && printf '  Author:    %s\n' "$author"
    [[ -n "$license"  ]] && printf '  License:   %s\n' "$license"
    [[ -n "$homepage" ]] && printf '  Homepage:  %s\n' "$homepage"
    printf '  Path:      %s\n' "$dir"

    local compat_msg
    if compat_msg=$(_plugin_compat_ok "$dir" 2>&1); then
        printf '  Status:    ok\n'
    else
        printf '  Status:    incompatible\n'
        [[ -n "$compat_msg" ]] && printf '%s\n' "$compat_msg" | sed 's/^/    /'
    fi

    local lint_out
    if lint_out=$(_plugin_cli_lint "$name" 2>&1); then
        printf '  Lint:      clean\n'
    else
        printf '  Lint:\n'
        printf '%s\n' "$lint_out" | sed '/^[[:space:]]*$/d; s/^/    /'
    fi

    if [[ -f "$MACRIFT_PLUGINS_LOCK" ]]; then
        local src ref commit installed
        src=$(jq -r --arg n "$name" '.plugins[$n].source // empty'       "$MACRIFT_PLUGINS_LOCK" 2>/dev/null || true)
        ref=$(jq -r --arg n "$name" '.plugins[$n].ref // empty'          "$MACRIFT_PLUGINS_LOCK" 2>/dev/null || true)
        commit=$(jq -r --arg n "$name" '.plugins[$n].commit // empty'    "$MACRIFT_PLUGINS_LOCK" 2>/dev/null || true)
        installed=$(jq -r --arg n "$name" '.plugins[$n].installed_at // empty' "$MACRIFT_PLUGINS_LOCK" 2>/dev/null || true)
        [[ -n "$src"       && "$src"       != "null" ]] && printf '  Source:    %s\n' "$src"
        [[ -n "$ref"       && "$ref"       != "null" ]] && printf '  Ref:       %s\n' "$ref"
        [[ -n "$commit"    && "$commit"    != "null" ]] && printf '  Commit:    %s\n' "${commit:0:12}"
        [[ -n "$installed" && "$installed" != "null" ]] && printf '  Installed: %s\n' "$installed"
    fi

    [[ -f "$dir/README.md" ]] && printf '\n  README:    %s\n' "$dir/README.md"
    printf '\n'
}

# `macrift plugin lint <path-or-name>` — static checks against the
# do-not-do rules documented in PLUGINS.md. Exit 0 if clean, 1 if findings.
# Validate plugin.json against schemas/plugin.schema.json (the source of truth).
# Prints one issue per line to stdout, returns non-zero if any. Single jq pass,
# no extra deps. Used by `plugin lint` (fatal) and `plugin add` (warning).
# Keep the enums/key lists below in sync with schemas/plugin.schema.json.
_plugin_schema_check() {
    local dir="$1" manifest="$1/plugin.json"
    [[ -f "$manifest" ]] || { echo "no plugin.json in $dir"; return 1; }
    if ! jq . "$manifest" >/dev/null 2>&1; then
        echo "plugin.json is not valid JSON"
        return 1
    fi
    local issues
    issues=$(jq -r '
        [
          # top level: required + unknown fields
          ((["name","version","description","compat","menu"] - keys_unsorted) | map("missing required field: \(.)") | .[]),
          ((keys_unsorted - ["$schema","name","version","description","author","license","homepage","compat","menu"]) | map("unknown field: \(.)") | .[]),

          # name
          (if (.name != null) and ((.name|test("^[a-z][a-z0-9-]*[a-z0-9]$"))|not) then "name: not kebab-case (a-z, 0-9, -)" else empty end),
          (if (.name != null) and ((.name|length) < 2 or (.name|length) > 64) then "name: must be 2–64 chars" else empty end),

          # version
          (if (.version != null) and ((.version|test("^[0-9]+\\.[0-9]+\\.[0-9]+(-[A-Za-z0-9.-]+)?$"))|not) then "version: not semver (MAJOR.MINOR.PATCH)" else empty end),

          # description
          (if (.description != null) and ((.description|length) < 1 or (.description|length) > 200) then "description: must be 1–200 chars" else empty end),

          # compat
          (if (.compat|type) == "object"
           then ((["macrift_min","macrift_api"] - (.compat|keys_unsorted)) | map("missing required field: compat.\(.)") | .[]),
                (((.compat|keys_unsorted) - ["macrift_min","macrift_api","macos_min"]) | map("unknown field: compat.\(.)") | .[])
           elif .compat != null then "compat: must be an object" else empty end),
          (if (.compat.macrift_min != null) and ((.compat.macrift_min|test("^[0-9]{2}\\.[0-9]{2}(\\.[0-9]+)?$"))|not) then "compat.macrift_min: not calver (YY.MM[.N])" else empty end),
          (if (.compat.macrift_api != null) and ((.compat.macrift_api|type) != "number" or (.compat.macrift_api < 1) or ((.compat.macrift_api|floor) != .compat.macrift_api)) then "compat.macrift_api: must be an integer ≥ 1" else empty end),
          (if (.compat.macos_min != null) and ((.compat.macos_min|test("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$"))|not) then "compat.macos_min: not a version (e.g. 14.0)" else empty end),

          # menu
          (if (.menu|type) == "object"
           then ((["entry","function"] - (.menu|keys_unsorted)) | map("missing required field: menu.\(.)") | .[]),
                (((.menu|keys_unsorted) - ["section","parent","entry","function"]) | map("unknown field: menu.\(.)") | .[])
           elif .menu != null then "menu: must be an object" else empty end),
          (if (.menu|type) == "object" and (.menu|has("section")) and (.menu|has("parent")) then "menu: section and parent are mutually exclusive" else empty end),
          (if (.menu|type) == "object" and (((.menu|has("section")) or (.menu|has("parent")))|not) then "menu: needs exactly one of section or parent" else empty end),
          (if (.menu.parent != null) and ((.menu.parent | IN("tweaks","apps","customize","security","cleanup")) | not) then "menu.parent: not a built-in submenu (tweaks|apps|customize|security|cleanup)" else empty end),
          (if (.menu.entry != null) and ((.menu.entry|length) < 1) then "menu.entry: must be non-empty" else empty end),
          (if (.menu.function != null) and ((.menu.function|test("^[a-zA-Z_][a-zA-Z0-9_]*$"))|not) then "menu.function: not a valid bash identifier" else empty end)
        ] | .[]
    ' "$manifest" 2>/dev/null)
    [[ -z "$issues" ]] && return 0
    printf '%s\n' "$issues"
    return 1
}

_plugin_cli_lint() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: macrift plugin lint <path-or-name>"
        return 1
    fi
    local target="$1"
    # Accept path-to-plugin, path-to-plugin.json, or installed-plugin name
    if [[ -d "$target" && -f "$target/plugin.json" ]]; then
        :
    elif [[ -f "$target" && "${target##*/}" == "plugin.json" ]]; then
        target="$(dirname "$target")"
    elif _plugin_name_ok "$target" && [[ -d "$MACRIFT_PLUGINS_DIR/$target" ]]; then
        target="$MACRIFT_PLUGINS_DIR/$target"
    else
        log_err "Could not locate plugin at: $1"
        return 1
    fi

    local issues=0

    if [[ ! -f "$target/plugin.json" ]]; then
        log_err "No plugin.json in $target"
        return 1
    fi
    if ! jq . "$target/plugin.json" >/dev/null 2>&1; then
        log_err "plugin.json is not valid JSON"
        issues=$((issues + 1))
    else
        # Manifest schema (mirrors schemas/plugin.schema.json)
        local schema_issues
        schema_issues=$(_plugin_schema_check "$target") || true
        if [[ -n "$schema_issues" ]]; then
            log_warn "plugin.json does not match the schema:"
            printf '%s\n' "$schema_issues" | sed 's|^|    |'
            issues=$((issues + $(printf '%s\n' "$schema_issues" | grep -c .)))
        fi
    fi
    if [[ ! -f "$target/menu.sh" ]]; then
        log_warn "menu.sh missing — plugin won't expose any menu entry"
        issues=$((issues + 1))
    fi

    local hits
    # Hits are matched anywhere in a line (a guarded `if ! launchctl ...` is
    # still a finding); comment-only lines are excluded by the file:line:# filter.
    # 1. Raw `defaults write` outside audit_default
    hits=$(grep -rnE 'defaults[[:space:]]+write' "$target" --include='*.sh' 2>/dev/null | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' | grep -v 'audit_default' || true)
    if [[ -n "$hits" ]]; then
        log_warn "Raw 'defaults write' (use audit_default → journal can undo it):"
        printf '%s\n' "$hits" | sed 's|^|    |'
        issues=$((issues + 1))
    fi

    # 2. Raw `launchctl bootstrap`
    hits=$(grep -rnE 'launchctl[[:space:]]+bootstrap' "$target" --include='*.sh' 2>/dev/null | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' || true)
    if [[ -n "$hits" ]]; then
        log_warn "Raw 'launchctl bootstrap' (use _journal_append_launchd for undo):"
        printf '%s\n' "$hits" | sed 's|^|    |'
        issues=$((issues + 1))
    fi

    # 3. curl | bash patterns
    hits=$(grep -rnE 'curl[^|]*\|[[:space:]]*((sudo|env|command)[[:space:]]+)?(sh|bash|zsh|python[0-9.]*)' "$target" --include='*.sh' 2>/dev/null || true)
    if [[ -n "$hits" ]]; then
        log_warn "'curl | bash' pattern (fetch + verify + execute instead):"
        printf '%s\n' "$hits" | sed 's|^|    |'
        issues=$((issues + 1))
    fi

    printf '\n'
    if (( issues == 0 )); then
        log_ok "lint clean — $target"
        return 0
    fi
    log_warn "lint found $issues issue(s) — see PLUGINS.md"
    return 1
}

# `macrift plugin restore` — re-install every lockfile entry that isn't
# currently present. The reproducibility play: move plugins.lock.json to a
# fresh machine, run `macrift plugin restore`, get the same plugin set back
# at the same refs (and the same commit if the source still resolves to it).
_plugin_cli_restore() {
    if [[ ! -f "$MACRIFT_PLUGINS_LOCK" ]]; then
        log_err "No lockfile at $MACRIFT_PLUGINS_LOCK"
        log_hint "install at least one plugin first to seed the lockfile"
        return 1
    fi
    local entries
    entries=$(jq -r '.plugins | keys[]' "$MACRIFT_PLUGINS_LOCK" 2>/dev/null || true)
    if [[ -z "$entries" ]]; then
        log_info "Lockfile is empty — nothing to restore"
        return 0
    fi

    local installed=0 skipped=0 failed=0
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        if [[ -d "$MACRIFT_PLUGINS_DIR/$name" ]]; then
            log_skip "$name: already installed"
            skipped=$((skipped + 1))
            continue
        fi

        local source ref add_arg
        source=$(jq -r --arg n "$name" '.plugins[$n].source // empty' "$MACRIFT_PLUGINS_LOCK")
        ref=$(jq -r --arg n "$name" '.plugins[$n].ref // empty'    "$MACRIFT_PLUGINS_LOCK")
        if [[ -z "$source" || "$source" == "null" ]]; then
            log_warn "$name: lockfile has no source — cannot restore (was the install a symlink?)"
            failed=$((failed + 1))
            continue
        fi
        add_arg="$source"
        [[ -n "$ref" && "$ref" != "null" ]] && add_arg="$source@$ref"

        log_info "Restoring $name from $add_arg"
        if _plugin_cli_add "$add_arg"; then
            installed=$((installed + 1))
        else
            log_warn "$name: restore failed"
            failed=$((failed + 1))
        fi
    done <<<"$entries"

    printf '\n'
    log_info "Restore: $installed installed, $skipped already-present, $failed failed"
    [[ $failed -gt 0 ]] && return 1
    return 0
}

# CLI dispatch for `macrift plugin ...` — sourced and called from macrift.sh.
_plugin_cli() {
    local sub="${1:-list}"
    [[ $# -gt 0 ]] && shift
    case "$sub" in
        help|--help|-h) ;;
        *) _plugin_require_jq || return 1 ;;
    esac
    case "$sub" in
        list)              _plugin_cli_list "$@" ;;
        add)               _plugin_cli_add "$@" ;;
        remove|rm)         _plugin_cli_remove "$@" ;;
        update|upgrade)    _plugin_cli_update "$@" ;;
        info|show)         _plugin_cli_info "$@" ;;
        lint|check)        _plugin_cli_lint "$@" ;;
        restore)           _plugin_cli_restore "$@" ;;
        help|--help|-h)    _plugin_cli_help ;;
        *)
            log_err "Unknown plugin subcommand: $sub"
            _plugin_cli_help >&2
            return 1
            ;;
    esac
}

_plugin_cli_help() {
    cat <<'HELP'
Usage: macrift plugin <subcommand> [args]

Subcommands:
  list                          list installed plugins (name / version / status / desc)
  add <source>[@<ref>]          clone, validate, prompt, install
                                source: github.com/user/repo, https://..., file://..., /path
  remove <name>                 delete a plugin + lockfile entry (state undo via 'macrift undo')
  update [<name>]               git pull every plugin (or just the named one)
  info <name>                   manifest fields + compat status + lint findings + lockfile entry
  lint <path-or-name>           static checks against PLUGINS.md do-not-do rules
  restore                       re-install every lockfile entry not currently present
                                (reproducibility — bring plugins.lock.json to a new machine)
  help                          this message

Aliases: rm=remove, upgrade=update, show=info, check=lint.

See PLUGINS.md for the plugin author contract and SECURITY.md for the trust model.
HELP
}

# `macrift plugin list` — render a tab-aligned table of installed plugins.
# Friendly empty-case message uses log_info / log_hint so the styling matches
# the rest of macrift's output.
_plugin_cli_list() {
    local rows=() d name version description status
    while IFS= read -r d; do
        [[ -z "$d" ]] && continue
        name=$(_plugin_field "$d" .name) || continue
        version=$(_plugin_field "$d" .version) || version="?"
        description=$(_plugin_field "$d" .description) || description=""
        # Suppress log_warn from compat_ok here — STATUS column communicates
        # the gist; `macrift plugin info <name>` (next slice) will show the
        # specific incompat reason.
        if _plugin_compat_ok "$d" >/dev/null 2>&1; then
            status="ok"
        else
            status="incompatible"
        fi
        rows+=("$name"$'\t'"$version"$'\t'"$status"$'\t'"$description")
    done < <(_plugin_discover)

    if [[ ${#rows[@]} -eq 0 ]]; then
        printf '\n'
        log_info "No plugins installed."
        log_hint "see PLUGINS.md for how to write one, or browse known plugins at https://github.com/emylfy/awesome-macrift-plugins"
        printf '\n'
        return 0
    fi

    # Render — widest NAME/VERSION/STATUS column drives padding (min widths for headers).
    local max_name=4 max_ver=7 max_status=6 r n v s _desc
    for r in "${rows[@]}"; do
        IFS=$'\t' read -r n v s _desc <<<"$r"
        (( ${#n} > max_name ))   && max_name=${#n}
        (( ${#v} > max_ver ))    && max_ver=${#v}
        (( ${#s} > max_status )) && max_status=${#s}
    done
    printf '\n'
    printf '  %-*s  %-*s  %-*s  %s\n' "$max_name" "NAME" "$max_ver" "VERSION" "$max_status" "STATUS" "DESCRIPTION"
    for r in "${rows[@]}"; do
        IFS=$'\t' read -r n v s _desc <<<"$r"
        printf '  %-*s  %-*s  %-*s  %s\n' "$max_name" "$n" "$max_ver" "$v" "$max_status" "$s" "$_desc"
    done
    printf '\n'
}

# TUI

# Read catalog entries as TSV (name<TAB>source<TAB>description).
# Empty / missing file → no rows. The catalog is a single flat list.
_plugin_catalog_entries() {
    local cf="$MACRIFT_DIR/catalog.json"
    [[ -f "$cf" ]] || return 0
    jq -r '.plugins[] | [.name, .source, .description] | @tsv' "$cf" 2>/dev/null
}

# Set of installed plugin names → assoc array via name-ref ($1).
_plugin_installed_set() {
    local -n _out="$1"
    _out=()
    local d nm
    while IFS= read -r d; do
        [[ -n "$d" ]] || continue
        nm=$(_plugin_field "$d" '.name' 2>/dev/null) || nm="$(basename "$d")"
        _out["$nm"]=1
    done < <(_plugin_discover)
}

# Free-text source prompt → hand off to _plugin_cli_add (preview + confirms live there).
_plugin_add_manual() {
    clear
    printf '  %bAdd from URL or path%b\n' "$BOLD" "$RESET"
    printf '  %bgithub.com/user/repo  ·  https://...  ·  /local/path   (optional @ref)%b\n\n' "$DIM" "$RESET"
    printf '  %bsource:%b ' "$CYAN" "$RESET"
    local src
    if ! IFS= read -r src || [[ -z "$src" ]]; then
        log_info "Cancelled"
        return 0
    fi
    _plugin_cli_add "$src"
}

# Add-plugin screen: catalog entries install directly, manual URL/path as the
# escape hatch. Already-installed plugins are filtered out (they live under
# Manage Plugins).
_plugin_add_menu() {
    crumb_push "Add plugin"
    while true; do
        clear
        local -A installed=()
        _plugin_installed_set installed

        local -a items=() actions=()

        # Catalog — direct install rows for everything not already installed.
        local -a cat_names=() cat_srcs=()
        local name src desc
        while IFS=$'\t' read -r name src desc; do
            [[ -n "$name" ]] || continue
            [[ -n "${installed[$name]+x}" ]] && continue
            cat_names+=("$name"); cat_srcs+=("$src")
        done < <(_plugin_catalog_entries)
        if (( ${#cat_names[@]} > 0 )); then
            items+=("## Catalog")
            local k
            for k in "${!cat_names[@]}"; do
                items+=("${cat_names[$k]}")
                actions+=("install:${cat_srcs[$k]}")
            done
        fi

        # Leading `---` only when a section already sits above it, else it renders
        # as a dangling blank row at the top of the box.
        (( ${#items[@]} > 0 )) && items+=("---")
        items+=("## Manual" "From URL or path...")
        actions+=(manual)
        items+=("Back")

        local choice
        choice=$(show_menu "Add plugin" "${items[@]}")
        [[ "$choice" == "0" ]] && break
        local action="${actions[$((choice - 1))]:-}"
        # On a successful install, leave the Add screen so the user lands back on
        # Manage Plugins with the new entry under Installed (rather than sitting on
        # a now-emptied Add screen). Install success = installed count grew, since
        # _plugin_cli_add returns 0 on both success and a declined confirm.
        local n0 n1
        case "$action" in
            install:*)
                clear
                n0=$(_plugin_discover | wc -l | tr -d ' ')
                _plugin_cli_add "${action#install:}" || true
                wait_enter
                n1=$(_plugin_discover | wc -l | tr -d ' ')
                (( n1 > n0 )) && break
                ;;
            manual)
                n0=$(_plugin_discover | wc -l | tr -d ' ')
                _plugin_add_manual || true
                wait_enter
                n1=$(_plugin_discover | wc -l | tr -d ' ')
                (( n1 > n0 )) && break
                ;;
            "") ;;
        esac
    done
    crumb_pop
}

# Per-plugin screen: Info / Update / Lint / Remove.
_plugin_one_menu() {
    local name="$1"
    crumb_push "$name"
    while true; do
        clear
        local ver
        ver=$(_plugin_field "$MACRIFT_PLUGINS_DIR/$name" '.version' 2>/dev/null) || ver="?"
        local -a items=(
            "## $name $ver"
            "Info"
            "Update"
            "Lint"
            "Remove"
            "Back"
        )
        local choice
        choice=$(show_menu "$name" "${items[@]}")
        case "$choice" in
            1) clear; _plugin_cli_info "$name"   || true; wait_enter ;;
            2) clear; _plugin_cli_update "$name" || true; wait_enter ;;
            3) clear; _plugin_cli_lint "$name"   || true; wait_enter ;;
            4) clear; _plugin_cli_remove "$name" || true; wait_enter; break ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

# Plugin management screen — drill-down list of installed plugins + manage actions.
plugins_menu() {
    crumb_push "Manage Plugins"
    # Marks every install/remove reached from here as TUI-driven (dynamic scope
    # reaches _plugin_cli_add/remove) so they skip the CLI-only restart hint.
    local MACRIFT_IN_TUI=1
    while true; do
        clear

        # Discover installed plugins for the drill-down list.
        local -a names=()
        local d nm
        while IFS= read -r d; do
            [[ -n "$d" ]] || continue
            nm=$(_plugin_field "$d" '.name' 2>/dev/null) || nm="$(basename "$d")"
            names+=("$nm")
        done < <(_plugin_discover)

        local -a items=() actions=()
        if (( ${#names[@]} > 0 )); then
            items+=("## Installed")
            for nm in "${names[@]}"; do
                items+=("$nm ›")
                actions+=("one:$nm")
            done
            items+=("---")
        fi
        items+=("## Manage" "Add plugin" "Update all" "Restore from lockfile" "Browse template ↗")
        actions+=(add updateall restore browse)
        items+=("Back")

        local choice
        choice=$(show_menu "Manage Plugins" "${items[@]}")
        [[ "$choice" == "0" ]] && break

        local action="${actions[$((choice - 1))]:-}"
        case "$action" in
            one:*)     _plugin_one_menu "${action#one:}" || true ;;
            add)       _plugin_add_menu || true ;;
            updateall) clear; _plugin_cli_update  || true; wait_enter ;;
            restore)   clear; _plugin_cli_restore || true; wait_enter ;;
            browse)    open "https://github.com/emylfy/macrift-plugin-template" || true ;;
            "") ;;
        esac
    done
    # Refresh the registry so the root menu reflects adds/removes without a restart.
    _plugin_load_all || true
    crumb_pop
}
