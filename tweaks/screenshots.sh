#!/usr/bin/env bash
# macrift — Screenshot tweaks

screenshots_tweaks() {
    audit_default "com.apple.screencapture" "type" "-string" "png" "Format"
    audit_default "com.apple.screencapture" "location" "-string" "$HOME/Screenshots" "Save location"

    audit_sep

    audit_default "com.apple.screencapture" "disable-shadow" "-bool" "true" "Disable window shadow"
    audit_default "com.apple.screencapture" "include-date" "-bool" "false" "Date in filename"
}
