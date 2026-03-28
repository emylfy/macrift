#!/usr/bin/env bash
# macrift — Input tweaks

input_tweaks() {
    audit_reset

    audit_default "NSGlobalDomain" "NSAutomaticSpellingCorrectionEnabled" "-bool" "false" "Auto-correct"
    audit_default "NSGlobalDomain" "NSAutomaticCapitalizationEnabled" "-bool" "false" "Auto-capitalize"

    if show_audit_table "Input"; then
        apply_audited_defaults
        log_ok "Input settings applied"
    fi
}
