#!/usr/bin/env bash
# macrift — disable temporal dithering on Apple Silicon
# Headless port of Stillcolor: compile a tiny C daemon, run it via LaunchAgent.

DITHERING_LABEL="com.macrift.stillcolord"
DITHERING_BIN_DIR="$HOME/Library/Application Support/macrift/bin"
DITHERING_BIN="$DITHERING_BIN_DIR/stillcolord"
DITHERING_SRC="$MACRIFT_DIR/tweaks/dithering.c"
DITHERING_PLIST="$HOME/Library/LaunchAgents/$DITHERING_LABEL.plist"
DITHERING_LOG_DIR="$HOME/Library/Logs/macrift"
DITHERING_LOG="$DITHERING_LOG_DIR/stillcolord.log"

_dithering_check_arch() {
    if [[ "$ARCH" != "arm64" ]]; then
        log_err "Dithering disable requires Apple Silicon (M1+)"
        log_info "Intel Macs use a different display pipeline (no IOMobileFramebufferAP)"
        return 1
    fi
}

_dithering_check_clang() {
    if ! xcrun --find clang &>/dev/null; then
        log_warn "Xcode Command Line Tools not found"
        if confirm "Install Xcode Command Line Tools? (opens system installer)" "y"; then
            xcode-select --install 2>/dev/null || true
            log_info "Re-run after the installer finishes"
        fi
        return 1
    fi
}

_dithering_compile() {
    mkdir -p "$DITHERING_BIN_DIR"
    if [[ "$DITHERING_BIN" -nt "$DITHERING_SRC" ]] && [[ -x "$DITHERING_BIN" ]]; then
        return 0
    fi
    log_info "Compiling stillcolord..."
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would compile to $DITHERING_BIN"
        return 0
    fi
    if xcrun cc \
        -O2 \
        -arch arm64 \
        -framework IOKit \
        -framework CoreGraphics \
        -framework CoreFoundation \
        -o "$DITHERING_BIN" \
        "$DITHERING_SRC" 2>&1; then
        log_ok "Compiled → ~${DITHERING_BIN#"$HOME"}"
    else
        log_err "Compile failed"
        log_hint "clang comes with Xcode CLT — run 'xcode-select --install' and retry"
        return 1
    fi
}

_dithering_query_status() {
    /usr/sbin/ioreg -lw0 2>/dev/null | grep -c '"enableDither" = No' || true
}

dithering_install() {
    clear
    crumb_push "Disable"

    _dithering_check_arch || { wait_enter; crumb_pop; return; }
    _dithering_check_clang || { wait_enter; crumb_pop; return; }

    log_info "This installs a small headless daemon (no app, no menu bar icon)"
    log_info "It disables GPU/DCP-generated temporal dithering on every login"
    printf '\n'
    if ! confirm "Continue?" "y"; then crumb_pop; return; fi

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would compile $DITHERING_SRC → $DITHERING_BIN"
        log_info "Dry run — would write LaunchAgent: $DITHERING_PLIST"
        log_info "Dry run — would bootstrap: gui/$UID/$DITHERING_LABEL"
        wait_enter
        crumb_pop
        return
    fi

    _dithering_compile || { wait_enter; crumb_pop; return; }
    write_launch_agent "$DITHERING_PLIST" "$DITHERING_LABEL" "$DITHERING_BIN" "$DITHERING_LOG" Background --daemon
    log_ok "Wrote LaunchAgent → ~${DITHERING_PLIST#"$HOME"}"

    launchd_load "$DITHERING_LABEL" "$DITHERING_PLIST"
    sleep 1

    local off_count
    off_count=$(_dithering_query_status)
    if [[ "$off_count" -gt 0 ]]; then
        log_ok "Dithering disabled on $off_count display(s)"
    else
        log_warn "Could not verify — check $DITHERING_LOG"
    fi

    printf '\n  %bVerify with:%b ioreg -lw0 | grep enableDither\n' "$DIM" "$RESET"
    printf '  %bLog:%b %s\n' "$DIM" "$RESET" "~${DITHERING_LOG#"$HOME"}"

    wait_enter
    crumb_pop
}

dithering_uninstall() {
    clear
    crumb_push "Re-enable"

    _dithering_check_arch || { wait_enter; crumb_pop; return; }

    if [[ ! -f "$DITHERING_PLIST" && ! -x "$DITHERING_BIN" ]]; then
        log_info "Dithering daemon not installed"
        wait_enter
        crumb_pop
        return
    fi

    log_info "This removes the daemon and re-enables dithering"
    printf '\n'
    if ! confirm "Continue?" "y"; then crumb_pop; return; fi

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would bootout: gui/$UID/$DITHERING_LABEL"
        log_info "Dry run — would remove: $DITHERING_PLIST"
        log_info "Dry run — would remove: $DITHERING_BIN"
        log_info "Dry run — would remove: $DITHERING_LOG"
        log_info "Dry run — would run: stillcolord --enable"
        wait_enter
        crumb_pop
        return
    fi

    launchd_unload "$DITHERING_LABEL"
    log_ok "LaunchAgent stopped"

    if [[ -x "$DITHERING_BIN" ]]; then
        "$DITHERING_BIN" --enable 2>/dev/null || true
        log_ok "Dithering re-enabled (effective immediately)"
    fi

    rm -f "$DITHERING_PLIST" "$DITHERING_BIN" "$DITHERING_LOG"
    log_ok "Removed daemon and LaunchAgent"
    log_info "Reboot for full reset of all display properties"

    wait_enter
    crumb_pop
}

dithering_status() {
    clear
    crumb_push "Status"

    if [[ "$ARCH" != "arm64" ]]; then
        log_err "Dithering disable requires Apple Silicon (M1+)"
        wait_enter
        crumb_pop
        return
    fi

    local daemon_status="not installed"
    if [[ -f "$DITHERING_PLIST" ]]; then
        if launchd_is_loaded "$DITHERING_LABEL"; then
            daemon_status="running"
        else
            daemon_status="installed (not running)"
        fi
    fi

    local off_count on_count
    off_count=$(/usr/sbin/ioreg -lw0 2>/dev/null | grep -c '"enableDither" = No' || true)
    on_count=$(/usr/sbin/ioreg -lw0 2>/dev/null | grep -c '"enableDither" = Yes' || true)

    show_info_box "Dithering Status" \
        "Daemon:               $daemon_status" \
        "Dithering disabled:   $off_count display(s)" \
        "Dithering active:     $on_count display(s)"

    # A leftover log with no daemon is stale — showing it only misleads
    if [[ -f "$DITHERING_LOG" && "$daemon_status" != "not installed" ]]; then
        printf '\n  %bRecent log:%b\n' "$DIM" "$RESET"
        tail -n 5 "$DITHERING_LOG" 2>/dev/null | sed 's/^/    /'
    fi

    wait_enter
    crumb_pop
}

dithering_menu() {
    crumb_push "Dithering"
    while true; do
        clear

        local installed=false
        [[ -f "$DITHERING_PLIST" ]] && installed=true

        local items=()
        if $installed; then
            items+=("Re-enable Dithering")
        else
            items+=("Disable Dithering")
        fi
        items+=("Status" "Back")

        local choice
        choice=$(show_menu "Dithering" "${items[@]}")

        case "$choice" in
            1) if $installed; then dithering_uninstall; else dithering_install; fi ;;
            2) dithering_status ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}
