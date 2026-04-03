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

    local boot_muted=false
    if nvram StartupMute 2>/dev/null | grep -q '%01'; then
        boot_muted=true
    fi

    [[ "$MACRIFT_BATCH_TWEAKS" == true ]] && return 0

    if show_audit_table "Misc"; then
        apply_audited_defaults

        if [[ "$boot_muted" == false ]]; then
            if [[ "$MACRIFT_DRY_RUN" == true ]]; then
                log_info "Dry run — would mute boot sound (nvram)"
            else
                require_sudo
                if sudo nvram StartupMute=%01 2>/dev/null; then
                    log_ok "Boot sound muted"
                else
                    log_warn "Could not mute boot sound"
                fi
            fi
        else
            log_skip "Boot sound already muted"
        fi

        log_ok "Misc tweaks applied"
        wait_enter
    fi
}
