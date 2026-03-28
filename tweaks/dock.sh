#!/usr/bin/env bash
# macrift — Dock tweaks

dock_tweaks() {
    audit_reset

    audit_default "com.apple.dock" "autohide-delay" "-float" "0" "Autohide delay"
    audit_default "com.apple.dock" "minimize-to-application" "-bool" "true" "Minimize to app icon"
    audit_default "com.apple.dock" "show-recents" "-bool" "false" "Show recent apps"
    audit_default "com.apple.dock" "showhidden" "-bool" "true" "Show hidden apps dimmed"

    if show_audit_table "Dock"; then
        apply_audited_defaults
        killall Dock 2>/dev/null || true
        log_ok "Dock restarted"
    fi
}
