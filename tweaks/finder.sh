#!/usr/bin/env bash
# macrift — Finder tweaks

finder_tweaks() {
    audit_reset

    # Show all file extensions
    audit_default "NSGlobalDomain" "AppleShowAllExtensions" "-bool" "true" "Show all extensions"

    # Show hidden files
    audit_default "com.apple.finder" "AppleShowAllFiles" "-bool" "true" "Show hidden files"

    # Show path bar at bottom
    audit_default "com.apple.finder" "ShowPathbar" "-bool" "true" "Show path bar"

    # Show status bar at bottom
    audit_default "com.apple.finder" "ShowStatusBar" "-bool" "true" "Show status bar"

    # Show full POSIX path in title bar
    audit_default "com.apple.finder" "_FXShowPosixPathInTitle" "-bool" "true" "Full path in title"

    # Search current folder by default
    audit_default "com.apple.finder" "FXDefaultSearchScope" "-string" "SCcf" "Search scope: current folder"

    # Default view style: list (Nlsv=list, icnv=icon, clmv=column, glyv=gallery)
    audit_default "com.apple.finder" "FXPreferredViewStyle" "-string" "Nlsv" "Default view: list"

    # New window opens home directory
    audit_default "com.apple.finder" "NewWindowTarget" "-string" "PfHm" "New window: home dir"
    audit_default "com.apple.finder" "NewWindowTargetPath" "-string" "file://$HOME/" "New window path"

    # Disable extension change warning
    audit_default "com.apple.finder" "FXEnableExtensionChangeWarning" "-bool" "false" "Extension change warning"

    # Disable .DS_Store on network volumes
    audit_default "com.apple.desktopservices" "DSDontWriteNetworkStores" "-bool" "true" "No .DS_Store (network)"

    # Disable .DS_Store on USB drives
    audit_default "com.apple.desktopservices" "DSDontWriteUSBStores" "-bool" "true" "No .DS_Store (USB)"

    # Keep folders on top when sorting
    audit_default "com.apple.finder" "_FXSortFoldersFirst" "-bool" "true" "Folders on top"

    # Disable window animations
    audit_default "com.apple.finder" "DisableAllAnimations" "-bool" "true" "Disable Finder animations"

    # Show Library folder
    if show_audit_table "Finder"; then
        apply_audited_defaults

        # Unhide ~/Library (not a defaults command)
        chflags nohidden ~/Library 2>/dev/null || true
        log_ok "~/Library unhidden"

        killall Finder 2>/dev/null || true
        log_ok "Finder restarted"
    fi
}
