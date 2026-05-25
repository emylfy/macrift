#!/usr/bin/env bash
# macrift — Dock tweaks

dock_tweaks() {
    audit_default_optional "com.apple.dock" "autohide-delay" "-float" "0" "Autohide delay"
    audit_default_optional "com.apple.dock" "autohide-time-modifier" "-float" "0.3" "Animation speed"

    audit_sep

    audit_default "com.apple.dock" "minimize-to-application" "-bool" "true" "Minimize to app"
    audit_default "com.apple.dock" "mineffect" "-string" "scale" "Minimize effect"

    audit_sep

    audit_default "com.apple.dock" "show-recents" "-bool" "false" "Recent apps"
    audit_default "com.apple.dock" "showhidden" "-bool" "true" "Dim hidden apps"
    audit_default "com.apple.dock" "mru-spaces" "-bool" "false" "Rearrange Spaces"
    audit_default "com.apple.dock" "static-only" "-bool" "false" "Only running apps"
}
