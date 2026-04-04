#!/usr/bin/env bash
# macrift — Finder tweaks

finder_tweaks() {
    [[ "$MACRIFT_BATCH_TWEAKS" != true ]] && audit_reset

    audit_default "NSGlobalDomain" "AppleShowAllExtensions" "-bool" "true" "Show extensions"
    audit_default "com.apple.finder" "AppleShowAllFiles" "-bool" "true" "Show hidden files"
    audit_default "com.apple.finder" "ShowPathbar" "-bool" "true" "Path bar"
    audit_default "com.apple.finder" "ShowStatusBar" "-bool" "true" "Status bar"
    audit_default "com.apple.finder" "_FXShowPosixPathInTitle" "-bool" "true" "Full path in title"
    audit_default "com.apple.finder" "ShowRecentTags" "-bool" "false" "Hide Recent Tags"

    audit_sep

    audit_default "com.apple.finder" "FXDefaultSearchScope" "-string" "SCcf" "Default search"
    audit_default "com.apple.finder" "FXPreferredViewStyle" "-string" "Nlsv" "Default view"
    audit_default "com.apple.finder" "NewWindowTarget" "-string" "PfHm" "New window target"
    audit_default "com.apple.finder" "NewWindowTargetPath" "-string" "file://$HOME/" "New window path"

    audit_sep

    audit_default "com.apple.finder" "FXEnableExtensionChangeWarning" "-bool" "false" "Extension change warn"
    audit_default "com.apple.finder" "DisableAllAnimations" "-bool" "true" "Disable animations"
    audit_default "com.apple.finder" "QuitMenuItem" "-bool" "true" "Quit Finder menu"
    audit_default "com.apple.finder" "WarnOnEmptyTrash" "-bool" "false" "No empty trash warn"
    audit_default "com.apple.finder" "FinderSounds" "-bool" "false" "Disable Finder sounds"
    audit_default "NSGlobalDomain" "com.apple.springing.delay" "-float" "0" "Instant spring folders"

    audit_sep

    audit_default "com.apple.desktopservices" "DSDontWriteNetworkStores" "-bool" "true" ".DS_Store on network"
    audit_default "com.apple.desktopservices" "DSDontWriteUSBStores" "-bool" "true" ".DS_Store on USB"
    audit_default "com.apple.finder" "_FXSortFoldersFirst" "-bool" "true" "Folders on top"
    audit_default "com.apple.finder" "_FXSortFoldersFirstOnDesktop" "-bool" "true" "Folders on top (Desktop)"

    [[ "$MACRIFT_BATCH_TWEAKS" == true ]] && return 0

    if show_audit_table "Finder"; then
        apply_audited_defaults

        chflags nohidden ~/Library 2>/dev/null || true
        log_ok "$HOME/Library unhidden"

        if confirm "Restart Finder?"; then
            killall Finder 2>/dev/null || true
            log_ok "Finder restarted"
        fi
        wait_enter
    fi
}
