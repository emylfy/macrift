#!/usr/bin/env bash
# macrift — Finder tweaks

finder_tweaks() {
    audit_default "NSGlobalDomain" "AppleShowAllExtensions" "-bool" "true" "Show extensions"
    audit_default "com.apple.finder" "AppleShowAllFiles" "-bool" "true" "Show hidden files"
    audit_default "com.apple.finder" "ShowPathbar" "-bool" "true" "Path bar"
    audit_default "com.apple.finder" "ShowStatusBar" "-bool" "true" "Status bar"
    audit_default "com.apple.finder" "_FXShowPosixPathInTitle" "-bool" "true" "Full path in title"
    audit_default "com.apple.finder" "ShowRecentTags" "-bool" "false" "Show recent tags"

    audit_sep

    audit_default "com.apple.finder" "FXDefaultSearchScope" "-string" "SCcf" "Default search"
    audit_default "com.apple.finder" "FXPreferredViewStyle" "-string" "Nlsv" "Default view"
    audit_default "com.apple.finder" "NewWindowTarget" "-string" "PfHm" "New window target"
    audit_default "com.apple.finder" "NewWindowTargetPath" "-string" "file://$HOME/" "New window path"

    audit_sep

    audit_default "com.apple.finder" "FXEnableExtensionChangeWarning" "-bool" "false" "Extension change warn"
    audit_default "com.apple.finder" "DisableAllAnimations" "-bool" "true" "Disable animations"
    audit_default "com.apple.finder" "QuitMenuItem" "-bool" "true" "Quit Finder menu"
    audit_default "com.apple.finder" "WarnOnEmptyTrash" "-bool" "false" "Empty Trash warning"
    audit_default "com.apple.finder" "FinderSounds" "-bool" "false" "Disable Finder sounds"
    audit_default "NSGlobalDomain" "com.apple.springing.delay" "-float" "0" "Instant spring folders"

    audit_sep

    audit_default "com.apple.desktopservices" "DSDontWriteNetworkStores" "-bool" "true" ".DS_Store on network"
    audit_default "com.apple.desktopservices" "DSDontWriteUSBStores" "-bool" "true" ".DS_Store on USB"
    audit_default "com.apple.finder" "_FXSortFoldersFirst" "-bool" "true" "Folders on top"
    audit_default "com.apple.finder" "_FXSortFoldersFirstOnDesktop" "-bool" "true" "Folders on top (Desktop)"

    # ~/Library visibility
    local lib_visible="false"
    local lib_flags
    lib_flags=$(stat -f "%Sf" ~/Library 2>/dev/null || echo "hidden")
    [[ "$lib_flags" != *hidden* ]] && lib_visible="true"
    AUDIT_ENTRIES+=("Show Library folder|${lib_visible}|true|chflags|nohidden|-bool")

    # Default sort for new folders — nested dict, applied via PlistBuddy (see _finder_sort_write)
    local current_sort
    current_sort=$(/usr/libexec/PlistBuddy -c "Print :FK_StandardViewSettings:ExtendedListViewSettingsV2:sortColumn" \
        "$HOME/Library/Preferences/com.apple.finder.plist" 2>/dev/null)
    [[ -z "$current_sort" ]] && current_sort="name"
    AUDIT_ENTRIES+=("Default sort (new folders)|${current_sort}|kind|finder_sort|sortColumn|-string")
}
