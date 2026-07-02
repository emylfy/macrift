#!/usr/bin/env bash
# macrift — Keyboard & text tweaks

keyboard_tweaks() {
    audit_default_optional "NSGlobalDomain" "KeyRepeat" "-int" "2" "Repeat speed~lower = faster; 2 ≈ 30 ms per repeat"
    audit_default_optional "NSGlobalDomain" "InitialKeyRepeat" "-int" "15" "Repeat delay~lower = shorter; 15 ≈ 225 ms before repeat"
    audit_default "NSGlobalDomain" "ApplePressAndHoldEnabled" "-bool" "false" "Press & hold accents~Disables long-press for é ñ ü"

    audit_sep

    audit_default "NSGlobalDomain" "NSAutomaticSpellingCorrectionEnabled" "-bool" "false" "Auto-correct"
    audit_default "NSGlobalDomain" "NSAutomaticCapitalizationEnabled" "-bool" "false" "Auto-capitalize"

    audit_sep

    audit_default "NSGlobalDomain" "NSAutomaticDashSubstitutionEnabled" "-bool" "false" "Smart dashes"
    audit_default "NSGlobalDomain" "NSAutomaticQuoteSubstitutionEnabled" "-bool" "false" "Smart quotes"
    audit_default "NSGlobalDomain" "NSAutomaticPeriodSubstitutionEnabled" "-bool" "false" "Double-space period"

}
