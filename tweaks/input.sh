#!/usr/bin/env bash
# macrift — Trackpad & Mouse tweaks

input_tweaks() {
    [[ "$MACRIFT_BATCH_TWEAKS" != true ]] && audit_reset

    audit_default "com.apple.AppleMultitouchTrackpad" "Clicking" "-bool" "true" "Tap to click"
    audit_default "NSGlobalDomain" "com.apple.mouse.tapBehavior" "-int" "1" "Tap to click (global)"
    audit_default "NSGlobalDomain" "com.apple.trackpad.scaling" "-float" "2.5" "Tracking speed"

    audit_sep

    audit_default "com.apple.AppleMultitouchTrackpad" "TrackpadRightClick" "-bool" "true" "Right-click"
    audit_default "NSGlobalDomain" "NSWindowShouldDragOnGesture" "-bool" "true" "Drag windows anywhere"
    audit_default "NSGlobalDomain" "com.apple.mouse.linear" "-bool" "true" "Disable pointer acceleration"

    [[ "$MACRIFT_BATCH_TWEAKS" == true ]] && return 0

    if show_audit_table "Trackpad & Mouse"; then
        apply_audited_defaults
        log_ok "Input settings applied"
        wait_enter
    fi
}
