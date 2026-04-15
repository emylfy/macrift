#!/usr/bin/env bash
# macrift — Privacy & security tweaks

privacy_recommended() {
    # Tracking & analytics
    audit_default "com.apple.AdLib" "allowIdentifierForAdvertising" "-bool" "false" "Ad identifier tracking"
    audit_default "com.apple.AdLib" "allowApplePersonalizedAdvertising" "-bool" "false" "Personalized ads"
    audit_default "com.apple.AdLib" "forceLimitAdTracking" "-bool" "true" "Limit ad tracking"
    audit_default "com.apple.Safari" "SuppressSearchSuggestions" "-bool" "true" "Help Apple Improve Search"
    audit_default "com.apple.CrashReporter" "DialogType" "-string" "none" "Share Mac analytics"

    audit_sep

    # Firewall
    audit_default "/Library/Preferences/com.apple.alf" "globalstate" "-bool" "true" "Application firewall"
    audit_default "/Library/Preferences/com.apple.alf" "stealthenabled" "-bool" "true" "Stealth mode"

    audit_sep

    # Guest access
    audit_default "/Library/Preferences/com.apple.loginwindow" "GuestEnabled" "-bool" "false" "Guest account login"
    audit_default "/Library/Preferences/SystemConfiguration/com.apple.smb.server" "AllowGuestAccess" "-bool" "false" "Guest sharing (SMB)"
    audit_default "/Library/Preferences/com.apple.AppleFileServer" "guestAccess" "-bool" "false" "Guest sharing (AFP)"

    audit_sep

    # App telemetry
    audit_default "com.microsoft.office" "DiagnosticDataTypePreference" "-string" "ZeroDiagnosticData" "Office telemetry"

    audit_sep

    # Screen lock
    audit_default "/Library/Preferences/com.apple.screensaver" "askForPassword" "-bool" "true" "Password after screensaver"
    audit_default "/Library/Preferences/com.apple.screensaver" "askForPasswordDelay" "-int" "5" "Lock delay (sec)"

    audit_sep

    # Input privacy
    audit_default "NSGlobalDomain" "WebAutomaticSpellingCorrectionEnabled" "-bool" "false" "Online spell correction"
    audit_default "com.apple.HIToolbox" "AppleDictationAutoEnable" "-bool" "false" "Dictation"

}

privacy_strict() {
    # Siri
    audit_default "com.apple.assistant.support" "Assistant Enabled" "-bool" "false" "Ask Siri"
    audit_default "com.apple.SetupAssistant" "DidSeeSiriSetup" "-bool" "true" "Siri setup popup"
    audit_default "com.apple.Siri" "StatusMenuVisible" "-bool" "false" "Siri in menu bar"
    audit_default "com.apple.Siri" "UserHasDeclinedEnable" "-bool" "true" "Siri opt-out flag"

    audit_sep

    # Firewall (strict)
    audit_default "/Library/Preferences/com.apple.alf" "loggingenabled" "-bool" "true" "Firewall logging"

    audit_sep

    # Network (strict)
    audit_default "com.apple.NetworkBrowser" "DisableAirDrop" "-bool" "true" "Disable AirDrop"
    audit_default "/Library/Preferences/SystemConfiguration/com.apple.captive.control.plist" "Active" "-bool" "false" "Captive portal~May break WiFi login at hotels/airports"
    audit_default "/Library/Preferences/com.apple.mDNSResponder.plist" "NoMulticastAdvertisements" "-bool" "true" "Bonjour multicast~May break AirPlay/printer discovery"

    audit_sep

    # Gatekeeper
    audit_default "/Library/Preferences/com.apple.security" "GKAutoRearm" "-bool" "true" "Gatekeeper auto-rearm~Prevents macOS from re-enabling Gatekeeper after 30 days"
}
