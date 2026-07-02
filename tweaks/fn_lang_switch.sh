#!/usr/bin/env bash
# macrift — toggle keyboard input source on the Globe/FN key.
# Headless port: compile a tiny Swift daemon wrapped in a hidden LSUIElement .app
# bundle (no dock/menu-bar icon, not in /Applications), run via LaunchAgent. The
# bundle exists only so TCC attributes the Input Monitoring grant to a named app
# instead of a bare binary path. A plain FN tap switches layout; FN in a combo is
# left alone.

FNLANG_LABEL="com.macrift.fnlangswitch"
FNLANG_SUPPORT_DIR="$HOME/Library/Application Support/macrift"
FNLANG_APP="$FNLANG_SUPPORT_DIR/macrift FN Switch.app"
FNLANG_BIN="$FNLANG_APP/Contents/MacOS/fnlangswitchd"
FNLANG_INFO_PLIST="$FNLANG_APP/Contents/Info.plist"
FNLANG_SRC="$MACRIFT_DIR/tweaks/fn_lang_switch.swift"
FNLANG_PLIST="$HOME/Library/LaunchAgents/$FNLANG_LABEL.plist"
FNLANG_LOG_DIR="$HOME/Library/Logs/macrift"
FNLANG_LOG="$FNLANG_LOG_DIR/fnlangswitchd.log"

# System Settings deep links + the Globe-key behaviour default.
FNLANG_INPUTMON_PANE="x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
# ?Keyboard anchors the section holding "Press 🌐 key to" (verified on macOS 27)
FNLANG_KEYBOARD_PANE="x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Keyboard"
FNLANG_FN_DOMAIN="com.apple.HIToolbox"
FNLANG_FN_KEY="AppleFnUsageType"   # 0 = Do Nothing, 1 = picker (macOS default)

_fnlang_check_swift() {
    if ! xcrun --find swiftc &>/dev/null; then
        log_warn "Xcode Command Line Tools not found"
        if confirm "Install Xcode Command Line Tools? (opens system installer)"; then
            xcode-select --install 2>/dev/null || true
            log_info "Re-run after the installer finishes"
        fi
        return 1
    fi
}

_fnlang_write_info_plist() {
    cat > "$FNLANG_INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>$FNLANG_LABEL</string>
    <key>CFBundleName</key>
    <string>macrift FN Switch</string>
    <key>CFBundleDisplayName</key>
    <string>macrift FN Switch</string>
    <key>CFBundleExecutable</key>
    <string>fnlangswitchd</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST
}

_fnlang_compile() {
    mkdir -p "$(dirname "$FNLANG_BIN")"
    if [[ "$FNLANG_BIN" -nt "$FNLANG_SRC" ]] && [[ -x "$FNLANG_BIN" ]]; then
        return 0
    fi
    log_info "Compiling fnlangswitchd..."
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Would compile to $FNLANG_BIN (inside ~${FNLANG_APP#"$HOME"})"
        return 0
    fi
    if xcrun swiftc \
        -O \
        -framework AppKit \
        -framework Carbon \
        -framework IOKit \
        -o "$FNLANG_BIN" \
        "$FNLANG_SRC" 2>&1; then
        _fnlang_write_info_plist
        # Sign the whole bundle so TCC attributes the Input Monitoring grant to it.
        # An unsigned bundle may not show up in the pane, so a failure is worth a warning.
        if ! codesign --force --sign - "$FNLANG_APP" 2>/dev/null; then
            log_warn "codesign failed — 'macrift FN Switch' may not appear in Input Monitoring"
        fi
        log_ok "Built → ~${FNLANG_APP#"$HOME"}"
    else
        log_err "Compile failed"
        return 1
    fi
}

_fnlang_fn_usage() {
    defaults read "$FNLANG_FN_DOMAIN" "$FNLANG_FN_KEY" 2>/dev/null
}

# Guide the user through the two manual prerequisites: Input Monitoring (so the
# daemon receives FN events) and Globe → Do Nothing (so macOS stops stealing FN).
# The two System Settings panes share one window, so step 1 pauses before step 2.
_fnlang_onboard() {
    printf '\n'
    log_info "Two one-time steps are needed:"

    # 1. Globe key → Do Nothing — set BY HAND in the pane. The UI switch applies
    # immediately; a `defaults write` here only lands after relogin and makes the
    # installer claim "already set" while macOS still intercepts FN. A read of 0
    # is trustworthy exactly because only the UI writes this key now.
    if [[ "$(_fnlang_fn_usage)" == "0" ]]; then
        log_ok "Globe key already set to 'Do Nothing'"
    elif open "$FNLANG_KEYBOARD_PANE" 2>/dev/null; then
        log_info "Opened Keyboard settings — set 'Press 🌐 key to' → 'Do Nothing' (applies immediately)"
        wait_enter
    else
        log_info "System Settings → Keyboard → 'Press 🌐 key to' → 'Do Nothing'"
    fi

    # 2. Input Monitoring permission. The daemon calls IOHIDRequestAccess on launch,
    # which should register 'macrift FN Switch' in the list — but a launchd-started
    # ad-hoc bundle does not always show up, so hand the user the manual-add path.
    printf '\n'
    log_info "Grant 'Input Monitoring' to 'macrift FN Switch' so it can see the FN key:"
    log_info "Not in the list? Click '+', press ⌘⇧G in the file dialog and paste:"
    printf '\n    %b~%s%b\n\n' "$CYAN" "${FNLANG_APP#"$HOME"}" "$RESET"
    if open -R "$FNLANG_APP" 2>/dev/null; then
        log_info "Also revealed the app in Finder — drag & drop into the list works too"
    fi
    if open "$FNLANG_INPUTMON_PANE" 2>/dev/null; then
        log_info "Opened Privacy → Input Monitoring — enable 'macrift FN Switch' (toggle it on)"
    else
        log_info "System Settings → Privacy & Security → Input Monitoring → enable 'macrift FN Switch'"
    fi
    # The event tap registers at daemon launch — a grant given later needs a restart
    log_info "Toggled it while the daemon was already running? Restart it:"
    printf '\n    %blaunchctl kickstart -k gui/%s/%s%b\n' "$CYAN" "$UID" "$FNLANG_LABEL" "$RESET"
}

fn_lang_switch_install() {
    clear
    crumb_push "Install"

    _fnlang_check_swift || { wait_enter; crumb_pop; return; }

    log_info "This installs a small headless daemon (hidden, no dock icon, not in /Applications)"
    log_info "Tap FN to switch keyboard layout; FN in a shortcut is left untouched"
    printf '\n'
    if ! confirm "Continue?"; then crumb_pop; return; fi

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Would compile $FNLANG_SRC → $FNLANG_BIN"
        log_info "Would write LaunchAgent: $FNLANG_PLIST"
        log_info "Would bootstrap: gui/$UID/$FNLANG_LABEL"
        log_info "Would open Keyboard settings (Globe → 'Do Nothing' is set by hand there)"
        log_info "Would open Input Monitoring settings pane"
        wait_enter
        crumb_pop
        return
    fi

    _fnlang_compile || { wait_enter; crumb_pop; return; }
    write_launch_agent "$FNLANG_PLIST" "$FNLANG_LABEL" "$FNLANG_BIN" "$FNLANG_LOG" Background
    log_ok "Wrote LaunchAgent → ~${FNLANG_PLIST#"$HOME"}"

    launchd_load "$FNLANG_LABEL" "$FNLANG_PLIST"
    sleep 1

    if launchd_is_loaded "$FNLANG_LABEL"; then
        log_ok "Daemon running"
        # A rebuild re-signs the bundle and invalidates a previous Input Monitoring
        # grant — the daemon then logs granted=false and receives no key events.
        if tail -n 3 "$FNLANG_LOG" 2>/dev/null | grep -q "granted=false"; then
            log_warn "This build has no Input Monitoring grant (a rebuild resets it)"
            log_info "Re-toggle 'macrift FN Switch' in the pane below, then restart the daemon"
        fi
    else
        log_warn "Could not verify — check $FNLANG_LOG"
    fi

    _fnlang_onboard

    printf '\n  %bLog:%b %s\n' "$DIM" "$RESET" "~${FNLANG_LOG#"$HOME"}"

    wait_enter
    crumb_pop
}

fn_lang_switch_uninstall() {
    clear
    crumb_push "Uninstall"

    if [[ ! -f "$FNLANG_PLIST" && ! -d "$FNLANG_APP" ]]; then
        log_info "FN Lang Switch not installed"
        wait_enter
        crumb_pop
        return
    fi

    log_info "This stops and removes the FN Lang Switch daemon"
    printf '\n'
    if ! confirm "Continue?"; then crumb_pop; return; fi

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Would bootout: gui/$UID/$FNLANG_LABEL"
        log_info "Would remove: $FNLANG_PLIST"
        log_info "Would remove: $FNLANG_APP"
        log_info "Would remove: $FNLANG_LOG"
        log_info "Would reset the Input Monitoring grant: tccutil reset ListenEvent $FNLANG_LABEL"
        wait_enter
        crumb_pop
        return
    fi

    launchd_unload "$FNLANG_LABEL"
    log_ok "LaunchAgent stopped"

    rm -f "$FNLANG_PLIST" "$FNLANG_LOG"
    rm -rf "$FNLANG_APP"
    log_ok "Removed daemon, LaunchAgent and log"

    if tccutil reset ListenEvent "$FNLANG_LABEL" >/dev/null 2>&1; then
        log_ok "Input Monitoring grant reset"
    else
        log_info "Revoke 'Input Monitoring' for 'macrift FN Switch' in System Settings if you wish"
    fi

    if [[ "$(_fnlang_fn_usage)" == "0" ]]; then
        log_info "Globe key is on 'Do Nothing' — restore it in System Settings → Keyboard if you want the picker back"
    fi

    wait_enter
    crumb_pop
}

fn_lang_switch_status() {
    clear
    crumb_push "Status"

    local daemon_status="not installed"
    if [[ -f "$FNLANG_PLIST" ]]; then
        if launchd_is_loaded "$FNLANG_LABEL"; then
            daemon_status="running"
        else
            daemon_status="installed (not running)"
        fi
    fi

    local fn_usage globe
    fn_usage=$(_fnlang_fn_usage)
    case "$fn_usage" in
        0) globe="Do Nothing" ;;
        "") globe="default (picker — set to Do Nothing)" ;;
        *) globe="picker — set to Do Nothing" ;;
    esac

    show_info_box "FN Lang Switch Status" \
        "Daemon:    $daemon_status" \
        "Globe key: $globe"

    # A leftover log with no daemon is stale — showing it only misleads
    if [[ -f "$FNLANG_LOG" && "$daemon_status" != "not installed" ]]; then
        printf '\n  %bRecent log:%b\n' "$DIM" "$RESET"
        tail -n 5 "$FNLANG_LOG" 2>/dev/null | sed 's/^/    /'
    fi

    wait_enter
    crumb_pop
}

fn_lang_switch_menu() {
    crumb_push "FN Lang Switch"
    while true; do
        clear

        local installed=false
        [[ -f "$FNLANG_PLIST" ]] && installed=true

        local items=()
        if $installed; then
            items+=("Uninstall")
        else
            items+=("Install")
        fi
        items+=("Status" "Back")

        local choice
        choice=$(show_menu "FN Lang Switch"$'\x1f'"Tap FN to switch keyboard layout; FN combos pass through" "${items[@]}")

        case "$choice" in
            1) if $installed; then fn_lang_switch_uninstall; else fn_lang_switch_install; fi ;;
            2) fn_lang_switch_status ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}
