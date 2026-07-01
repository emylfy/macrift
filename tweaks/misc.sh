#!/usr/bin/env bash
# macrift — Misc system tweaks

misc_tweaks() {
    audit_default_optional "com.apple.LaunchServices" "LSQuarantine" "-bool" "false" "App quarantine dialog~Also disables Gatekeeper checks for new downloads"

    audit_sep

    audit_default "NSGlobalDomain" "NSNavPanelExpandedStateForSaveMode" "-bool" "true" "Expand save panel"
    audit_default "NSGlobalDomain" "NSNavPanelExpandedStateForSaveMode2" "-bool" "true" "Expand save panel (older apps)"
    audit_default "NSGlobalDomain" "PMPrintingExpandedStateForPrint" "-bool" "true" "Expand print panel"
    audit_default "NSGlobalDomain" "PMPrintingExpandedStateForPrint2" "-bool" "true" "Expand print panel (older apps)"

    audit_sep

    audit_default "NSGlobalDomain" "NSDocumentSaveNewDocumentsToCloud" "-bool" "false" "Save to iCloud"
    audit_default "NSGlobalDomain" "NSAutomaticWindowAnimationsEnabled" "-bool" "false" "Window animations"
    audit_default "com.apple.WindowManager" "EnableStandardClickToShowDesktop" "-bool" "false" "Click wallpaper shows desktop"
    audit_default "com.apple.WindowManager" "EnableTiledWindowMargins" "-bool" "false" "Tiled window margins"

    # macOS 26+ (Tahoe): context menu icons
    local macos_ver
    macos_ver="$(sw_vers -productVersion 2>/dev/null)"
    if [[ "${macos_ver%%.*}" -ge 26 ]]; then
        audit_sep
        audit_default "NSGlobalDomain" "NSMenuEnableActionImages" "-bool" "false" "Context menu icons"
    fi

    # Boot sound
    local boot_current="true"
    if nvram StartupMute 2>/dev/null | grep -q '%01'; then
        boot_current="false"
    fi
    AUDIT_ENTRIES+=("Startup sound~needs sudo|${boot_current}|false|nvram|StartupMute|-bool")
}
