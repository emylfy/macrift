#!/usr/bin/env bash
# macrift — Misc system tweaks

misc_tweaks() {
    [[ "$MACRIFT_BATCH_TWEAKS" != true ]] && audit_reset

    audit_default "com.apple.LaunchServices" "LSQuarantine" "-bool" "false" "App open warning"

    audit_sep

    audit_default "NSGlobalDomain" "NSNavPanelExpandedStateForSaveMode" "-bool" "true" "Expand save panel"
    audit_default "NSGlobalDomain" "NSNavPanelExpandedStateForSaveMode2" "-bool" "true" "Expand save panel 2"
    audit_default "NSGlobalDomain" "PMPrintingExpandedStateForPrint" "-bool" "true" "Expand print panel"
    audit_default "NSGlobalDomain" "PMPrintingExpandedStateForPrint2" "-bool" "true" "Expand print panel 2"

    audit_sep

    audit_default "NSGlobalDomain" "NSDocumentSaveNewDocumentsToCloud" "-bool" "false" "Save to iCloud"
    audit_default "NSGlobalDomain" "NSAutomaticWindowAnimationsEnabled" "-bool" "false" "Window animations"
    audit_default "com.apple.WindowManager" "EnableStandardClickToShowDesktop" "-bool" "false" "Click wallpaper shows desktop"
    audit_default "com.apple.WindowManager" "EnableTiledWindowMargins" "-bool" "false" "Tiled window margins"

    # Boot sound: read current state and add to audit table
    local boot_current="true"
    if nvram StartupMute 2>/dev/null | grep -q '%01'; then
        boot_current="false"
    fi
    AUDIT_ENTRIES+=("Startup sound|${boot_current}|false|nvram|StartupMute|-bool")

    [[ "$MACRIFT_BATCH_TWEAKS" == true ]] && return 0

    if show_audit_table "Misc"; then
        apply_audited_defaults
        log_ok "Misc tweaks applied"
        wait_enter
    fi
}
