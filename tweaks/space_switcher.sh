#!/usr/bin/env bash
# macrift — instant macOS space switching
# CLI for one-shot calls + optional LaunchAgent daemon that intercepts
# native Ctrl+←/→ and replaces the slow animation with an instant switch.

SPACE_LABEL="com.macrift.space-switcher"
SPACE_BIN_DIR="$HOME/Library/Application Support/macrift/bin"
SPACE_BIN="$SPACE_BIN_DIR/space-switcher"
SPACE_SRC="$MACRIFT_DIR/tweaks/space_switcher.c"
SPACE_PLIST="$HOME/Library/LaunchAgents/$SPACE_LABEL.plist"
SPACE_LOG_DIR="$HOME/Library/Logs/macrift"
SPACE_LOG="$SPACE_LOG_DIR/space-switcher.log"

_space_check_clang() {
    if ! xcrun --find clang &>/dev/null; then
        log_warn "Xcode Command Line Tools not found"
        if confirm "Install Xcode Command Line Tools? (opens system installer)"; then
            xcode-select --install 2>/dev/null || true
            log_info "Re-run after the installer finishes"
        fi
        return 1
    fi
}

_space_compile() {
    mkdir -p "$SPACE_BIN_DIR"
    if [[ -x "$SPACE_BIN" && "$SPACE_BIN" -nt "$SPACE_SRC" ]]; then
        return 0
    fi
    log_info "Compiling space-switcher..."
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Would compile to $SPACE_BIN"
        return 0
    fi
    if xcrun cc -O2 -arch arm64 \
        -framework CoreGraphics -framework CoreFoundation \
        -o "$SPACE_BIN" "$SPACE_SRC" 2>&1; then
        log_ok "Compiled → ${SPACE_BIN/#$HOME/~}"
    else
        log_err "Compile failed"
        return 1
    fi
}

_space_write_plist() {
    mkdir -p "$SPACE_LOG_DIR"
    cat > "$SPACE_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$SPACE_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SPACE_BIN</string>
        <string>--daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>$SPACE_LOG</string>
    <key>StandardErrorPath</key>
    <string>$SPACE_LOG</string>
</dict>
</plist>
PLIST
}

_space_is_loaded() { launchctl print "gui/$UID/$SPACE_LABEL" &>/dev/null; }

_space_load() {
    if _space_is_loaded; then
        launchctl bootout "gui/$UID/$SPACE_LABEL" 2>/dev/null || true
    fi
    launchctl bootstrap "gui/$UID" "$SPACE_PLIST" 2>&1
    launchctl enable "gui/$UID/$SPACE_LABEL" 2>/dev/null || true
}

_space_unload() { launchctl bootout "gui/$UID/$SPACE_LABEL" 2>/dev/null || true; }

_space_show_usage() {
    local bin="${SPACE_BIN/#$HOME/~}"
    printf '\n  %bCLI usage:%b\n' "$BOLD" "$RESET"
    printf '    %b%s left%b     # one-shot: switch one space left\n'  "$CYAN" "$bin" "$RESET"
    printf '    %b%s right%b    # one-shot: switch one space right\n\n' "$CYAN" "$bin" "$RESET"

    printf '  %bDaemon:%b\n' "$BOLD" "$RESET"
    printf '    Intercepts native %bCtrl+←/→%b → instant switch (no animation)\n' "$CYAN" "$RESET"
    printf '    Toggle from the menu. No external hotkey tool needed.\n\n'
}

space_install() {
    clear
    crumb_push "Install"

    _space_check_clang || { wait_enter; crumb_pop; return; }

    log_info "Installs the space-switcher CLI"
    log_info "  • CLI works one-shot: ${SPACE_BIN/#$HOME/~} left|right"
    log_info "  • Daemon (toggle separately) intercepts native Ctrl+←/→"
    printf '\n'
    if ! confirm "Continue?"; then crumb_pop; return; fi

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Would compile $SPACE_SRC → $SPACE_BIN"
        wait_enter
        crumb_pop
        return
    fi

    _space_compile || { wait_enter; crumb_pop; return; }
    _space_show_usage

    log_info "First call triggers an Accessibility prompt"
    log_info "  System Settings → Privacy & Security → Accessibility"

    wait_enter
    crumb_pop
}

space_uninstall() {
    clear
    crumb_push "Uninstall"
    if [[ ! -x "$SPACE_BIN" && ! -f "$SPACE_PLIST" ]]; then
        log_info "Not installed"
        wait_enter
        crumb_pop
        return
    fi
    if ! confirm "Remove space-switcher (CLI + daemon)?"; then crumb_pop; return; fi

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Would bootout, remove plist + binary"
        wait_enter
        crumb_pop
        return
    fi

    _space_unload
    rm -f "$SPACE_PLIST" "$SPACE_BIN"
    log_ok "Removed"
    log_info "Accessibility entry remains in System Settings — remove manually if desired"
    wait_enter
    crumb_pop
}

space_toggle_daemon() {
    if [[ ! -x "$SPACE_BIN" ]]; then
        log_err "space-switcher not installed — run Install first"
        wait_enter
        return
    fi

    if _space_is_loaded; then
        clear
        if ! confirm "Stop daemon? Native Ctrl+←/→ becomes slow again."; then return; fi
        _space_unload
        rm -f "$SPACE_PLIST"
        log_ok "Daemon stopped — native Ctrl+←/→ restored to default behavior"
        sleep 1
        return
    fi

    clear
    log_info "Starts a LaunchAgent that intercepts Ctrl+←/→ at the system level"
    log_info "  • Replaces the slow animation with our instant switch"
    log_info "  • Other Ctrl combos (Ctrl+Shift+←, Ctrl+Cmd+←) pass through unchanged"
    log_info "  • Set-and-forget — survives login"
    printf '\n'
    if ! confirm "Continue?"; then return; fi

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Would write plist and bootstrap"
        wait_enter
        return
    fi

    _space_write_plist
    _space_load
    sleep 1

    if _space_is_loaded; then
        log_ok "Daemon running — try Ctrl+←/→ now"
    else
        log_warn "Daemon failed to start — check $SPACE_LOG"
        log_info "Likely missing Accessibility permission for ${SPACE_BIN/#$HOME/~}"
    fi
    wait_enter
}

space_status() {
    clear
    crumb_push "Status"
    local installed="not installed"
    [[ -x "$SPACE_BIN" ]] && installed="installed"
    local daemon="off"
    _space_is_loaded && daemon="running"

    show_info_box "Space Switcher" \
        "Binary:   $installed" \
        "Daemon:   $daemon"

    if [[ -f "$SPACE_LOG" ]]; then
        printf '\n  %bRecent log:%b\n' "$DIM" "$RESET"
        tail -n 5 "$SPACE_LOG" 2>/dev/null | sed 's/^/    /'
    fi
    wait_enter
    crumb_pop
}

space_switcher_menu() {
    crumb_push "Space Switcher"
    while true; do
        clear
        local items=()
        if [[ -x "$SPACE_BIN" ]]; then
            local toggle_label
            if _space_is_loaded; then
                toggle_label="Native Ctrl+←/→ daemon: on"
            else
                toggle_label="Native Ctrl+←/→ daemon: off"
            fi
            items+=("$toggle_label" "Show usage" "Status" "---" "Uninstall" "Back")
        else
            items+=("Install" "Status" "Back")
        fi

        local choice
        choice=$(show_menu "Space Switcher" "${items[@]}")

        if [[ -x "$SPACE_BIN" ]]; then
            case "$choice" in
                1) space_toggle_daemon ;;
                2) clear; _space_show_usage; wait_enter ;;
                3) space_status ;;
                4) space_uninstall ;;
                0) break ;;
            esac
        else
            case "$choice" in
                1) space_install ;;
                2) space_status ;;
                0) break ;;
            esac
        fi
    done
    crumb_pop
}
