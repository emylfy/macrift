#!/usr/bin/env bash
# macrift — Misc system tweaks

misc_tweaks() {
    audit_reset

    # Disable boot sound (on newer Macs)
    audit_default_sudo "SystemAudioVolume" " " "-string" " " "Boot sound"

    # Speed up "Are you sure you want to open this app?" dialog
    audit_default "com.apple.LaunchServices" "LSQuarantine" "-bool" "false" "App open warning"

    if show_audit_table "Misc"; then
        apply_audited_defaults
        log_ok "Misc tweaks applied"
    fi
}
