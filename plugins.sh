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
