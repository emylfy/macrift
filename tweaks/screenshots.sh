#!/usr/bin/env bash
# macrift — Screenshot tweaks

screenshots_tweaks() {
    [[ "$MACRIFT_BATCH_TWEAKS" != true ]] && audit_reset

    audit_default "com.apple.screencapture" "type" "-string" "png" "Format"
    local screenshots_dir="$HOME/Screenshots"
    mkdir -p "$screenshots_dir"
    audit_default "com.apple.screencapture" "location" "-string" "$screenshots_dir" "Save location"

    audit_sep

    audit_default "com.apple.screencapture" "disable-shadow" "-bool" "true" "Window shadow"
    audit_default "com.apple.screencapture" "include-date" "-bool" "false" "Date in filename"

    [[ "$MACRIFT_BATCH_TWEAKS" == true ]] && return 0

    if show_audit_table "Screenshots"; then
        apply_audited_defaults
        log_ok "Screenshot settings applied"
        wait_enter
    fi
}
