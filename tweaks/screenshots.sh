#!/usr/bin/env bash
# macrift — Screenshot tweaks

screenshots_tweaks() {
    audit_reset

    # Save format: png (other options: jpg, gif, pdf, tiff)
    audit_default "com.apple.screencapture" "type" "-string" "png" "Format"

    # Save location
    local screenshots_dir="$HOME/Screenshots"
    mkdir -p "$screenshots_dir"
    audit_default "com.apple.screencapture" "location" "-string" "$screenshots_dir" "Save location"

    # Disable shadow in window screenshots
    audit_default "com.apple.screencapture" "disable-shadow" "-bool" "true" "Window shadow"

    # Remove date from filename
    audit_default "com.apple.screencapture" "include-date" "-bool" "false" "Date in filename"

    if show_audit_table "Screenshots"; then
        apply_audited_defaults
        killall SystemUIServer 2>/dev/null || true
        log_ok "Screenshot settings applied"
    fi
}
