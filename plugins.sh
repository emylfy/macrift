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

# CLI dispatch for `macrift plugin …` — sourced and called from macrift.sh.
# Only `list` is implemented in this slice; the rest stub-fail with a clear
# message so users see the surface that's coming.
_plugin_cli() {
    local sub="${1:-list}"
    [[ $# -gt 0 ]] && shift
    case "$sub" in
        list)              _plugin_cli_list "$@" ;;
        add|remove|update|info|lint)
            log_err "macrift plugin $sub: not yet implemented (next slice)"
            return 1
            ;;
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
Usage: macrift plugin <subcommand>

Subcommands:
  list      List installed plugins
  add       (coming soon) install a plugin from a git URL
  remove    (coming soon) uninstall a plugin + undo via journal
  update    (coming soon) pull latest and re-validate
  info      (coming soon) README + journaled changes for a plugin
  lint      (coming soon) check a plugin against the do-not-do rules

See PLUGINS.md for how to write one.
HELP
}

# `macrift plugin list` — render a tab-aligned table of installed plugins.
# Friendly empty-case message uses log_info / log_hint so the styling matches
# the rest of macrift's output.
_plugin_cli_list() {
    local rows=() d name version description
    while IFS= read -r d; do
        [[ -z "$d" ]] && continue
        name=$(_plugin_field "$d" .name) || continue
        version=$(_plugin_field "$d" .version) || version="?"
        description=$(_plugin_field "$d" .description) || description=""
        rows+=("$name"$'\t'"$version"$'\t'"$description")
    done < <(_plugin_discover)

    if [[ ${#rows[@]} -eq 0 ]]; then
        printf '\n'
        log_info "No plugins installed."
        log_hint "see PLUGINS.md for how to write one, or browse known plugins at https://github.com/emylfy/awesome-macrift-plugins"
        printf '\n'
        return 0
    fi

    # Render — widest NAME/VERSION column drives padding (min widths for headers).
    local max_name=4 max_ver=7 r n v _desc
    for r in "${rows[@]}"; do
        IFS=$'\t' read -r n v _desc <<<"$r"
        (( ${#n} > max_name )) && max_name=${#n}
        (( ${#v} > max_ver )) && max_ver=${#v}
    done
    printf '\n'
    printf '  %-*s  %-*s  %s\n' "$max_name" "NAME" "$max_ver" "VERSION" "DESCRIPTION"
    for r in "${rows[@]}"; do
        IFS=$'\t' read -r n v _desc <<<"$r"
        printf '  %-*s  %-*s  %s\n' "$max_name" "$n" "$max_ver" "$v" "$_desc"
    done
    printf '\n'
}
