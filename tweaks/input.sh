#!/usr/bin/env bash
# macrift — Trackpad & Mouse tweaks

input_tweaks() {
    audit_default "com.apple.AppleMultitouchTrackpad" "Clicking" "-bool" "true" "Tap to click"
    audit_default "NSGlobalDomain" "com.apple.mouse.tapBehavior" "-int" "1" "Tap to click (global)"

    audit_sep

    audit_default "com.apple.AppleMultitouchTrackpad" "TrackpadRightClick" "-bool" "true" "Right-click"
    audit_default "com.apple.AppleMultitouchTrackpad" "TrackpadThreeFingerDrag" "-bool" "true" "Three-finger drag"
    audit_default "NSGlobalDomain" "NSWindowShouldDragOnGesture" "-bool" "true" "Drag windows anywhere"
    audit_default_optional "NSGlobalDomain" "com.apple.mouse.linear" "-bool" "true" "Disable pointer acceleration"
}
