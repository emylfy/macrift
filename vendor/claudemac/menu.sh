#!/usr/bin/env bash
# claudemac — macrift plugin entry point.
#
# Sourced by macrift's _plugin_load_all at startup. Defines a single function,
# claudemac_menu (declared in plugin.json), which the main menu invokes.
#
# Implementation note: the actual install logic lives in handlers/, lifted as-is
# from macrift core (customize/claude_code{,_telegram}.sh) so we can iterate
# without rewriting 2600 lines. The only adaptation is rebinding CC_CONFIG to
# this plugin's own config/ so handlers find their resources here, not in
# macrift's pre-extraction config/claude-code/.

# Self-locate so the plugin can find its own files regardless of where macrift
# (or a future `macrift plugin add`) installs it.
_CLAUDEMAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export _CLAUDEMAC_DIR

# Point handlers at THIS plugin's config/ tree BEFORE sourcing — the handlers
# use `CC_CONFIG="${CC_CONFIG:-…}"`, so pre-setting it here wins without any
# post-source override gymnastics.
CC_CONFIG="$_CLAUDEMAC_DIR/config"
export CC_CONFIG

# shellcheck source=handlers/claude-code.sh
source "$_CLAUDEMAC_DIR/handlers/claude-code.sh"
# shellcheck source=handlers/telegram.sh
source "$_CLAUDEMAC_DIR/handlers/telegram.sh"

# Public entry — what `_plugin_load_all` registers and main_menu invokes.
# Delegate to claude_code_menu (defined by handlers/claude-code.sh), which
# already implements the full submenu, registry, wizard, etc.
claudemac_menu() {
    claude_code_menu
}
