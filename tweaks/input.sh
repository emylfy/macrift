#!/usr/bin/env bash
# macrift — Trackpad & Mouse tweaks

input_tweaks() {
    audit_reset

    # Trackpad: tap to click
    audit_default "com.apple.AppleMultitouchTrackpad" "Clicking" "-bool" "true" "Tap to click (trackpad)"
    audit_default "NSGlobalDomain" "com.apple.mouse.tapBehavior" "-int" "1" "Tap to click (global)"

    # Trackpad: tracking speed
    audit_default "NSGlobalDomain" "com.apple.trackpad.scaling" "-float" "2.5" "Tracking speed"

    # Enable secondary click (right-click)
    audit_default "com.apple.AppleMultitouchTrackpad" "TrackpadRightClick" "-bool" "true" "Right-click"

    # Drag windows from anywhere (Ctrl+Cmd)
    audit_default "NSGlobalDomain" "NSWindowShouldDragOnGesture" "-bool" "true" "Drag windows anywhere"

    if show_audit_table "Trackpad & Mouse"; then
        apply_audited_defaults
        log_ok "Input settings applied"
    fi
}
