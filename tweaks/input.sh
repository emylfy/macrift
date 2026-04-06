#!/usr/bin/env bash
# macrift — Trackpad & Mouse tweaks

input_tweaks() {
    audit_default "com.apple.AppleMultitouchTrackpad" "Clicking" "-bool" "true" "Tap to click"
    audit_default "NSGlobalDomain" "com.apple.mouse.tapBehavior" "-int" "1" "Tap to click (global)"
    audit_default "NSGlobalDomain" "com.apple.trackpad.scaling" "-float" "2.5" "Tracking speed"  # 0–3 scale, 2.5 ≈ "Fast" in System Settings

    audit_sep

    audit_default "com.apple.AppleMultitouchTrackpad" "TrackpadRightClick" "-bool" "true" "Right-click"
    audit_default "com.apple.AppleMultitouchTrackpad" "TrackpadThreeFingerDrag" "-bool" "true" "Three-finger drag"
    audit_default "NSGlobalDomain" "NSWindowShouldDragOnGesture" "-bool" "true" "Drag windows anywhere"
    audit_default "NSGlobalDomain" "com.apple.mouse.linear" "-bool" "true" "Disable pointer acceleration"
}
