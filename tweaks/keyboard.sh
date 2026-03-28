#!/usr/bin/env bash
# macrift — Keyboard & text tweaks

keyboard_tweaks() {
    audit_reset

    # Fast key repeat
    audit_default "NSGlobalDomain" "KeyRepeat" "-int" "2" "Key repeat speed"
    audit_default "NSGlobalDomain" "InitialKeyRepeat" "-int" "15" "Key repeat delay"

    # Disable press-and-hold for accents, enable key repeat
    audit_default "NSGlobalDomain" "ApplePressAndHoldEnabled" "-bool" "false" "Press & hold for accents"

    # Disable auto-correct
    audit_default "NSGlobalDomain" "NSAutomaticSpellingCorrectionEnabled" "-bool" "false" "Auto-correct"
    audit_default "NSGlobalDomain" "NSAutomaticCapitalizationEnabled" "-bool" "false" "Auto-capitalize"

    # Disable smart substitutions
    audit_default "NSGlobalDomain" "NSAutomaticDashSubstitutionEnabled" "-bool" "false" "Smart dashes"
    audit_default "NSGlobalDomain" "NSAutomaticQuoteSubstitutionEnabled" "-bool" "false" "Smart quotes"
    audit_default "NSGlobalDomain" "NSAutomaticPeriodSubstitutionEnabled" "-bool" "false" "Double-space period"

    if show_audit_table "Keyboard & Text"; then
        apply_audited_defaults
        log_ok "Keyboard settings applied"
    fi
}
