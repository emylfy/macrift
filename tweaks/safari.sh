#!/usr/bin/env bash
# macrift — Safari tweaks

safari_tweaks() {
    [[ "$MACRIFT_BATCH_TWEAKS" != true ]] && audit_reset

    audit_default "com.apple.Safari" "SearchProviderShortName" "-string" "DuckDuckGo" "Search engine"

    [[ "$MACRIFT_BATCH_TWEAKS" == true ]] && return 0

    if show_audit_table "Safari"; then
        apply_audited_defaults
        log_ok "Safari tweaks applied"
        wait_enter
    fi
}
