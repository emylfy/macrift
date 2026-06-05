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
# mismatch is a load-time error, not a runtime crash.
MACRIFT_API_VERSION=1

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
# tab-separated:  section \t entry \t function
# Read by macrift.sh's main_menu to inject plugin items.
MACRIFT_PLUGIN_REGISTRY=()

# Discover, compat-check, source, and register every plugin under
# $MACRIFT_PLUGINS_DIR. Idempotent: clears the registry first. Skips plugins
# whose menu.sh fails to source or doesn't define the declared function.
# Plugin failures emit log_warn but never abort the startup of macrift itself.
_plugin_load_all() {
    MACRIFT_PLUGIN_REGISTRY=()
    local dir name section entry func
    while IFS= read -r dir; do
        [[ -z "$dir" ]] && continue
        _plugin_compat_ok "$dir" || continue

        # name is already validated by _plugin_compat_ok; safe to read.
        name=$(_plugin_field "$dir" .name)
        section=$(_plugin_field "$dir" .menu.section) || {
            log_warn "Plugin $name: missing menu.section — skipping"
            continue
        }
        entry=$(_plugin_field "$dir" .menu.entry) || {
            log_warn "Plugin $name: missing menu.entry — skipping"
            continue
        }
        func=$(_plugin_field "$dir" .menu.function) || {
            log_warn "Plugin $name: missing menu.function — skipping"
            continue
        }

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

        MACRIFT_PLUGIN_REGISTRY+=("$section"$'\t'"$entry"$'\t'"$func")
    done < <(_plugin_discover)
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
    local clone_status=0
    if [[ -n "$ref" ]]; then
        git clone --depth=1 --branch "$ref" "$src" "$tmp/clone" 2>&1 | tail -5 || clone_status=1
    else
        git clone --depth=1 "$src" "$tmp/clone" 2>&1 | tail -5 || clone_status=1
    fi
    if [[ $clone_status -ne 0 || ! -d "$tmp/clone" ]]; then
        log_err "git clone failed"
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
    local target="$MACRIFT_PLUGINS_DIR/$name"
    if [[ -e "$target" ]]; then
        log_warn "Plugin $name is already installed at $target"
        if ! confirm "Overwrite existing installation?" "n"; then
            log_skip "kept existing $name"
            rm -rf "$tmp"
            return 0
        fi
        local ts backup
        ts=$(date +%s)
        backup="$target.bak.$ts"
        mv "$target" "$backup"
        log_info "Old version backed up to $backup"
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

    if [[ -f "$clone_dir/README.md" ]]; then
        log_info "README preview (first 20 lines):"
        printf '    ────────\n'
        head -n 20 "$clone_dir/README.md" | sed 's/^/    /'
        printf '    ────────\n\n'
    fi

    if [[ -d "$clone_dir/.git" ]]; then
        log_info "Recent commits:"
        git -C "$clone_dir" log --oneline -5 2>/dev/null | sed 's/^/    /'
        printf '\n'
    fi

    if ! confirm "Install $name?" "y"; then
        log_skip "cancelled"
        rm -rf "$tmp"
        return 0
    fi

    if ! mv "$clone_dir" "$target"; then
        log_err "Failed to move plugin into $target"
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$tmp"

    # Run on_install hook if defined
    local on_install
    on_install=$(_plugin_field "$target" .lifecycle.on_install 2>/dev/null || true)
    if [[ -n "${on_install:-}" && -f "$target/$on_install" ]]; then
        log_info "Running on_install hook: $on_install"
        if ! bash "$target/$on_install"; then
            log_warn "on_install returned non-zero (plugin installed but hook may not have completed)"
        fi
    fi

    _plugin_lock_add "$name" "$version" "$src" "$ref" "$target"

    printf '\n'
    log_ok "Installed $name $version → $target"
    log_hint "restart macrift to see '$name' in the main menu"
}

# `macrift plugin remove <name>` — run on_remove hook if any, delete dir,
# update lockfile. State changes the plugin made (defaults / launchd / rc-file
# markers) need `macrift undo` separately — full per-plugin journal-undo is
# future work (the journal currently tags by session, not plugin).
_plugin_cli_remove() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: macrift plugin remove <name>"
        return 1
    fi
    local name="$1"
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

    local on_remove
    on_remove=$(_plugin_field "$target" .lifecycle.on_remove 2>/dev/null || true)
    if [[ -n "${on_remove:-}" && -f "$target/$on_remove" ]]; then
        log_info "Running on_remove hook: $on_remove"
        bash "$target/$on_remove" || log_warn "on_remove returned non-zero (continuing)"
    fi

    rm -rf "$target"
    _plugin_lock_remove "$name"

    log_ok "Removed $name"
    log_hint "restart macrift to drop the entry from the main menu"
}

# `macrift plugin update [<name>]` — git pull each git-checkout plugin (or
# just the named one). Re-validates compat after pull and bumps the lockfile.
_plugin_cli_update() {
    local target_name="${1:-}"
    local updated=0 skipped=0 failed=0
    if [[ -n "$target_name" ]]; then
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

# `macrift plugin info <name>` — manifest fields + compat status + lockfile
# entry + README pointer. Read-only.
_plugin_cli_info() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: macrift plugin info <name>"
        return 1
    fi
    local name="$1"
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

    if _plugin_compat_ok "$dir" >/dev/null 2>&1; then
        printf '  Status:    ok\n'
    else
        printf '  Status:    incompatible (re-run with verbose flag for the reason)\n'
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
    elif [[ -d "$MACRIFT_PLUGINS_DIR/$target" ]]; then
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
    fi
    if [[ ! -f "$target/menu.sh" ]]; then
        log_warn "menu.sh missing — plugin won't expose any menu entry"
        issues=$((issues + 1))
    fi

    local hits
    # 1. Raw `defaults write` outside audit_default
    hits=$(grep -rnE '^[[:space:]]*defaults[[:space:]]+write' "$target" --include='*.sh' 2>/dev/null | grep -v 'audit_default' || true)
    if [[ -n "$hits" ]]; then
        log_warn "Raw 'defaults write' (use audit_default → journal can undo it):"
        printf '%s\n' "$hits" | sed 's|^|    |'
        issues=$((issues + 1))
    fi

    # 2. Raw `launchctl bootstrap`
    hits=$(grep -rnE '^[[:space:]]*launchctl[[:space:]]+bootstrap' "$target" --include='*.sh' 2>/dev/null || true)
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
  info <name>                   manifest fields + compat status + lockfile entry
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
