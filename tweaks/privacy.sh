#!/usr/bin/env bash
# macrift — Privacy & security tweaks

privacy_recommended() {
    # Tracking & analytics
    audit_default "com.apple.AdLib" "allowIdentifierForAdvertising" "-bool" "false" "Ad identifier tracking"
    audit_default "com.apple.AdLib" "allowApplePersonalizedAdvertising" "-bool" "false" "Personalized ads"
    audit_default "com.apple.AdLib" "forceLimitAdTracking" "-bool" "true" "Limit ad tracking"
    audit_default "com.apple.CrashReporter" "DialogType" "-string" "none" "Share Mac analytics"

    audit_sep

    # Guest access
    audit_default "/Library/Preferences/com.apple.loginwindow" "GuestEnabled" "-bool" "false" "Guest account login"
    audit_default "/Library/Preferences/SystemConfiguration/com.apple.smb.server" "AllowGuestAccess" "-bool" "false" "Guest sharing (SMB)"

    # App telemetry — only if Office is installed
    if [[ -d "/Applications/Microsoft Word.app" || -d "/Applications/Microsoft Excel.app" \
       || -d "/Applications/Microsoft PowerPoint.app" || -d "/Applications/Microsoft Outlook.app" ]]; then
        audit_sep
        audit_default "com.microsoft.office" "DiagnosticDataTypePreference" "-string" "ZeroDiagnosticData" "Office telemetry"
    fi

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

    # Gatekeeper
    audit_default "/Library/Preferences/com.apple.security" "GKAutoRearm" "-bool" "true" "Gatekeeper auto-rearm~Prevents macOS from re-enabling Gatekeeper after 30 days"
}
